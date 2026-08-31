# 验收、交付与进度恢复

## 分层证据

| 层级 | 实际要证明什么 | 不能替代它的东西 |
| --- | --- | --- |
| SSH | 新非 root 密钥会话、sudo、硬化后仍能重新登录 | 旧长连接还活着 |
| 服务 | Xray / Hysteria / Nginx / firewall active，版本与配置合法 | 安装命令退出 0 |
| TLS / DNS | 域名正确、证书链/主机名/到期日正确，DNS-only | `curl -k` 或客户端 skip-cert-verify |
| 协议 | HY2、Trojan、REALITY 各自真实认证并代理 HTTP(S) | TCP 握手或服务本机 HTTP 204 |
| 订阅 | 客户端可解析，主备两种格式分别一致，无秘密日志 | Worker deploy 成功 |
| 用户网络 | 从用户上网网络重测请求、故障切换和应用 | 服务器访问 Google 正常 |

服务器只输出脱敏状态，使用 Xray `run -test`、`nginx -t`、`ss`、服务重启计数、证书到期日和权限检查。验证 `certbot.timer`；获准后执行一次 renew dry-run 并检查续期 hook（不要频繁重试生产签发）。hook 要复制服务组可读的证书、更新两服务并 reload Nginx，不能只更新磁盘证书。

检查主机和云防火墙两层，UDP 443 与 TCP 443 是独立的；确认其他业务没意外暴露/阻断、ACL 禁止 metadata/私网/回环/SMTP25。不要用宽放行防火墙完成测试。

## 独立客户端测试

优先使用用户电脑已安装的 Mihomo，或获准安装校验过的测试客户端。启动独立临时目录、临时 loopback SOCKS/控制端口，`allow-lan: false`，不覆盖现有配置、系统代理或浏览器会话。控制接口只绑 loopback；记录本次进程 PID，结束只清理自己的测试进程和目录。

测试配置必须独占权限；stdout/stderr 含 URI/域名令牌时先脱敏，不能直接发布。Clash `-t` 配置验证与实际出站请求都要做。缺少 geodata 时经授权获取对应资源，记录版本，不把 geodata 下载失败误判为服务器认证失败。

逐一固定选择三个节点，记录请求次数、失败数、耗时分位数、出口国家、测试源网络与时间。默认低流量请求 Google/GitHub 的小响应；不得未经批准循环下载大文件“测速”。若要做 100 次/晚高峰 30 分钟测试，说明流量与时间后在用户允许范围内执行。

自动切换优先在隔离客户端里模拟首选不可达，确认 fallback 生效。真正在服务器停止 Hysteria 会中断用户连接，只能提前获准并在 finally 恢复，不为了验收自动停生产服务。Fallback 是按顺序择可用项，不是 url-test 最低延迟组；手动选中/固定节点会影响自动选择。

ChatGPT 浏览器登录、长回复、WebSocket、文件上传、Voice 等要用真实浏览器分别测试；用户自己完成登录，不读取 Cookie 或账户密码。CLI 的 Cloudflare challenge 403 不能单独证明被封，未认证 API 401 只证明请求到达。不能保证某出口永久被第三方接受。

## 订阅断言

- 使用真实客户端 UA 或显式格式路径。YAML 包含三节点及规则/组；Base64 解码后是三条对应 URI（不在报告展示）。
- 按字节/哈希比较服务器、主入口、备用入口同格式 payload，不能拿 YAML 和 Base64 的哈希互比。避免正文进入工具输出。
- 精确有效路径 GET/HEAD、`Cache-Control: no-store`。Worker 错误令牌路径应为 404，非法方法应拒绝；只有聚合 `/subscription` 的非法/重复 target 应拒绝，固定格式路径不采用 target 参数。直连 Nginx 未命中路径按当前配置返回静态页（可能200），必须证明它不是订阅正文，不能对直连强求404。
- TLS 验证保持开启；8443 订阅路径 access_log off。测试客户端回环暴露不得被误当公网出口。
- 直连模式只测并交付直连链接；没有发布 Cloudflare 时不把主入口写成成功。

## 只交付用户需要的两条

将已验证的 Clash 与 V2Ray/小火箭链接写入用户独占的交付文件，不在普通任务总结/README 展示。服务器源文件 root:root 0600；复制到本地时经明确授权短暂使用指定管理员可读文件，Linux/macOS 目录 0700 文件 0600，Windows 使用当前用户独占 ACL。确认 Git ignore 命中后再留存本地，不能只靠 Private 仓库或 ignore 当权限保护。

### 安全导出配方（不是把秘密读进模型）

源文件只允许 root 读取时，不用 chmod 放开，也不必把整份 secrets.env 下载。通过已验证管理员的 `ssh` + `sudo -n cat`，**在执行端直接将 stdout 重定向到独占文件**；工具只返回退出码与哈希。所有下面的 alias/路径由 Codex 使用本次已验证值填入，不能照抄到别人的主机。

- Linux/macOS：先 `umask 077`，用 `mktemp -d` 创建新目录；`ssh -- <alias> 'sudo -n cat /var/lib/proxy-subscription/clash.yaml' > <目录>/clash.yaml`。按同样方法导出 v2ray.txt 和供内部选择入口的 subscription-urls.txt；失败时不交付部分文件。完整 manifest 含五个路径，仅为受限内部输入；从中选出本次已验收的两条，生成另一个用户独占交付文件，不把完整 manifest 交给用户。用 `git check-ignore` 或将目录放仓库外，并检查 owner/mode。
- Windows：先创建全新目录，在任何秘密写入前，用当前用户 SID 设置独占 ACL，再核对 `icacls`。例如以 `[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value` 取 SID，对新目录运行 `icacls <目录> /inheritance:r /grant:r "*<SID>:(OI)(CI)F"`。不要在不确定内容的既有目录上批量改 ACL。
- PowerShell **7.4+** 可用原生命令 `ssh ... > <文件>` 保留 stdout 字节；其他版本使用进程 stdout 的 BaseStream 写入 FileStream，或采用受控二进制传输，不经过会改编码/换行的 `Out-File`、`Set-Content` 或聊天输出。不要合并 stderr 到 stdout，否则会破坏字节保留。导出后检查 native exit code、文件ACL和源/目标SHA256。[PowerShell 官方重定向说明](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection)
- Worker token 单独用远端 `sudo -n sed -n 's/^SUBSCRIPTION_TOKEN=//p' /etc/proxy-stack/secrets.env` 导入独占文件；只把这个文件 stdin 传给 `wrangler secret put SUB_TOKEN`，不用命令参数承载值。不要把 token、URI 或订阅哈希之外的正文输出到终端。
- 两份订阅经 KV 上传/验收后，删除本次创建的**确切上传文件**和空临时目录；只给用户保留其独占交付文件，以及明确保留的备份。复制失败或授权不足时停止，不通过放宽服务器权限解决。

用户说明用三句话即可：Clash 导入第一条并用规则模式；v2rayN/v2rayNG/Shadowrocket 导入第二条；不支持某协议时先核对客户端核心版本。URI 不携带 Clash 的规则与策略组。自动识别链接与备用路径只在需要时展示，不能造成“有五组服务器”的错觉。

## 最小交接记录

公开 worklog 只记录目标代号、Git revision、软件版本、协议、直连/Cloudflare 模式、脱敏验收结果、未完成项和下一步，区分“已配置”与“已验证”。真实 SSH 别名、IP/域名、账号、本机路径、确切快照/备份位置、预算账户信息与订阅链接写入仓库外、用户独占的交接文件，供后续经授权恢复，不复制到公开总结。

出现工具/权限/网络阻塞时，完成安全检查后报告缺的具体条件，不循环重新部署。新会话从记录和当前只读状态续接，不重复轮换或创建 Worker/KV。

任何示例、其他用户的结果或仓库 CI 都不是本次实例的测试结果、吞吐量或 SLA。新用户实例在未测前一律记为未验收。
