#!/usr/bin/env python3
"""Read-only, fail-closed gate for the Debian 13/amd64 bootstrap.

The confirmation flags are attestations, not substitutes for a second SSH
session or user approval. No files, services, DNS or cloud resources are changed.
"""
import ipaddress
import os
from pathlib import Path
import platform
import re
import subprocess
import sys


MESSAGES = {
    "domains": "Set your real DOMAIN and SUB_DOMAIN (use DOMAIN for both in direct-only mode); example domains/IPs are refused.",
    "platform": "This bootstrap requires root on Debian 13 x86_64 with systemd. Do not bypass the gate on other platforms.",
    "admin": "ADMIN_USER must be an existing non-root administrator, not a service account.",
    "ssh-proof": "Verify a NEW non-root, key-only SSH session and sudo first; then set ADMIN_SSH_VERIFIED=1.",
    "ssh-port": "Only SSH port 22 is supported by this firewall; inspect sshd and socket activation before proceeding.",
    "host-approval": "Obtain approval for the host changes listed in the skill, then set HOST_CHANGES_APPROVED=1.",
    "acme-terms": "Obtain acceptance of Let's Encrypt terms, then set ACME_TOS_ACCEPTED=1.",
    "port-conflict": "A fresh host has listeners on proxy/web ports. Inspect ownership; do not overwrite another service.",
    "other-services": "Other public listeners would be blocked by this firewall. Use a dedicated host or design an explicit adaptation.",
    "ops-option": "DISABLE_GOOGLE_OPS_AGENT must be 0 or 1; the default preserves the agent.",
    "preflight-option": "PREFLIGHT_ONLY must be 0 or 1; an invalid read-only flag must never trigger a deployment.",
}


def valid_domain(value):
    if not isinstance(value, str) or len(value) > 253:
        return False
    if not re.fullmatch(r"(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}", value):
        return False
    domain = value.lower()
    return not any(domain == suffix or domain.endswith("." + suffix)
                   for suffix in ("example.com", "example.net", "example.org", "invalid", "test", "localhost", "example"))


def validate(config, facts):
    errors = []
    if not all(valid_domain(config.get(key, "")) for key in ("DOMAIN", "SUB_DOMAIN")):
        errors.append("domains")
    if (facts.get("os_id") != "debian" or facts.get("os_version") != "13"
            or facts.get("arch") != "x86_64" or facts.get("euid") != 0 or not facts.get("systemd")):
        errors.append("platform")
    admin = config.get("ADMIN_USER", "")
    uid = facts.get("admin_uid")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", admin) or admin == "root" or uid is None or uid < 1000:
        errors.append("admin")
    if config.get("ADMIN_SSH_VERIFIED") != "1":
        errors.append("ssh-proof")
    if facts.get("ssh_ports") != [22]:
        errors.append("ssh-port")
    if config.get("HOST_CHANGES_APPROVED") != "1":
        errors.append("host-approval")
    if config.get("ACME_TOS_ACCEPTED") != "1":
        errors.append("acme-terms")
    if config.get("DISABLE_GOOGLE_OPS_AGENT", "0") not in ("0", "1"):
        errors.append("ops-option")
    if config.get("PREFLIGHT_ONLY", "0") not in ("0", "1"):
        errors.append("preflight-option")
    proxy_ports = {80, 443, 2053, 8080, 8443, 10443}
    try:
        proxy_ports.add(int(config.get("XRAY_PORT", "2053")))
    except ValueError:
        pass  # Bootstrap separately validates the port before reaching this gate.
    listeners = set(facts.get("listeners", []))
    if listeners & proxy_ports and not facts.get("existing_stack"):
        errors.append("port-conflict")
    if listeners - proxy_ports - {22, 68, 546}:
        errors.append("other-services")
    return errors


def run_readonly(*args):
    result = subprocess.run(args, check=True, capture_output=True, text=True, timeout=10)
    return result.stdout


def collect(config):
    release = {}
    for line in Path("/etc/os-release").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            release[key] = value.strip('"')
    import pwd  # Linux-only collector; policy tests also run on Windows.
    try:
        admin_uid = pwd.getpwnam(config.get("ADMIN_USER", "")).pw_uid
    except KeyError:
        admin_uid = None
    ssh_config = run_readonly("/usr/sbin/sshd", "-T")
    ssh_ports = sorted({int(line.split()[1]) for line in ssh_config.splitlines() if line.startswith("port ")})
    listeners = []
    for line in run_readonly("ss", "-H", "-lntup").splitlines():
        fields = line.split()
        address, port = fields[4].rsplit(":", 1)
        try:
            if ipaddress.ip_address(address.strip("[]").split("%")[0]).is_loopback:
                continue
        except ValueError:
            pass  # Wildcard bind.
        listeners.append(int(port))
    return dict(os_id=release.get("ID"), os_version=release.get("VERSION_ID"),
                arch=platform.machine(), euid=os.geteuid(), systemd=Path("/run/systemd/system").is_dir(),
                admin_uid=admin_uid, ssh_ports=ssh_ports, listeners=listeners,
                existing_stack=Path("/etc/proxy-stack/secrets.env").is_file()
                and Path("/etc/xray/config.json").is_file())


def main():
    try:
        errors = validate(os.environ, collect(os.environ))
    except (OSError, ValueError, IndexError, ImportError, subprocess.SubprocessError):
        print("BLOCKED: unable to inspect host safely (requires Linux, root, OpenSSH and iproute2).", file=sys.stderr)
        return 1
    for error in errors:
        print(f"BLOCKED [{error}]: {MESSAGES[error]}", file=sys.stderr)
    if errors:
        return 1
    print("Readiness gate passed. DNS, cloud firewall, fresh SSH proof and recovery access still require independent verification.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
