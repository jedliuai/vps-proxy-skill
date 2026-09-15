# VPS Proxy Skill

[中文](./README.md) · [Quick start](#quick-start) · [Releases](https://github.com/jedliuai/vps-proxy-skill/releases) · [Skill](./skill/vps-proxy-builder/SKILL.md)

**Give Codex a repository, not a pile of VPS setup tutorials.**

VPS Proxy Skill combines one Codex skill with deployment scripts, tests and incident playbooks. It guides authorized SSH preparation, Hysteria2 / Trojan / VLESS REALITY deployment, client verification and recovery on your own server. It produces Clash / Mihomo YAML and V2Ray / Shadowrocket URI subscriptions—not free nodes or a hosted VPN service.

[![Repository checks](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml/badge.svg)](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml)
[Preview release: v0.1.0-preview.1](https://github.com/jedliuai/vps-proxy-skill/releases/tag/v0.1.0-preview.1)

## Who is this for?

People who control a dedicated VPS and want Codex to handle the technical setup without reconstructing SSH, TLS, firewall and subscription instructions. Existing installations can use the diagnosis workflow without reinstalling the stack.

The useful part is the complete lifecycle: **prepare → authorize → deploy → verify → maintain**. Source and tests make the workflow inspectable; safety gates and incident playbooks help avoid treating a reinstall as the answer to every failure.

## Quick start

Bring a dedicated **Debian 13 / x86_64 / systemd / SSH port 22 / public IPv4** server, a domain you control, and Codex with terminal and network access. Codex can guide SSH setup. You handle purchases, sign-in, MFA, authorization and client checks it cannot perform remotely.

Paste this into Codex:

```text
Use https://github.com/jedliuai/vps-proxy-skill to set up a private proxy on my VPS.
Get the full repository, then read AGENTS.md and skill/vps-proxy-builder/SKILL.md.
Check prerequisites and help with SSH; never ask for private-key contents.
Explain the target and changes, obtain my approval, then carry out the approved work.
Verify direct subscriptions first; Cloudflare is optional.
Preserve existing services and keep credentials outside Git and public logs.
Deliver private client-labelled subscription entries, verified/unverified results,
and maintenance/recovery instructions. Pause when new authority is needed.
```

No global skill installation is necessary. Open the full checkout as a Codex project: `AGENTS.md` explicitly points to the singular `skill/` directory. The skill alone is not a standalone installer.

For a reproducible preview instead of the moving default branch:

```sh
git clone --branch v0.1.0-preview.1 https://github.com/jedliuai/vps-proxy-skill.git
cd vps-proxy-skill
```

The release includes source downloads, but Git cloning is recommended because repository checks use Git's file inventory. Updating this toolkit does **not** mean redeploying a working server.

Git and OpenSSH capabilities are needed. A GitHub connector is optional. Cloudflare tools are only needed if you choose Cloudflare subscription delivery. Codex does not need to be installed on the VPS.

## What you receive

| Client | Private delivery | Important difference |
| --- | --- | --- |
| Clash Verge / Mihomo-compatible clients | Clash YAML subscription | Routing and fallback groups |
| v2rayN / v2rayNG / Shadowrocket | URI / Base64 subscription | No automatic transfer of Clash routing groups |

Each client/core must support the selected protocol. The handoff also records protocol tests, certificate renewal, versions and recovery instructions. See the [illustrative handoff](./docs/handoff-example.md): it contains no working subscriptions or claimed test results.

## Boundaries before you deploy

- This is an early preview, not a managed service or an unattended-success guarantee.
- ARM, Ubuntu, custom SSH ports, IPv6-only/NAT-only and shared business hosts require separate adaptation. Do not bypass preflight.
- Bootstrap changes services, firewall and SSH settings. Verify a new non-root key login and sudo, preserve console access, and review the [deployment reference](./skill/vps-proxy-builder/references/deployment.md). Backups are not transactional full-system rollback.
- Three protocols share one server and exit location. Cloudflare distributes subscriptions; it does not carry or improve the main proxy data path.
- Often called a “self-hosted VPN,” this deploys application proxies, not WireGuard/OpenVPN. Templates assume China-oriented routing; adapt policies and region labels to the user.
- Users pay their own VPS, IP, bandwidth, domain, optional Cloudflare and Codex costs. No promise of unrestricted access to third-party sites.

## Evidence and maintenance

CI checks secret patterns, deployment invariants, the Worker, preflight, entrypoint and port migration. **A green check is not proof of a fresh VPS deployment or reliability on your home network.** Every host needs new protocol/client acceptance evidence.

```text
pwsh scripts/validate-repo.ps1
python -B scripts/test-preflight.py
python -B scripts/test-entrypoint.py
python -B scripts/test-trojan-migration.py
git diff --check
```

These checks do not connect to a VPS. Operational references are currently in Chinese; Codex should explain them in your language.

[Prerequisites](./skill/vps-proxy-builder/references/prerequisites.md) · [Troubleshooting](./skill/vps-proxy-builder/references/troubleshooting.md) · [Validation](./skill/vps-proxy-builder/references/validation.md) · [Security](./SECURITY.md) · [Feedback](./CONTRIBUTING.md) · [Deployment details](./skill/vps-proxy-builder/references/deployment.md)

Maintained by [jedliuai](https://github.com/jedliuai), who builds AI-native systems for solo creators. Explore [the author's public projects](https://github.com/jedliuai?tab=repositories). Star to bookmark, watch releases for version updates, and cite the repository plus a tag/commit when sharing reproducible work. Never share your subscription credentials.

**License status:** no open-source license has been selected. Public visibility is not a blanket reuse, redistribution or commercial license. Ask the author about required permissions; see [GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
