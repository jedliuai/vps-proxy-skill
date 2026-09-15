<div align="center">

# 🌐 VPS Proxy Skill

Codex Skill for self-hosted VPS proxies · 从 SSH 准备到节点验收与恢复

**把仓库地址交给 Codex，让它按可审查的流程搭建和维护你的私人代理。**

一个 Codex Skill，配套部署脚本、测试与故障手册：在自己的 VPS 上配置 Hysteria2、Trojan、VLESS REALITY，交付 Clash / Mihomo 与 V2Ray / 小火箭订阅。不是免费节点合集，也不是代理服务商。

[![Repository checks](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml/badge.svg)](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml)
[![Release notes](https://img.shields.io/badge/release-v0.1.0--preview.1-blue)](https://github.com/jedliuai/vps-proxy-skill/releases/tag/v0.1.0-preview.1)
![Baseline](https://img.shields.io/badge/baseline-Debian_13_x86__64-A81D33)

[快速开始](#quick-start) · [English](./README.en.md) · [交付示例](./docs/handoff-example.md) · [Skill](./skill/vps-proxy-builder/SKILL.md) · [Releases](https://github.com/jedliuai/vps-proxy-skill/releases)

You bring the VPS. Codex follows the setup, verification and recovery workflow.

</div>

---

## 中文

### 适合谁，为什么用它？

适合已经有（或准备购买）专用 VPS、希望自建私人代理，却不想逐项拼接 SSH、TLS、订阅和防火墙教程的人。也适合把已有节点交给 Codex 排障：技能要求先诊断、保住可用配置，而不是遇错就重装。

它的区别不在于又支持一种协议，而在于把**准备 → 授权 → 部署 → 逐协议验收 → 维护恢复**连起来，并提供可检查的源码和测试。常被称为“自建 VPN”“翻墙”“科学上网”或“魔法”的需求，在这里具体指自托管应用代理，而非 WireGuard / OpenVPN。

**开始前只需确认：**专用 Debian 13 x86_64 VPS、systemd、SSH 22、公网 IPv4、自己控制的域名，以及能使用终端和网络的 Codex。不会 SSH 可以让它指导；Cloudflare 和 GitHub 插件均不是直连部署的前提。

**目标是自动完成已授权的技术工作，不是跳过人的控制权。** 购买、账号登录、MFA、必要授权和无法远程代办的家庭网络测试，仍需要你参与。

<a id="quick-start"></a>

### 🚀 Quick Start：复制给你的 Codex

```text
请使用这个仓库，帮我在自己的 VPS 上搭建私人代理节点：
https://github.com/jedliuai/vps-proxy-skill

先获取完整仓库，阅读根目录 AGENTS.md 和
skill/vps-proxy-builder/SKILL.md，按其中的流程执行。
先检查你能用的工具、仓库权限和我的 VPS 条件。
我不熟悉 SSH，请在需要时指导我配置，不要让我提供私钥正文。
先说明目标服务器和要改什么，经我确认后连续完成范围内的工作。
优先跑通直连订阅；需要 Cloudflare 时再协助安装/授权必要插件。
不要覆盖已有服务、关闭证书校验或把凭据提交到 GitHub。
最后给我适用于 Clash 和 V2Ray/小火箭的两个已验证订阅入口，
以及已测/未测结果和恢复说明。遇到权限或购买步骤再让我参与。
```

> [!IMPORTANT]
> 这是一个可公开读取的独立仓库，可以直接把上面的地址发给 Codex。代码公开不等于提供免费节点或授予云账号权限：你仍需准备自己的 VPS、域名和授权。仓库不包含作者的实际订阅、密钥或运行配置；详见 [安全约定](./SECURITY.md)。

**不必先全局安装技能。** 把完整仓库作为 Codex 项目打开，它可按 `AGENTS.md` 读取技能。`skill/` 不是 Codex 默认自动扫描目录，因此提示词明确给出文件路径。若另行安装了技能，也需要完整仓库中的部署脚本。[Codex 技能说明](https://learn.chatgpt.com/docs/build-skills)

想固定版本复现，可让 Codex 使用预览版，或自行克隆后打开目录：

```sh
git clone --branch v0.1.0-preview.1 https://github.com/jedliuai/vps-proxy-skill.git
cd vps-proxy-skill
```

[Release](https://github.com/jedliuai/vps-proxy-skill/releases/tag/v0.1.0-preview.1) 提供版本说明和源码下载。建议通过 Git 克隆：仓库检查依赖 Git 文件清单，源码 ZIP 不是独立安装器。固定的是工具箱版本，**不是每次重新安装服务器**。

完成后应得到两个按客户端标记的私密订阅入口、逐项测试结果和维护恢复说明。先看[无真实凭据的交付示例](./docs/handoff-example.md)，了解应该向 Codex 要什么。

### 🧰 要安装哪些插件？

| 工具 / 插件 | 是否必需 | 用来做什么 |
| --- | --- | --- |
| Codex + 可用终端、网络权限 | **必需** | 读取代码、执行检查、通过 SSH 配置 VPS |
| Git + OpenSSH | **必需能力** | 获取仓库、连接和传输文件，不需要另找 SSH 插件 |
| GitHub 插件 / 连接器 | 可选便利 | 访问仓库；已有权限的 Git / `gh` 可以替代 |
| Cloudflare 插件 | 使用 Cloudflare 时推荐 | DNS、Workers、KV 等能力需实际授权；缺失操作可用 API / Wrangler |
| 浏览器控制插件 | 可选 | 协助操作控制台；登录、MFA、付款由你完成 |

**没有其他必须凑齐的插件包。** 插件已安装不代表账号已授权，也不代表支持所有写入操作。Codex 会先核对实际能力；插件使用方式参见[官方说明](https://learn.chatgpt.com/docs/plugins)。本地依赖按需准备，VPS 不需要安装 Codex、Node 或 Docker 面板。

### 📦 你准备什么，Codex 负责什么？

| 你提供或确认 | Codex 按技能负责 |
| --- | --- |
| 自己购买、可管理的 VPS | 检查系统、资源、监听端口与现有业务 |
| SSH 初始入口；不会可以让它指导 | 公钥/alias 配置，新非 root 登录与 sudo 验证，保留救援入口 |
| 可控制的域名或子域名 | 检查 DNS、证书条件、云防火墙，生成节点配置 |
| 账户授权与变更范围 | 在范围内部署、验证、可选发布 Cloudflare 订阅 |
| 家庭网络/客户端测试配合 | 区分服务器成功和真实使用成功，给出恢复及维护记录 |

当前自动化基线是 **专用 Debian 13、x86_64、systemd、SSH 22、公网 IPv4**。域名用于有效 TLS 证书；已有域名可用子域名。Cloudflare 不是必需项。

ARM、Ubuntu、自定义 SSH 端口、仅 IPv6/NAT 或共享业务主机暂不属于开箱基线，Codex 必须先停下说明适配需求，不能硬跑。模板默认是中国家庭网络分流和 `US-*` 名称；其他地区部署需按真实地域调整标签与策略。

### 🛡️ 自动化也要有刹车

- 没有自己的参数就停止，不再默认指向作者服务器或域名。
- 新非 root 密钥 SSH 和 sudo 必须先验证，避免禁用 root 后把自己锁在门外。
- 部署门禁检查平台、声明的授权与监听冲突；DNS、云权限和恢复点另行核实。
- 固定版本、下载校验、部署互斥和备份；不把完整重装当订阅更新按钮。
- 私钥、密码与真实订阅不进 Git，也不交给公共订阅转换网站。
- 先保住可用节点，再做最小修复；第一次安装失败先诊断，不无限重试。

**不需要为了更新这个 Skill 重部署线上节点**。完整部署要求显式参数及 SSH/变更/CA 条款确认，见[部署参考](./skill/vps-proxy-builder/references/deployment.md)。

### 💡 把真实踩坑经验交给下一次部署

技能里记录了：未认证 fallback 外发带宽、连接风暴、全局限速误伤、Trojan 最小端口迁移、证书权限和续期、UA 识别错误、Worker 与 KV 没同步、订阅刷新后重连，以及如何区分 Codex 资源占用和跨境链路丢包。

每个案例都保留“先看什么、证据是什么、最小修复是什么、什么时候不能套用”，不是一串遇错就重装的命令。[查看诊断手册](./skill/vps-proxy-builder/references/troubleshooting.md)

### 💰 费用与限制

本仓库不提供服务器、付费代理上游或订阅服务。你自行承担 VPS、公网 IP、流量、域名、可选 Cloudflare 与 Codex 使用费用，按各服务当前计费规则确认。作者的试用额度不适用于其他用户；预算告警也不是硬性消费上限。

三个协议共享一台 VPS 的出口，不能变成多个国家，也不提供跨服务器高可用。Cloudflare 在这里仅分发订阅，不改善主要跨境数据链路，不保证任何网站永久接受该 IP。使用应符合服务提供商条款及适用要求。

### ❓ 常见问题

**这是传统 VPN 服务吗？** 搜索中常把此类需求称为“自建 VPN”，但本仓库实际部署的是 Hysteria2、Trojan 和 VLESS REALITY 代理，不是 WireGuard / OpenVPN，也不承诺接管整台设备的所有流量。

**翻墙、科学上网、魔法上网需要自己看完教程吗？** 可以把上面的提示词交给 Codex，由它按 Skill 检查前提并完成已授权的技术步骤；购买、账户登录与必要授权仍由你处理。

**Clash、V2Ray、小火箭能用同一套节点吗？** 可以使用支持对应协议的客户端；交付分别适配 Clash/Mihomo 的 YAML 与 v2rayN/v2rayNG/Shadowrocket 的 URI/Base64 订阅。规则和自动切换组不会通过 URI 自动复制。

---

## English

Read the **[English quick start and project overview](./README.en.md)**. Operational references are currently in Chinese; Codex should explain them in your language.

<a id="architecture"></a>

## 🧭 Architecture · 一条执行链，两类流量

```mermaid
flowchart LR
    User["You / 购买与授权"] --> Codex["Codex + one skill"]
    Codex --> Check["SSH + preflight / 先核验"]
    Check --> VPS["Your VPS / 三协议节点"]
    Codex -.-> CF["Optional Cloudflare / 订阅分发"]
    Client["Clash / V2Ray / Shadowrocket"] -->|"Proxy traffic"| VPS
    Client -.->|"Subscription"| CF
    Client -.->|"Direct subscription :8443"| VPS
```

| Component / 组件 | Port / 端口 | Role / 用途 |
| --- | --- | --- |
| Hysteria2 | UDP 443 | 首选候选 / Preferred candidate, validate on the user's network |
| Xray Trojan TLS | TCP 10443 | TLS TCP 兼容入口 / TLS TCP option |
| Xray VLESS + REALITY + Vision | TCP 2053 | TCP 备用 / Alternate TCP path |
| Nginx | TCP 80 / 8443 | ACME、直连订阅、本机 TLS target / ACME, direct subscriptions, local TLS target |
| Cloudflare Worker + KV | Optional HTTPS | 订阅分发，不承载代理流量 / Subscription delivery only |

Repository pins / 仓库固定版本：Xray `v26.3.27` · Hysteria2 `v2.12.1` · Wrangler `4.127.1`。Not claims of being the latest; verify security advisories and compatibility before changing them.

## 🧪 Evidence, not promises · 验证边界

仓库提供本地隐私模式扫描、部署静态检查，以及 Worker、主机预检、运维入口和端口迁移测试。它们验证工具行为，不代表某台 VPS 已经安装成功，也不能替代真实客户端、家庭网络和晚高峰验收。[验收参考](./skill/vps-proxy-builder/references/validation.md)

Local checks cover secret patterns, deployment invariants, the Worker, readiness checks, the entrypoint and port migration. They are not fresh-server deployment results or an uptime guarantee. The skill must collect new evidence for every user's host, including real-client and home-network acceptance.

```text
pwsh scripts/validate-repo.ps1
python -B scripts/test-preflight.py
python -B scripts/test-entrypoint.py
python -B scripts/test-trojan-migration.py
git diff --check
```

以上检查不连接 VPS。The checks above do not connect to a VPS.

## 维护、反馈与作者 / Maintenance and author

由 [jedliuai](https://github.com/jedliuai) 维护，属于作者围绕 AI agents 与个人创作工具的实践。可以在[作者的其他公开项目](https://github.com/jedliuai?tab=repositories)中继续了解这些方向。

遇到问题请先读[排障手册](./skill/vps-proxy-builder/references/troubleshooting.md)，再按[反馈指南](./CONTRIBUTING.md)提交脱敏的可复现信息。不承诺响应时限或代管服务器。若项目有帮助，可以 Star 收藏、Watch → Custom → Releases 关注版本，或分享仓库和具体版本；不要分享自己的订阅。引用时注明 `jedliuai/vps-proxy-skill` 和 tag/commit，便于复现。

**许可状态：目前尚未选择开源许可证。** 公开可读不等于授予所有复用、分发或商业授权；需要这些权限时请先向作者确认。详见 [GitHub 许可证说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。

<a id="project-map"></a>

## 📚 Project map · 给 Codex 的工具箱

| Entry / 入口 | Purpose / 用途 |
| --- | --- |
| [AGENTS.md](./AGENTS.md) | 仓库行为约定与技能入口 / Repository instructions |
| [SKILL.md](./skill/vps-proxy-builder/SKILL.md) | 唯一 Codex 技能 / The single skill |
| [准备 / Prerequisites](./skill/vps-proxy-builder/references/prerequisites.md) | 插件、SSH、域名、权限、恢复点 |
| [部署 / Deployment](./skill/vps-proxy-builder/references/deployment.md) | 直连优先，可选 Cloudflare；参数与副作用 |
| [排障 / Troubleshooting](./skill/vps-proxy-builder/references/troubleshooting.md) | 症状、证据、最小修复与回退 |
| [验收 / Validation](./skill/vps-proxy-builder/references/validation.md) | 逐协议、用户网络、两链接交付 |
| [deploy/](./deploy/) · [scripts/](./scripts/) · [Worker](./cloudflare-worker/) | 可审查的执行源码与测试 / Source and tests |
| [SECURITY.md](./SECURITY.md) | 凭据与泄漏处理 / Credential boundaries |
| [worklog/](./worklog/) | 公共工具箱的维护记录，不存放个人实例档案 / Public project maintenance notes, not private host records |

公开仓库只保留可复用的 Skill、脚本、测试和维护说明。个人实例配置、运行日志、订阅及备份不属于公共文档；复用排障方法请读 Skill 参考，而不是复制某个人的服务器记录。This repository keeps reusable skills, source, tests and project notes. Personal host inventories, runtime logs, subscriptions and backups do not belong here; use the skill's incident playbooks instead.

---

<div align="center">

**把重复劳动交给 Codex，把选择权留给人。**<br>
Let Codex handle the repetition. Keep people in control.

</div>
