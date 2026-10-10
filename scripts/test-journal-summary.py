#!/usr/bin/env python3
"""Journal parsing and failure paths must never expose log contents."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('journal_summary', Path(__file__).resolve().parents[1] / 'deploy/journal-summary.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class JournalSummaryTests(unittest.TestCase):
    def test_message_encodings(self):
        message = '\x1b[31mclient disconnected: timeout\x1b[0m'
        self.assertEqual(module.decode_message(list(message.encode())), message)
        self.assertEqual(module.decode_message(['one', 'two']), 'one\ntwo')
        for value in (None, [], [True], [-1], [256], [1, 'x'], {}):
            self.assertIsNone(module.decode_message(value))

    def test_redaction_and_overlapping_categories(self):
        sensitive = 'fixture-private-credential-and-address'
        message = f'client disconnected timeout no recent network activity {sensitive}'
        lines = [json.dumps({'MESSAGE': list(message.encode()), '__REALTIME_TIMESTAMP': '2000000'}),
                 json.dumps({'MESSAGE': f'accepted {sensitive}', '__REALTIME_TIMESTAMP': '1000000'})]
        result = module.summarize(lines, 2)
        self.assertEqual(result['categories']['timeout'], 1)
        self.assertEqual(result['categories']['disconnected'], 1)
        self.assertEqual(result['categories']['accepted'], 1)
        self.assertTrue(result['record_limit_reached'])
        self.assertEqual(result['observed_first_utc'], '1970-01-01T00:00:01+00:00')
        self.assertEqual(result['observed_last_utc'], '1970-01-01T00:00:02+00:00')
        self.assertNotIn(sensitive, json.dumps(result))

    def test_malformed_unreadable_and_empty_window(self):
        result = module.summarize(['invalid secret fixture', '[]', '{}', ''], 10)
        self.assertEqual(result['malformed_entries'], 2)
        self.assertEqual(result['unreadable_messages'], 1)
        self.assertIsNone(result['observed_first_utc'])
        self.assertFalse(result['record_limit_reached'])
        self.assertIsNone(module.utc_timestamp('9' * 1000))

    def test_failed_reader_never_returns_stderr(self):
        with patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, 'private stdout', 'private stderr')):
            self.assertEqual(module.collect('xray', 7, 2000), {'read_ok': False})
        with patch.object(module.subprocess, 'run', side_effect=subprocess.TimeoutExpired('private command', 20)):
            self.assertEqual(module.collect('xray', 7, 2000), {'read_ok': False})

    def test_bounded_arguments(self):
        for value in ('0', '20001'):
            with self.assertRaises(Exception):
                module.bounded_number(1, 20000)(value)
        self.assertEqual(module.bounded_number(1, 20000)('2000'), 2000)

if __name__ == '__main__':
    unittest.main()
