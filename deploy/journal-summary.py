#!/usr/bin/env python3
"""Read bounded journals on the host; return counts, never log text or identifiers."""
import argparse
from datetime import datetime, timezone
import json
import subprocess

UNITS = ('xray', 'hysteria-server', 'nginx', 'proxy-firewall', 'certbot')
CATEGORIES = {
    'accepted': ('accepted ',),
    'rejected': ('rejected ',),
    'connected': ('client connected',),
    'disconnected': ('client disconnected',),
    'timeout': ('timeout', 'timed out', 'no recent network activity'),
    'dns_error': ('no such host', 'temporary failure in name resolution', 'dns error'),
    'transport_closed': ('transport closed', 'stream canceled', 'stream cancelled'),
    'buffer_warning': ('receive buffer size', 'send buffer size', 'buffer space'),
    'resource_error': ('out of memory', 'too many open files', 'no space left'),
    'service_transition': ('starting ', 'started ', 'stopping ', 'stopped ', 'main process exited'),
}

def decode_message(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list) and value:
        if all(type(x) is int and 0 <= x <= 255 for x in value):
            return bytes(value).decode('utf-8', errors='replace')
        if all(isinstance(x, str) for x in value):
            return '\n'.join(value)
    return None

def utc_timestamp(value):
    try:
        return datetime.fromtimestamp(int(value) / 1_000_000, timezone.utc).isoformat()
    except (ValueError, TypeError, OverflowError, OSError):
        return None

def summarize(lines, limit):
    result = {'entries': 0, 'malformed_entries': 0, 'unreadable_messages': 0,
              'observed_first_utc': None, 'observed_last_utc': None,
              'record_limit_reached': False, 'categories': dict.fromkeys(CATEGORIES, 0)}
    timestamps = []
    for line in lines:
        if not line.strip():
            continue
        try:
            record = json.loads(line)
            if not isinstance(record, dict):
                raise ValueError('not an object')
        except (ValueError, TypeError):
            result['malformed_entries'] += 1
            continue
        result['entries'] += 1
        stamp = utc_timestamp(record.get('__REALTIME_TIMESTAMP'))
        if stamp:
            timestamps.append(stamp)
        message = decode_message(record.get('MESSAGE'))
        if message is None:
            result['unreadable_messages'] += 1
            continue
        message = message.lower()
        for category, needles in CATEGORIES.items():
            if any(needle in message for needle in needles):
                result['categories'][category] += 1
    if timestamps:
        result['observed_first_utc'] = min(timestamps)
        result['observed_last_utc'] = max(timestamps)
    result['record_limit_reached'] = result['entries'] + result['malformed_entries'] >= limit
    return result

def collect(unit, days, limit):
    try:
        proc = subprocess.run(['journalctl', '--no-pager', '-o', 'json', '-u', unit,
                               '--since', f'{days} days ago', '-n', str(limit)],
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=20)
        if proc.returncode != 0:
            return {'read_ok': False}
        return {'read_ok': True, **summarize(proc.stdout.splitlines(), limit)}
    except (OSError, subprocess.TimeoutExpired):
        return {'read_ok': False}

def bounded_number(low, high):
    def parse(value):
        number = int(value)
        if not low <= number <= high:
            raise argparse.ArgumentTypeError(f'must be between {low} and {high}')
        return number
    return parse

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--since-days', type=bounded_number(1, 30), default=7)
    parser.add_argument('--lines', type=bounded_number(1, 20000), default=2000)
    args = parser.parse_args()
    print(json.dumps({'schema': 1, 'requested_days': args.since_days, 'limit_per_unit': args.lines,
                      'counts_overlap': True, 'units': {unit: collect(unit, args.since_days, args.lines) for unit in UNITS}}))

if __name__ == '__main__':
    main()
