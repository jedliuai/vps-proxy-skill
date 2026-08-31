# n8n Docker 部署说明

> 历史归档：主机地址与 SSH 别名已替换为文档示例，不能直接照抄连接；实际资源信息不在公开候选文档中保留。

部署时间：2026-08-09（Asia/Shanghai）

> 状态更新（2026-08-09）：由于 `e2-micro` 资源不足、n8n 操作持续卡顿，n8n 容器、
> `n8n_data` 数据卷、2.32.6 镜像和 `/opt/n8n` 部署目录均已移除。Docker Engine 与
> Docker Compose 仍保留。服务器上保留了
> `/var/backups/n8n/n8n-final-2026-08-09.tar.gz`；该归档包含部署配置、加密密钥和较早的
> `n8n-data-before-i18n-20260809.tar.gz` 数据备份，但不包含删除前最后一版数据库，最近创建的
> 测试工作流和后续凭据无法由它恢复。下文仅作为历史部署记录，不再代表当前运行状态。

## 当前状态

| 项目 | 配置 |
|---|---|
| 访问地址 | <http://192.0.2.10:5678/> |
| Docker Engine | `29.7.2` |
| Docker Compose | `v5.4.0` |
| n8n | `2.32.6`，固定版本 |
| 容器名 | `n8n` |
| 对外端口 | `0.0.0.0:5678` |
| 部署目录 | `/opt/n8n` |
| 配置文件 | `/opt/n8n/compose.yaml`、`/opt/n8n/.env` |
| 数据卷 | `n8n_data`，挂载到容器内 `/home/node/.n8n` |
| 重启策略 | `unless-stopped` |
| 时区 | `Asia/Shanghai` |
| 默认界面语言 | `zh-CN`，简体中文 |
| 实例级 MCP | 已启用，通过本机 SSH 隧道连接 |

`/opt/n8n/.env` 中保存了 n8n 的加密密钥，权限为 `0600`。不要把该文件发送给别人，
也不要在已有凭据后随意更换加密密钥，否则 n8n 中保存的凭据可能无法解密。

## 首次使用

浏览器打开 <http://192.0.2.10:5678/>，按页面提示创建 Owner 管理员账号。
当前使用公网 HTTP，登录信息和工作流数据在传输途中没有 HTTPS 保护；建议不要复用其他
网站的密码。后续正式使用时，最好绑定域名并通过 Caddy、Nginx 或 Cloudflare 配置 HTTPS。

## 常用命令

先连接服务器并进入部署目录：

```powershell
ssh my-proxy-vps
cd /opt/n8n
```

查看状态和日志：

```bash
docker compose ps
docker compose logs -f --tail=100
```

重启、停止和启动：

```bash
docker compose restart
docker compose stop
docker compose up -d
```

当前用户已加入 `docker` 用户组。如果旧的 SSH 会话提示无权访问 Docker，退出后重新执行
`ssh my-proxy-vps`，让新的组权限生效。

## 更新 n8n

当前镜像版本固定为 `2.32.6`，避免意外自动升级。更新前先备份数据，然后修改
`/opt/n8n/compose.yaml` 中的镜像版本并运行：

```bash
cd /opt/n8n
docker compose pull
docker compose up -d
docker compose ps
```

这台机器是 `e2-micro`，镜像首次下载、解压和 n8n 数据库迁移可能需要数分钟。

## 备份数据

下面的命令会把持久化卷打包到 `/opt/n8n/backups`。备份文件仍在服务器上，重要工作流
还应再下载到本地或其他存储位置。

```bash
sudo mkdir -p /opt/n8n/backups
sudo docker run --rm \
  -v n8n_data:/data:ro \
  -v /opt/n8n/backups:/backup \
  alpine sh -c 'tar czf /backup/n8n-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .'
ls -lh /opt/n8n/backups
```

## 当前资源情况

部署完成后，根磁盘约使用 `8.0 GB / 30 GB`，剩余约 `21 GB`；n8n 镜像占用约
`2.48 GB`。系统有约 `964 MiB` 内存和 `2 GiB` Swap。这个规格适合轻量工作流和试用，
并发任务、浏览器自动化或大量数据处理可能会比较慢。

## 中文界面

后端仍使用官方 `docker.n8n.io/n8nio/n8n:2.32.6` 镜像，只把与版本完全对应的中文
`editor-ui` 静态资源以只读方式挂载到容器中。中文包来自
`other-blowsnow/n8n-i18n-chinese` 的 `release/2.32.6`，下载文件的 SHA-256 为：

```text
07416c1db325207ce50812996c62fcc5729017eb11e57cda49d5b75d7f54895e
```

服务器上的文件位于 `/opt/n8n/i18n/2.32.6`。浏览器如果仍显示英文，请按
`Ctrl+F5` 强制刷新缓存。汉化属于社区前端，不是 n8n 官方语言包；更新 n8n 时必须同步
换成完全相同版本的中文前端。

## 从本机使用 n8n CLI

项目目录中提供了包装脚本：

```powershell
.\n8n-cli.ps1 --help
.\n8n-cli.ps1 export:workflow --all
.\n8n-cli.ps1 audit
```

脚本通过 `ssh my-proxy-vps` 在正在运行的 n8n 容器内调用官方 CLI。导入、删除或执行工作流
会改变实例数据，运行这些命令前仍应确认参数。

## 从 Codex 使用 MCP

n8n 的实例级 MCP 已由环境变量开启，Codex 全局 MCP 名称为 `n8n-mcp`。连接通过本机
`15678` 端口的 SSH 隧道转发到服务器，不会把 OAuth 或访问令牌直接发送到公网 HTTP。

每次电脑重启或 SSH 隧道退出后，先运行：

```powershell
.\Start-n8n-MCP隧道.ps1
```

查看 Codex MCP 配置：

```powershell
codex mcp get n8n-mcp
```

当前使用 n8n 生成的个人 MCP Access Token 认证。令牌保存在 Windows 用户环境变量
`N8N_MCP_TOKEN` 中，Codex 的 `config.toml` 只引用变量名，不保存令牌正文。修改或轮换令牌后，
需要完全退出并重新打开 Codex，让桌面程序读取新的用户环境变量。

目前不要使用 `codex mcp login n8n-mcp`：实例通过公网 HTTP 访问，而 n8n 2.32.6 的 OAuth
授权会话 Cookie 带有 `Secure` 属性，浏览器不会在这个 HTTP 地址保存它，授权页会立即提示
`Invalid or expired authorization session`。配置 HTTPS 后才能正常使用这条 OAuth 登录路径。

在 n8n 中，全局 MCP 已开启，但工作流的完整读取、修改和运行仍需要单独授权。可在
“设置 → 实例级 MCP”中启用工作流，或打开工作流设置并开启“可在 MCP 中使用”。

当前 MCP 地址只供这台电脑通过隧道使用：

```text
http://127.0.0.1:15678/mcp-server/http
```
