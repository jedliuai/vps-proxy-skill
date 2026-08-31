# 部署：先直连，再按需增强订阅

先完成 [准备](prerequisites.md)，确认一次变更计划，再按阶段连续执行。以下路径以完整仓库根目录为工作目录；不得照抄历史实例信息。

## A. 本地与主机预检

读取 `deploy/server-bootstrap.sh` 与 `deploy/preflight.py`，确认本次版本的副作用。运行仓库测试（见根 AGENTS.md），记录 commit。固定版本是已记录的基线，不是“最新版”；部署前核对官方发布与安全公告，若存在必须处理的严重问题，暂停该版本并提出有测试/回退的升级方案，而非自动追新。

只读检查目标系统、内存/swap/磁盘、NTP、监听、Nginx 站点、容器、nft/UFW 和已有代理。`preflight.py` 不负责 DNS、云权限、sudo 新会话或备份验证，也不识别所有业务冲突；Codex 必须补齐这些检查。已有栈的凭据文件存在只是一项识别线索，不是允许覆盖的授权。

## B. 传参和执行

`.env.example` 仅提供空白非敏感项，复制到未跟踪 `.env` 后填自己的 alias/domain/admin；已经存在 `.env` 时先检查，不覆盖。

PowerShell 入口适合 Windows；完成真实 SSH 测试与变更/CA 授权后：

```powershell
pwsh ./scripts/vps-proxy.ps1 preflight -AdminSshVerified -HostChangesApproved -AcmeTosAccepted
# 上一步成功且 DNS、云防火墙、恢复通道已独立核实后
pwsh ./scripts/vps-proxy.ps1 deploy -AdminSshVerified -HostChangesApproved -AcmeTosAccepted
```

`deploy` 会变更服务；`preflight` 只在服务器临时目录传输/执行检查并清理，不安装软件或改配置。每次都重新取证后传确认开关；不要把开关当作检查本身。`VPS_ADMIN_USER` 可存在 `.env`，证明/授权开关不持久化。

Linux/macOS：使用 SSH/SCP 传输 `deploy/server-bootstrap.sh` **及同目录 `deploy/preflight.py`** 到新建、当前用户独占的远端临时目录。通过 `sudo env` 显式传下表环境变量，先 `PREFLIGHT_ONLY=1 bash <绝对路径>/server-bootstrap.sh`；预检成功后改为 `PREFLIGHT_ONLY=0` 执行一次。服务器需要 Python 3、OpenSSH、iproute2、util-linux/flock；缺失时在已批准准备范围内补齐，不绕过检查。

| 参数 | 来源与含义 |
| --- | --- |
| `DOMAIN` | 用户已验证、DNS-only 的节点域名；无作者默认值 |
| `SUB_DOMAIN` | 可选 Cloudflare 订阅域名；直连模式可与 DOMAIN 相同 |
| `XRAY_PORT` | 默认 2053；不得占用 SSH/Nginx/Trojan 或已关闭的 TCP 443 |
| `ADMIN_USER` | 已确认的非 root 管理员，当前 gate 要求 UID ≥ 1000 |
| `ADMIN_SSH_VERIFIED=1` | 已用新连接验证密钥 SSH 与 sudo 的事实声明 |
| `HOST_CHANGES_APPROVED=1` | 用户已批准准备参考中的主机变更 |
| `ACME_TOS_ACCEPTED=1` | 用户已接受 CA 条款 |
| `ROTATE_SECRETS=0` | 默认保留旧凭据；1 仅用于明确授权的轮换 |
| `DISABLE_GOOGLE_OPS_AGENT=0` | 默认保留监控；1 必须有针对性诊断与额外授权 |

不要把上述用户输入拼成未转义 shell 命令。Windows wrapper 已限制字符串字符并使用独立临时目录；直接 Bash 路径也要等效验证。绝不 `curl | sudo bash`。

脚本在任何持久变更前运行门禁，再用固定 `flock` 互斥并创建唯一 root-only 备份目录。不要删锁文件或并发重跑。首个失败后保留脱敏错误/阶段、查看备份位置再诊断；完整安装不是事务，失败可能留下部分安装状态。

## C. 先验收直连订阅

服务器生成 `/var/lib/proxy-subscription/clash.yaml`、`v2ray.txt` 和 `/etc/proxy-stack/subscription-urls.txt`。权威凭据源在 `/etc/proxy-stack/secrets.env`；生成的 Xray/Hysteria 配置、订阅正文和 URL 副本同样携带可使用的凭据，全部按敏感数据保护，不打印。

先逐协议完成 [验收](validation.md)。尚未配置 Cloudflare 时，manifest 中 `PRIMARY_*` 只是未来路径，不代表可用；**只交付已测通的 `BACKUP_CLASH` / `BACKUP_V2RAY`，对用户标为“Clash 订阅 / V2Ray·小火箭订阅”**。不用让用户理解备用命名，也不交付五个链接。

Cloudflare 不是成功搭建节点的必要条件。用户暂不授权 Cloudflare 时到此交付；不悄悄创建 Worker、绑定域名或消耗付费配额。

## D. 可选 Cloudflare

安装/授权用户选择的 Cloudflare 插件后先检查其实际可用工具。执行相关操作前读取该插件对应技能；若缺写入 KV/secret/DNS 能力，使用本仓库 `cloudflare-worker/package-lock.json` 锁定的 Wrangler 与已授权账号。无需在 VPS 安装 Node/Wrangler。

1. `cloudflare-worker/` 内 `npm ci`，后续用 `npm exec -- wrangler`；先 `whoami` 核对账户，必要时让用户登录。命令参数以锁定版本 `--help` 为准。
2. 从已授权账户确认 zone，创建或选择本用户专用 Worker/KV namespace，不复用作者 ID。复制模板为忽略的 `wrangler.local.jsonc`，填本用户的 Worker 名、account_id（多账户时明确）、自定义域名和真实 namespace ID；所有操作显式 `--config wrangler.local.jsonc`。模板占位值不能部署。
3. 变更前备份旧 Worker 版本/配置和两个 KV 值到独占忽略目录；KV 读取正文重定向到受限文件，不输出。新服务记为“无旧版本”，不伪造回滚点。
4. 上传代码、设置 `SUB_TOKEN` secret、同步 KV 是三项独立操作。`SUB_TOKEN` 必须匹配服务器主订阅令牌；从独占文件 stdin 注入 `wrangler secret put SUB_TOKEN`，不放到参数、输出或历史里。不要把整个 secrets.env 交给第三方工具。
5. 分别将服务器 YAML、Base64 通过安全临时文件写入绑定 `SUBSCRIPTIONS` 的 `clash-config`、`v2ray-config`。锁定 CLI 支持的典型操作为 `kv key put <key> --path <文件> --binding SUBSCRIPTIONS --remote --config wrangler.local.jsonc`。**`--remote` 不可漏，否则可能只改本地 KV。**
6. 只绑定订阅域名，节点域名继续 DNS-only。不能把真实代理线路套到 Worker/CDN 里。发布完成后验证两种格式、精确令牌、错误路径、主备同格式哈希和 no-store。
7. 验收全通过才将交付文件升级为两个 `PRIMARY_*` 显式入口；客户端只需选择一条。清理上传/测试临时副本，保留有意留存的独占恢复备份。

主聚合 `/subscription` 会按 `target=clash|v2ray` 或 UA 返回一种格式，未知 UA 默认 Base64。统一 URL 不能给一次请求同时返回 YAML 和 Base64，也不能让不支持 HY2/REALITY 的旧核心突然支持它们。

官方资料（执行时核实变更）：[Wrangler 命令](https://developers.cloudflare.com/workers/wrangler/commands/)、[KV](https://developers.cloudflare.com/kv/)、[Workers secrets](https://developers.cloudflare.com/workers/configuration/secrets/)。

## E. 原实例与历史操作

[原实例运维记录](../../../docs/美国单实例代理运维.md)用于理解历史，不是新用户的默认命令。Trojan 443→10443 的 `deploy/migrate-trojan-port.py` 是旧布局的定向迁移工具，不是通用端口编辑器。当前新部署已使用 10443，不需要运行迁移。

完整重部署会下载固定二进制、重建配置并重启 Xray/Hysteria；`restart` 同样影响两个协议服务。只更新订阅或修一个端口时不要执行这两项。已有用户迁移到本仓库新版只改变本地脚本，不要求重跑服务器安装。
