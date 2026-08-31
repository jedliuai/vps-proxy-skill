#!/usr/bin/env python3
"""One-time 443 -> 10443 migration. No installs, credential rotation or HY2 restart.

Run as root with check/apply, or rollback /root/proxy-trojan-port-<suffix>.
Cloudflare KV is deliberately a separate step after the home-client test.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import signal
import subprocess
import sys
import tempfile
import time

FILES = {
    'xray': Path('/etc/xray/config.json'),
    'firewall': Path('/etc/proxy-stack/firewall.nft'),
    'clash': Path('/var/lib/proxy-subscription/clash.yaml'),
    'v2ray': Path('/var/lib/proxy-subscription/v2ray.txt'),
}
PROTECTED = (Path('/etc/hysteria/config.yaml'), Path('/etc/proxy-stack/secrets.env'),
             Path('/etc/proxy-stack/subscription-urls.txt'))


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError('Unexpected configuration shape; refusing migration')
    return text.replace(before, after, 1)


def transform(old):
    new = dict(old)
    data = json.loads(old['xray'])
    trojans = [i for i in data['inbounds'] if i.get('protocol') == 'trojan']
    if len(trojans) != 1 or trojans[0].get('port') != 443:
        raise ValueError('Expected exactly one Trojan inbound on 443')
    if any(i.get('port') == 10443 for i in data['inbounds']):
        raise ValueError('Target port already configured')
    trojans[0]['port'] = 10443
    new['xray'] = json.dumps(data, indent=2) + '\n'
    new['firewall'] = replace_once(old['firewall'],
        'tcp dport 443 ct state new limit rate 60/second burst 120 packets accept',
        'tcp dport 10443 ct state new limit rate 60/second burst 120 packets accept')
    new['firewall'] = replace_once(new['firewall'], 'tcp dport 443 drop', 'tcp dport 10443 drop')
    # Operate on one named YAML block, preserving every other byte/node/rule.
    block = re.search(r'(?m)^  - name: US-Trojan\r?\n(?:(?!  - name:).*(?:\n|$))*', old['clash'])
    if not block or old['clash'].count('  - name: US-Trojan\n') != 1:
        raise ValueError('Expected one named Trojan YAML block')
    updated = replace_once(block.group(), '    port: 443\n', '    port: 10443\n')
    new['clash'] = old['clash'][:block.start()] + updated + old['clash'][block.end():]
    uri_text = base64.b64decode(old['v2ray'].strip(), validate=True).decode()
    lines = uri_text.splitlines(keepends=True)
    indices = [n for n, line in enumerate(lines) if line.startswith('trojan://')]
    if len(indices) != 1:
        raise ValueError('Expected one Trojan subscription URI')
    index = indices[0]
    lines[index] = replace_once(lines[index], ':443?', ':10443?')
    new['v2ray'] = base64.b64encode(''.join(lines).encode()).decode()
    return new


def run(*args, input=None):
    result = subprocess.run(args, input=input, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=40)
    if result.returncode:
        # Never print command output: config validators may echo credentials.
        raise RuntimeError(f'Command failed: {args[0]} {args[1]} (details withheld)')
    return result.stdout.strip()


def put(path, text):
    """Atomic replacement retaining the live file's ownership and permissions."""
    info = path.stat()
    fd, temporary = tempfile.mkstemp(prefix='.trojan-port-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            os.fchmod(output.fileno(), info.st_mode & 0o777)
            os.fchown(output.fileno(), info.st_uid, info.st_gid)
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def firewall(text, check=False):
    # One nft transaction: no delete/reload gap, no changes to other tables.
    args = ('/usr/sbin/nft', '-c', '-f', '-') if check else ('/usr/sbin/nft', '-f', '-')
    run(*args, input='delete table inet proxy_guard\n' + text)


def healthy():
    for unit in ('xray', 'hysteria-server', 'nginx', 'proxy-firewall'):
        run('systemctl', 'is-active', unit)
    pid = run('systemctl', 'show', 'hysteria-server', '-p', 'MainPID', '--value')
    if not pid.isdigit() or int(pid) == 0:
        raise RuntimeError('Hysteria has no running process')
    return pid


def wait_ports(ports):
    deadline = time.monotonic() + 8
    for port in ports:
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=1):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Xray listeners did not become ready') from None
                time.sleep(0.2)


def restore(backup):
    original = {key: (backup / key).read_text() for key in FILES}
    firewall(original['firewall'], check=True)
    for key, path in FILES.items():
        put(path, original[key])
    firewall(original['firewall'])
    run('systemctl', 'restart', 'xray')
    wait_ports((443, 2053))
    healthy()


def apply_changes(new, backup, protected, hy2_pid):
    try:
        for key, path in FILES.items():
            put(path, new[key])
        firewall(new['firewall'])
        run('systemctl', 'restart', 'xray')
        wait_ports((10443, 2053))
        if healthy() != hy2_pid:
            raise RuntimeError('Hysteria process changed')
        for p in PROTECTED:
            if hashlib.sha256(p.read_bytes()).hexdigest() != protected[str(p)]:
                raise RuntimeError('Protected file changed')
    except BaseException:
        # Catch interruption as well as failures. Ignore additional termination
        # signals while restoring; SIGKILL/power loss still need manual rollback.
        for sig in (signal.SIGINT, signal.SIGTERM, getattr(signal, 'SIGHUP', None)):
            if sig is not None:
                signal.signal(sig, signal.SIG_IGN)
        try:
            restore(backup)
        except BaseException:
            raise RuntimeError(f'Automatic rollback failed; preserve and restore backup {backup}') from None
        raise RuntimeError('Migration failed and original files/services were restored') from None


def interrupted(signum, frame):
    raise KeyboardInterrupt()


def main():
    import fcntl
    if os.geteuid() != 0:
        raise RuntimeError('Root is required')
    action = sys.argv[1] if len(sys.argv) > 1 else 'check'
    if action not in ('check', 'apply', 'rollback'):
        raise ValueError('Use check, apply, or rollback BACKUP')
    os.umask(0o077)
    with open('/var/lock/proxy-stack-bootstrap.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if action == 'rollback':
            backup = Path(sys.argv[2]).resolve(strict=True)
            if backup.parent != Path('/root') or not backup.name.startswith('proxy-trojan-port-'):
                raise ValueError('Invalid backup directory')
            restore(backup)
            print('Rollback complete; remember to restore Cloudflare KV if already published.')
            return
        hy2_pid = healthy()
        old = {key: path.read_text() for key, path in FILES.items()}
        new = transform(old)
        protected = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in PROTECTED}
        with socket.socket() as probe:
            probe.bind(('0.0.0.0', 10443))
        with tempfile.TemporaryDirectory(prefix='proxy-trojan-check-', dir='/root') as stage:
            candidate = Path(stage) / 'xray.json'
            candidate.write_text(new['xray'])
            run('/usr/local/bin/xray', 'run', '-test', '-c', str(candidate))
            firewall(new['firewall'], check=True)
        if action == 'check':
            print('Preflight passed: 10443 free; Xray/nft candidates valid; other nodes unchanged.')
            return
        backup = Path(tempfile.mkdtemp(prefix='proxy-trojan-port-', dir='/root'))
        for key, content in old.items():
            (backup / key).write_text(content)
        (backup / 'protected-hashes.json').write_text(json.dumps(protected))
        print(f'Backup: {backup}', flush=True)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, interrupted)
        apply_changes(new, backup, protected, hy2_pid)
        print('Applied: Trojan10443; original credentials/URLs/HY2 unchanged; test home client before KV publish.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Migration stopped: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
