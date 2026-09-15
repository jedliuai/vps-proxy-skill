# v0.1.0-preview.1 — First versioned toolkit preview / 首个版本化工具箱预览

This release labels the existing toolkit for reproducible evaluation. It is **not** a new protocol release, proof of unattended deployment, or a reason to reinstall a working VPS.

本次为现有工具箱建立可复现的版本入口，不新增代理协议，不代表无人值守部署认证，也不要求重部署可用节点。

## Included / 包含什么

- One Codex skill covering SSH preparation, deployment, validation and incident recovery.
- Hysteria2, Trojan and VLESS REALITY scripts; direct subscriptions and optional Cloudflare Worker/KV delivery.
- Preflight gates, local tests and documented safety boundaries.
- Clearer Chinese/English starts, an illustrative private handoff checklist and redacted feedback guidance.

## Start / 开始

```sh
git clone --branch v0.1.0-preview.1 https://github.com/jedliuai/vps-proxy-skill.git
cd vps-proxy-skill
```

Open the full checkout in Codex and follow README.md or README.en.md. Source ZIP/tar downloads are reference archives, not standalone installers; repository validation expects Git metadata.

用 Codex 打开完整仓库，按 README 开始。源码压缩包不是独立安装器，仓库检查需要 Git 元数据。

## Scope and evidence / 范围与证据

Dedicated Debian 13 x86_64, systemd, SSH 22, public IPv4 and a controlled domain are the supported baseline. Review the exact release commit's [CI checks](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml). Local checks cover secret patterns, static invariants and Worker/preflight/entrypoint/migration behavior; they do not prove a fresh-host deployment or client-network reliability.

支持基线为专用 Debian 13 x86_64、systemd、SSH 22、公网 IPv4 和自有域名。本地检查不是新 VPS 部署或家庭网络稳定性的验收。本次仅调整公开文档与传播入口，未连接或修改线上节点。

Three protocols share one exit. Cloudflare distributes subscriptions only. No managed service, free nodes, uptime guarantee or selected open-source license. Read README and SECURITY.md before use.
