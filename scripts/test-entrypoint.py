#!/usr/bin/env python3
"""Exercise local wrapper guards in a disposable repo with SSH/SCP intercepted."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class EntrypointTests(unittest.TestCase):
    def invoke(self, arguments, remote_stub="throw 'REMOTE_CALLED'"):
        with tempfile.TemporaryDirectory(prefix="proxy-entry-test-") as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            source = Path(__file__).resolve().parent / "vps-proxy.ps1"
            target = root / "scripts" / source.name
            shutil.copyfile(source, target)
            shutil.copytree(source.parent.parent / "deploy", root / "deploy")
            # SSH/SCP are intercepted; no network operation is possible.
            command = ("function ssh { " + remote_stub + " }; function scp { throw 'REMOTE_CALLED' }; "
                       "& '" + str(target).replace("'", "''") + "' " + arguments)
            env = {k: v for k, v in os.environ.items() if not k.startswith("VPS_")}
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", command],
                                    capture_output=True, text=True, encoding="utf-8", env=env, timeout=20)
            return result.returncode, result.stdout + result.stderr

    def test_no_config_never_contacts_an_authors_host(self):
        code, output = self.invoke("-Action check")
        self.assertNotEqual(code, 0)
        self.assertNotIn("REMOTE_CALLED", output)
        self.assertIn("SshHost", output)

    def test_missing_domain_rejected_before_remote_access(self):
        code, output = self.invoke("-Action check -SshHost test-host")
        self.assertNotEqual(code, 0)
        self.assertNotIn("REMOTE_CALLED", output)
        self.assertIn("Domain", output)

    def test_deploy_requires_ssh_proof_before_upload(self):
        code, output = self.invoke("-Action deploy -SshHost test-host -Domain node.customer.net")
        self.assertNotEqual(code, 0)
        self.assertNotIn("REMOTE_CALLED", output)
        self.assertIn("Admin", output)

    def test_readonly_status_does_not_require_deploy_attestations(self):
        code, output = self.invoke("-Action status -SshHost test-host -Domain node.customer.net")
        self.assertNotEqual(code, 0)
        self.assertIn("REMOTE_CALLED", output)

    def test_status_does_not_read_raw_journal(self):
        stub = "if (($args -join ' ') -match 'journalctl|--full status') { throw 'RAW_LOGS_REQUESTED' }; $global:LASTEXITCODE = 0; 'SAFE_STATUS'"
        code, output = self.invoke('-Action status -SshHost test-host -Domain node.customer.net', stub)
        self.assertEqual(code, 0, output)
        self.assertIn('SAFE_STATUS', output)

    def test_logs_pipe_the_safe_helper_and_return_json(self):
        stub = "if (($input -join '') -notmatch 'def decode_message') { throw 'HELPER_NOT_PIPED' }; $global:LASTEXITCODE = 0; '{\"schema\":1,\"units\":{},\"observed_first_utc\":\"2026-10-10T13:00:00+00:00\"}'"
        code, output = self.invoke('-Action logs -SshHost test-host -Domain node.customer.net', stub)
        self.assertEqual(code, 0, output)
        result = json.loads(output)
        self.assertEqual(result['schema'], 1)
        self.assertEqual(result['observed_first_utc'], '2026-10-10T13:00:00+00:00')

    def test_logs_failure_and_invalid_json_do_not_echo_output(self):
        for exit_code in (0, 1):
            stub = f"$global:LASTEXITCODE = {exit_code}; 'fixture-private-remote-output'"
            code, output = self.invoke('-Action logs -SshHost test-host -Domain node.customer.net', stub)
            self.assertNotEqual(code, 0)
            self.assertNotIn('fixture-private-remote-output', output)
            self.assertIn('no remote output was displayed', output)

    def test_logs_transport_exception_does_not_echo_details(self):
        code, output = self.invoke('-Action logs -SshHost test-host -Domain node.customer.net', "throw 'fixture-private-remote-error'")
        self.assertNotEqual(code, 0)
        self.assertNotIn('fixture-private-remote-error', output)
        self.assertIn('no remote output was displayed', output)


if __name__ == "__main__":
    unittest.main()
