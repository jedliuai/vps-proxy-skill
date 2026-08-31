# 准备：从仓库链接到可安全操作的 VPS

## 1. Codex 与工具

运行在能到达 VPS 的 Codex 桌面端/CLI 环境；只有网页阅读能力不能部署。先检查终端、联网、SSH 和授权，不通过放开所有权限解决能力缺失。Codex 应运行在用户电脑，不要求塞进低内存 VPS。

| 能力 | 优先选择 | 可替代途径 / 边界 |
| --- | --- | --- |
| 获取完整仓库 | 已授权 Git / GitHub CLI | GitHub 插件可读仓库，但不等于终端已登录；私有库需 owner 邀请/用户已有权限 |
| 执行服务器操作 | OpenSSH 的 `ssh` / `scp` | 无所谓“必装 SSH 插件”；Codex 终端权限与网络必须真实可用 |
| Cloudflare DNS / Workers / KV | 用户安装并授权的 Cloudflare 插件 | 工具能力不足时用授权 API、Node.js 22+ 与本仓库锁定的 Wrangler；直连模式无需它 |
| 云防火墙、快照、预算 | 用户云控制台或已授权云 CLI | SSH 权限不等于 Compute/Billing 权限；无需虚构一个 GCP 插件 |
| 控制台辅助 | 可选浏览器工具 | 用户完成登录、MFA、付款；没有浏览器工具可给逐步指引 |
| Windows 运维入口 | PowerShell 7 | Linux/macOS 可直接 SSH 执行 Bash；`check` 的 `Test-NetConnection` 是 Windows 命令，不要当跨平台保证 |
| 本地仓库测试 | Git、Bash、PowerShell 7、Node、Python 3 | Windows 用 Git Bash；Python 测试不需要连接 VPS |

不是“装满插件就能部署”。先发现本次会话实际工具，再验证账号、zone/project 权限。插件不可用时只请求必要安装/授权，不猜名称、版本或接口。不要把用户的 token 粘到聊天；使用登录流程、secret 输入或用户独占的环境配置。

Codex 技能发现位置与插件方式可能随版本变化，以官方文档为准：[技能](https://learn.chatgpt.com/docs/build-skills)、[插件](https://learn.chatgpt.com/docs/plugins)。本项目采用根 `AGENTS.md` 显式指向 `skill/vps-proxy-builder/SKILL.md`，无需先安装本技能到全局；单独安装技能也必须保留完整仓库供执行。

## 2. 只收集必要输入

在用户授权范围内确认目标 VPS 公网 IPv4、提供商/区域、系统/CPU、已有业务、SSH 端口/用户名/本地私钥路径、用户客户端、可控制域名、Cloudflare 是否可选、预算/流量上限和恢复控制台。地址、账号与本机路径属于个人运行资料，只保存在仓库外的用户独占交接文件，不能作为公开 worklog 的“非敏感项”。不要索要私钥正文。

本 bootstrap 固定支持 Debian 13 x86_64 + systemd + SSH 22，建议专用主机。按本次负载检查内存、swap 与磁盘，不能把某个示例机型当作最低规格保证。不自动重装用户系统。ARM、只有 NAT 端口映射、只有 IPv6、其他发行版先停止自动安装并解释适配成本。

三个协议共享 VPS 出口，不凭名称选择国家。模板节点名目前为 `US-*`，若用户主机不在美国，交付前同步修改 YAML、URI 与组引用为真实区域或中性名称，再做配置检查。主机地域不能靠 Cloudflare、SNI 或节点名改变。

## 3. SSH：先建立可恢复访问

初次只拿到 root 密码很常见。让用户在云控制台完成一次登录/公钥注入，或在自己的终端安全输入初始密码，不把密码发给模型。Codex 检查本地已有公钥；新建专用 Ed25519 key 时不覆盖既有 key，给私钥设置本地独占权限。

向用户提供可直接替换的 SSH alias 模板（模板必须替换后才使用）：

```sshconfig
Host my-proxy-vps
    HostName <用户提供的公网IP>
    User deploy
    Port 22
    IdentityFile <本地专用私钥的绝对路径>
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

合并到现有 SSH config，不覆盖文件。首次服务器 host-key 指纹应通过提供商控制台等可信渠道核对；`ssh-keyscan` 只能收集，不能证明身份。不要设置 `StrictHostKeyChecking=no`，host-key 改变时先核实实例是否被重建。

在已授权服务器创建/确认非 root 管理员、其公钥和 sudo 权限。仅当用户允许无人值守 sudo 时才设置相应策略，否则用用户交互授权。保留 root 原会话/云串口或救援控制台，然后从用户电脑打开**新 TCP 连接**验证：

```text
ssh -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o ControlMaster=no -o ControlPath=none my-proxy-vps "id -un; sudo -n true"
```

用户名必须是预期管理员，`sudo -n true` 必须成功才能采用本仓库无人值守入口。只在旧复用会话里运行 `whoami` 不足以证明新登录可用。验证成功后才传 `ADMIN_USER`、`ADMIN_SSH_VERIFIED=1`，禁止为满足门禁编造结果。

非 22 端口的 SSH 不能直接跑当前防火墙脚本；需要用户同意并先完成新端口登录验证的适配，或使用符合基线的新主机，绝不擅自切端口。

## 4. 域名、云防火墙与成本

Hysteria2、Trojan 和直连订阅都使用有效 TLS 证书，当前脚本依赖用户控制域名和 HTTP-01。没有域名时，说明需要一个能指向 VPS 的域名/子域名（用户若有域名无需再买），由用户授权使用或购买；不擅自改成自签名并关闭证书验证。

节点域名使用 DNS-only A 记录指向本 VPS。验证公共 DNS；若存在 AAAA，确认可达同一服务，否则经授权清理错误 AAAA。确认 CAA 允许所选 CA。Cloudflare 橙云不代理本方案 HY2/REALITY/Trojan 数据。

云安全组与主机防火墙是两层。基线公开 TCP 80/2053/8443/10443、UDP 443，SSH 22 尽量限制到管理来源；保留必要 ICMP。TCP 443 不需要开放。公网 TCP 80 必须在 ACME 验证前可达，避免让安装卡在签证书。

费用包括 VPS/公网 IPv4/磁盘快照、出站流量、域名、可选 Cloudflare 用量及 Codex 使用。不要沿用作者的试用额度或承诺免费；购买/扩容要先查对应提供商当前官方价格。预算告警不等于消费上限。得到授权才设置账户级告警，并验证创建结果；`vnstat` 只统计流量，不会强制限费。

## 5. 变更前向用户说明一次

将安装固定 Xray/Hysteria、Nginx、Certbot、nftables、vnstat；创建服务用户、站点、证书与定时续期；收紧 SSH、设置本栈防火墙、sysctl 和日志限额；重启相关服务。Docker 保留，监控默认不动。已有业务/其他防火墙不能被无声覆盖。

确认用户接受 CA 条款：[Let's Encrypt Subscriber Agreement](https://letsencrypt.org/repository/)。当前 Certbot 非交互注册不留邮箱，依赖本地续期/到期检查；需要邮箱时先做受审查的参数适配。

准备用户授权的快照或其他可验证恢复点。bootstrap 的目录备份不含完整系统、全部 SSH/Nginx/DNS/云设置与 Cloudflare；不能称为“一键全量回滚”。
