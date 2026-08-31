#!/usr/bin/env python3
"""Exercise local wrapper guards in a disposable repo with SSH/SCP intercepted."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class EntrypointTests(unittest.TestCase):
    def invoke(self, arguments):
        with tempfile.TemporaryDirectory(prefix="proxy-entry-test-") as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            source = Path(__file__).resolve().parent / "vps-proxy.ps1"
            target = root / "scripts" / source.name
            shutil.copyfile(source, target)
            shutil.copytree(source.parent.parent / "deploy", root / "deploy")
            # Any remote call fails visibly; no network operation is possible.
            command = ("function ssh { throw 'REMOTE_CALLED' }; function scp { throw 'REMOTE_CALLED' }; "
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


if __name__ == "__main__":
    unittest.main()
