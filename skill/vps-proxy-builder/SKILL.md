---
name: vps-proxy-builder
description: "Use Codex to prepare SSH, deploy, validate, troubleshoot or recover this repository's private VPS proxy stack (Hysteria2, Trojan and VLESS REALITY) on a user-authorized Debian 13 x86_64 host, with direct subscriptions and optional Cloudflare delivery. Not for buying servers or changing infrastructure during a documentation-only request."
---

# VPS Proxy Builder · Codex 执行入口

把配置、检查与排障留给 Codex，让使用者只处理购买、账号登录、必要授权和无法远程代办的客户端验收。用使用者的语言沟通；不要求其理解协议参数，也不假装插件或一次脚本执行能保证成功。

## 先定位，再行动

本技能依赖整个 `vps-proxy-skill` 仓库，不是独立安装包。从当前工作目录定位包含 `deploy/server-bootstrap.sh`、`deploy/preflight.py`、`cloudflare-worker/` 的仓库。若技能被单独复制到个人技能目录，先获取用户可访问的完整仓库并切换到它；不要相对个人技能目录运行部署。记录本次 Git revision。文档示例与模板 `US-*` 名称不是用户配置；实际域名、IP、SSH alias 和 Cloudflare ID 必须另行验证，不写入公开文件。

依据请求选择模式：

- **仅阅读/规划/文档**：解释，不执行 SSH、部署、DNS 写入或安装插件。
- **新建**：读 [准备与工具](references/prerequisites.md)，再读 [部署步骤](references/deployment.md)。
- **已有节点坏了**：读 [诊断与恢复](references/troubleshooting.md)，先做只读对照；不得用完整 bootstrap 当修复按钮。
- **验收或交付**：读 [验收与交付](references/validation.md)。

涉及变更前读仓库 [安全约定](../../SECURITY.md)。仅加载当前阶段需要的参考，不必读完整历史。

## 本次自动化的合同

用一段简短计划明确：目标 SSH alias/主机、系统、是否专用 VPS、域名归属、直连还是 Cloudflare 订阅、允许改的服务与防火墙、预算限制和回退入口。目标不明确时只问最小缺失信息。

确认这段计划得到授权后，连续完成范围内的检查、配置和测试，不为每条普通命令重复询问。购买、扩容、新建 VM、付费产品、改 IP、删除现有业务、关闭监控、公开仓库、轮换已使用的凭据或更改受影响范围必须另获授权。需要人工登录时暂停在那一步，说明点哪里/授权什么；禁止绕过权限或关闭 Codex 安全限制。

自动化基线：**专用 Debian 13 / x86_64 / systemd / SSH 22 / 公网 IPv4 / 用户控制的域名**。ARM、Ubuntu、自定义 SSH 端口、NAT-only、仅 IPv6、共享业务主机属于适配任务，不能跳过门禁硬跑。现有模板以中国家庭网络分流为场景；地域与策略必须向用户说明，不把美国标签套到其他国家。

## 必须保持的不变量

1. **不能锁出用户**：先用新会话证明非 root 管理员的密钥登录和 sudo 可用，保留原会话/控制台。`ADMIN_SSH_VERIFIED=1` 是检查结果的声明，不是自动证明；脚本随后会禁用密码和 root SSH，并仅保留 22 端口。
2. **不能覆盖其他业务**：列出监听、Nginx、nftables/UFW、Docker 与 systemd 状态。bootstrap 会重建本栈配置、替换 Nginx 默认站点、收紧入站规则、安装固定版本并重启。专用主机的快照/恢复控制台准备好后再部署。
3. **不能复用作者配置**：真实域名/alias 由用户提供或已授权账户内验证；Cloudflare 配置必须改用其 account/zone/KV。新入口不再内置作者默认值。
4. **不能泄漏凭据**：密钥在服务器生成；订阅 URL 本身是 bearer 凭据，Base64 不是加密。私钥/密码/URI/YAML/令牌不进入 Git、日志、聊天或公网转换站。只交付用户独占的文件，参考交付章节。
5. **不能把安装当验收**：`active`、TCP 可达、TLS 成功、完整协议可用、用户网络可用是不同证据。用独立临时客户端逐个测，不覆盖其当前配置。
6. **不能无限试错**：脚本第一次失败先保存脱敏证据并定位阶段，不重复整套安装、不并发部署。原节点恶化时先恢复已知配置。升级与证书签发重试需针对根因，不用试错消耗 ACME 配额。

## 依赖按能力检查，不按插件名字猜测

- Codex 必须能读取完整仓库、执行本地终端、通过网络连接 SSH，且已获得相应权限。VPS 不必安装 Codex。
- GitHub 插件/连接器可用于仓库访问；已授权的 Git/`gh` 也可以。插件不一定赋予终端克隆凭据。
- 选择 Cloudflare 时推荐其官方插件并检查可用工具与授权；缺少 DNS/Workers/KV/secret 能力时使用授权后的 API 或锁定的 Wrangler。仅安装插件不代表这些权限全有。
- 浏览器控制只在用户希望协助控制台操作时使用；登录、MFA、付款留给用户。不要要求其他无关插件，不自动安装整包依赖。

工具安装与官方资料入口见准备参考。不要求固定模型；能力不足、上下文丢失或工具受限时保存可恢复进度，不承诺“任何模型无监督完成”。

## 完成定义与续接

交付两个按客户端标记的链接入口：Clash 与 v2rayN/v2rayNG/Shadowrocket；Cloudflare 没配置好时只交付已验证的直连入口。说明三种协议是同一台服务器，不是多国出口；URI 订阅不含 Clash 分流组。

报告已测试/失败/待用户测试，保留版本、日期、回滚位置、证书续期状态和费用边界。无法在用户家庭网络测试时应明确“服务器部署完成，家庭网络验收待完成”，不能写成全部验收成功。

每个完整阶段写中文 `worklog/YYYY-MM-DD-标题.md`：做了什么、为什么、决策/坑、一句话亮点。公开 worklog 只保留通用结论、目标代号和脱敏结果；真实地址、账号、日志和恢复路径留在用户独占的仓库外文件。恢复长任务只读授权记录与当前状态，再继续未完成步骤；不从头部署，不记录凭据。把新故障的条件、证据类型和可复用修复补入参考，不附个人实例档案，也不把个案扩大成通用结论。
