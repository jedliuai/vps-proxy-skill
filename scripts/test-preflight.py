#!/usr/bin/env python3
"""Readiness policy tests; no SSH, packages, firewall or real credentials."""
import importlib.util
from pathlib import Path
import unittest


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[1] / "deploy" / "preflight.py"
        self.assertTrue(path.is_file(), "Deployment is missing its read-only readiness gate")
        spec = importlib.util.spec_from_file_location("proxy_preflight", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.config = dict(DOMAIN="node.customer.net", SUB_DOMAIN="sub.customer.net",
                           ADMIN_USER="deploy", ADMIN_SSH_VERIFIED="1",
                           HOST_CHANGES_APPROVED="1", ACME_TOS_ACCEPTED="1")
        self.facts = dict(os_id="debian", os_version="13", arch="x86_64", euid=0,
                          systemd=True, admin_uid=1000, ssh_ports=[22], listeners=[],
                          existing_stack=False)

    def errors(self, **changes):
        return self.module.validate({**self.config, **changes}, self.facts)

    def test_ready_host_allowed(self):
        self.assertEqual(self.errors(), [])

    def test_missing_domains_rejected(self):
        for key in ("DOMAIN", "SUB_DOMAIN"):
            with self.subTest(key=key):
                self.assertIn("domains", self.errors(**{key: ""}))

    def test_example_ip_and_injection_domains_rejected(self):
        for domain in ("node.example.com", "node.invalid", "127.0.0.1", "-a.net",
                       "a..net", "node.net;touch /tmp/x", "node.net\n", "localhost"):
            with self.subTest(domain=domain):
                self.assertIn("domains", self.errors(DOMAIN=domain))

    def test_direct_subscription_allows_same_domain(self):
        self.assertEqual(self.errors(SUB_DOMAIN="node.customer.net"), [])

    def test_root_missing_admin_and_unverified_access_rejected(self):
        self.assertIn("admin", self.errors(ADMIN_USER="root"))
        self.assertIn("admin", self.errors(ADMIN_USER=""))
        self.assertIn("ssh-proof", self.errors(ADMIN_SSH_VERIFIED="0"))
        self.facts["admin_uid"] = None
        self.assertIn("admin", self.errors())

    def test_authorization_and_acme_terms_required(self):
        self.assertIn("host-approval", self.errors(HOST_CHANGES_APPROVED="0"))
        self.assertIn("acme-terms", self.errors(ACME_TOS_ACCEPTED="0"))

    def test_unsupported_platforms_rejected(self):
        for key, value in (("os_id", "ubuntu"), ("os_version", "12"),
                           ("arch", "aarch64"), ("systemd", False), ("euid", 1000)):
            with self.subTest(key=key):
                self.assertIn("platform", self.module.validate(self.config, {**self.facts, key: value}))

    def test_nonstandard_or_unknown_ssh_port_rejected(self):
        for ports in ([2222], [], [22, 2222]):
            self.facts["ssh_ports"] = ports
            self.assertIn("ssh-port", self.errors())

    def test_existing_unrelated_listeners_rejected(self):
        self.facts["listeners"] = [80, 443]
        self.assertIn("port-conflict", self.errors())
        self.facts["existing_stack"] = True
        self.assertNotIn("port-conflict", self.errors())

    def test_arbitrary_non_proxy_listeners_not_silently_firewalled(self):
        self.facts["listeners"] = [22, 5432]
        self.assertIn("other-services", self.errors())

    def test_ops_agent_opt_in_is_boolean(self):
        self.assertEqual(self.errors(DISABLE_GOOGLE_OPS_AGENT="0"), [])
        self.assertEqual(self.errors(DISABLE_GOOGLE_OPS_AGENT="1"), [])
        self.assertIn("ops-option", self.errors(DISABLE_GOOGLE_OPS_AGENT="yes"))

    def test_mistyped_readonly_option_does_not_fall_through_to_deploy(self):
        self.assertIn("preflight-option", self.errors(PREFLIGHT_ONLY="yes"))
        self.assertEqual(self.errors(PREFLIGHT_ONLY="1"), [])


if __name__ == "__main__":
    unittest.main()
