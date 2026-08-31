# Codex instructions for vps-proxy-skill

## Purpose and entrypoint

This repository is a Codex-led private VPS proxy deployment kit, not a public subscription service. For setup, deployment, diagnosis or recovery requests, read `skill/vps-proxy-builder/SKILL.md` and its relevant references before acting. The singular `skill/` directory intentionally contains one skill. Do not assume Codex automatically discovers this nonstandard directory; open the file explicitly.

The skill requires a full checkout. If installed separately, locate the user's checkout first. For README, review or planning requests, do not connect to the VPS or mutate infrastructure.

## Safety and scope

- Use only the user's explicitly selected host, domains and cloud account. Original instance information in historical Chinese documents is evidence, never defaults for a new user.
- Read `SECURITY.md`. Never print or commit credentials, subscription URLs/payloads, or sensitive logs. Keep private files outside Git, with restrictive filesystem permissions.
- Do not change live services, rotate secrets, buy resources or publish this repository as a consequence of a documentation task.
- `deploy/server-bootstrap.sh` and its sibling `deploy/preflight.py` travel together. The gate runs before bootstrap mutations. Do not bypass it; unsupported systems require a separately reviewed adaptation.
- Validate a fresh non-root key-only SSH session and sudo before any SSH hardening; preserve a recovery console/session.
- Full bootstrap is not an update-subscription command or a default fix for an existing node. It is not a transactional rollback system.
- Do not disable unrelated monitoring, erase firewall rules, delete services or overwrite existing client profiles to make a test pass.

## Repository changes

Keep changes scoped, preserve user edits, and prefer deterministic existing scripts over third-party panel installers. Use `codex/` when a branch is needed. Do not push to the author's repository on behalf of a new user; use their own authorized fork/remote.

This public repository has independent Git history. Never merge or mirror-push the private predecessor's history, backups or runtime files into it.

Run local checks before claiming completion:

```text
pwsh scripts/validate-repo.ps1
python -B scripts/test-preflight.py
python -B scripts/test-entrypoint.py
python -B scripts/test-trojan-migration.py
git diff --check
```

`python3` may be used where appropriate. These are local checks, not live VPS acceptance. `scripts/test-deployment-lock.ps1` is different: it uses SSH and needs explicit target authorization.

## 工作总结习惯

每完成一个相对完整的任务或阶段，在 `worklog/` 新建 `YYYY-MM-DD-简短标题.md`。用中文讲给未来的自己：做了什么、为什么做、值得记住的决策或坑、一句话亮点。不贴大段命令或 diff，不记录秘密。保留“已测”和“未测”的区别。
