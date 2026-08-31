"""Run with python scripts/test-trojan-migration.py; fixtures contain no credentials."""
import base64
import importlib.util
import json
import pathlib
import unittest
from unittest.mock import patch, Mock

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'deploy/migrate-trojan-port.py'


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.exists(), 'Port migration implementation is missing')
        spec = importlib.util.spec_from_file_location('migration', SOURCE)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.old = {
            'xray': json.dumps({'inbounds': [
                {'protocol': 'trojan', 'port': 443, 'settings': {'clients': [{'password': 'fixture'}]}},
                {'protocol': 'vless', 'port': 2053, 'settings': {'clients': [{'id': 'fixture'}]}},
            ], 'outbounds': [{'protocol': 'freedom'}]}),
            'firewall': 'table inet proxy_guard {\n tcp dport 443 ct state new limit rate 60/second burst 120 packets accept\n tcp dport 443 drop\n tcp dport 2053 drop\n udp dport 443 accept\n}\n',
            'clash': 'proxies:\n  - name: US-Hysteria2\n    type: hysteria2\n    port: 443\n  - name: US-Trojan\n    type: trojan\n    server: example.invalid\n    port: 443\n    password: fixture\n  - name: US-Reality\n    type: vless\n    port: 2053\n',
            'v2ray': base64.b64encode(b'hysteria2://fixture@example.invalid:443/#US-Hysteria2\ntrojan://fixture@example.invalid:443?security=tls#US-Trojan\nvless://fixture@example.invalid:2053?security=reality#US-Reality\n').decode(),
        }

    def test_changes_only_trojan_and_preserves_other_nodes(self):
        new = self.module.transform(self.old)
        original = json.loads(self.old['xray'])
        actual = json.loads(new['xray'])
        self.assertEqual(actual['inbounds'][0]['port'], 10443)
        actual['inbounds'][0]['port'] = 443
        self.assertEqual(actual, original)
        self.assertIn('tcp dport 10443 ct state new', new['firewall'])
        self.assertNotIn('tcp dport 443 ct state new', new['firewall'])
        self.assertIn('udp dport 443 accept', new['firewall'])
        self.assertEqual(new['firewall'].replace('tcp dport 10443 ', 'tcp dport 443 '), self.old['firewall'])
        self.assertEqual(new['clash'].replace('port: 10443', 'port: 443'), self.old['clash'])
        self.assertIn('port: 10443', new['clash'])
        lines = base64.b64decode(new['v2ray']).decode().splitlines()
        self.assertEqual(lines[0], 'hysteria2://fixture@example.invalid:443/#US-Hysteria2')
        self.assertEqual(lines[1], 'trojan://fixture@example.invalid:10443?security=tls#US-Trojan')
        self.assertEqual(lines[2], 'vless://fixture@example.invalid:2053?security=reality#US-Reality')

    def test_rejects_missing_or_duplicate_trojan(self):
        for inbounds in ([], [{'protocol': 'trojan', 'port': 443}] * 2):
            with self.subTest(inbounds=inbounds):
                self.old['xray'] = json.dumps({'inbounds': inbounds})
                with self.assertRaises(ValueError):
                    self.module.transform(self.old)

    def test_rejects_port_conflict_and_repeat_migration(self):
        data = json.loads(self.old['xray'])
        data['inbounds'][1]['port'] = 10443
        self.old['xray'] = json.dumps(data)
        with self.assertRaises(ValueError):
            self.module.transform(self.old)
        data['inbounds'][1]['port'] = 2053
        data['inbounds'][0]['port'] = 10443
        self.old['xray'] = json.dumps(data)
        with self.assertRaises(ValueError):
            self.module.transform(self.old)

    def test_rejects_subscription_and_firewall_drift_before_changes(self):
        for key in ('clash', 'v2ray', 'firewall'):
            with self.subTest(key=key):
                original = self.old[key]
                self.old[key] = ''
                with self.assertRaises(ValueError):
                    self.module.transform(self.old)
                self.old[key] = original

    def test_health_requires_every_service_and_nonzero_hysteria_pid(self):
        self.assertTrue(hasattr(self.module, 'healthy'), 'Per-service health gate missing')
        def response(*args, **kwargs):
            if args == ('systemctl', 'is-active', 'hysteria-server'):
                raise RuntimeError('hysteria inactive')
            return '100'
        with patch.object(self.module, 'run', side_effect=response):
            with self.assertRaises(RuntimeError):
                self.module.healthy()
        with patch.object(self.module, 'run', return_value='0'):
            with self.assertRaises(RuntimeError):
                self.module.healthy()

    def test_listener_wait_retries_refusal_then_checks_both_ports(self):
        self.assertTrue(hasattr(self.module, 'wait_ports'), 'Bounded readiness check missing')
        opened=[]
        def connect(address, **kwargs):
            opened.append(address[1])
            if len(opened) == 1:
                raise ConnectionRefusedError()
            client=Mock()
            client.__enter__=Mock(return_value=client)
            client.__exit__=Mock(return_value=False)
            return client
        with patch.object(self.module.socket, 'create_connection', side_effect=connect), patch.object(self.module.time, 'sleep'):
            self.module.wait_ports((10443,2053))
        self.assertEqual(opened, [10443,10443,2053])

    def test_failed_writes_firewall_restart_and_interrupt_restore(self):
        self.assertTrue(hasattr(self.module, 'apply_changes'), 'Rollback transaction missing')
        for failing_stage, failure in [('put', RuntimeError('write failed')), ('firewall', RuntimeError('nft failed')),
                                       ('run', RuntimeError('restart failed')), ('put', KeyboardInterrupt())]:
            with self.subTest(stage=failing_stage, interruption=isinstance(failure, KeyboardInterrupt)):
                with patch.object(self.module, 'put') as put, patch.object(self.module, 'firewall') as firewall, patch.object(self.module, 'run') as run, patch.object(self.module, 'restore') as restore:
                    {'put':put, 'firewall':firewall, 'run':run}[failing_stage].side_effect=failure
                    with self.assertRaises(RuntimeError):
                        self.module.apply_changes(self.old, pathlib.Path('fixture-backup'), {}, '123')
                    restore.assert_called_once_with(pathlib.Path('fixture-backup'))


if __name__ == '__main__':
    unittest.main()
