# 安全约定

## 永远不要提交的内容

- `/etc/proxy-stack/secrets.env` 与 `subscription-urls.txt`。
- Hysteria2 密码、Xray UUID、REALITY 私钥和 Short ID。
- Trojan 密码，以及通用 URI/Base64 订阅的任何解码结果。
- 主订阅或备用订阅的完整 URL。
- Cloudflare API Token、Worker `SUB_TOKEN`、Wrangler 本地缓存和 `.dev.vars`。
- SSH 私钥、Clash 实际订阅 YAML、Cookie 或浏览器会话。
- 从服务器临时复制、用于上传 KV 或验收的订阅文件和临时客户端配置。

这些文件和常见命名已由 `.gitignore` 排除，但提交前仍应执行：

```powershell
pwsh .\scripts\validate-repo.ps1
git diff --cached
```

## 公开内容边界

公开仓库只保留 Skill、部署/维护脚本、测试、非敏感示例和公共项目维护记录。个人实例盘点、无关应用教程、原始运维日志、账单、访问记录和备份不应上传，即使已用示例值替换部分字段。

真实 IP、域名、SSH 别名/用户名/本机路径、云账户或项目标识，以及确切恢复备份位置，不是“没有密码就可公开”的信息。部署时在授权范围内读取它们，交付和恢复资料保存到仓库外、用户独占的文件；公开 worklog 仅保留目标代号、通用技术结论和脱敏测试结果。

`.gitignore` 不能撤销已跟踪文件，也不能穷举敏感文件名。检查新增文件、暂存区、全部待推送历史和提交者邮箱；发现敏感数据已经公开时先报告暴露范围，取得必要轮换授权，再处理历史与平台缓存。删除当前文件不等于撤回已发布版本。

## 订阅处理边界

- Worker 的 `SUB_TOKEN` 保持在 secret 中；不要为排障把它写入命令历史、日志、报告或截图。
- Cloudflare KV 的 `clash-config` 与 `v2ray-config` 只能通过安全的临时文件上传，完成后立即删除。
- 覆盖 KV 前，把当前两个 key 写入 Git 忽略且当前用户独占的本地备份目录；部署脚本不会备份 Cloudflare KV、secret 或 Worker。
- 8443 令牌路径已关闭新的 access log，但历史 Nginx 日志可能仍含旧路径；日志必须保持 root-only，不得为排障复制或放宽权限。若曾被不可信主体读取，应轮换备用令牌。
- `v2ray.txt` 是通用 URI/Base64 列表，不是“所有 V2Ray Core 都能导入”的承诺；旧 Core 可能不支持
  Hysteria2 或 REALITY。策略组、规则和自动选择只存在于 Clash YAML。

## 凭据疑似泄漏

1. 取得轮换授权后，按 [部署参考](./skill/vps-proxy-builder/references/deployment.md) 配置自己的目标和管理员，通过 SSH/主机变更/CA 确认后执行 `rotate` 动作，轮换全部代理及订阅凭据。它会运行完整部署，不是无影响的订阅刷新；不要在 SSH 入口未验证时强行执行。
2. 使用 Wrangler 更新 Worker secret 和私有 KV。
3. 在 Clash 中重新导入新订阅并确认旧订阅返回 404。
4. 若敏感值已经进入 Git 历史，仅删除当前文件不够；应立即作废凭据，再清理历史并强制更新远端。

## 仓库可见性

`vps-proxy-skill` 是独立的公开代码仓库，从经过审查的脱敏文件快照和新的初始提交开始，不继承私有前身的 Git 历史。原私有仓库保持独立；不应依赖“仓库私有”来保护任何运行凭据。

以后新增文件或导入改动时，继续检查实际域名/IP、账户标识、提交元数据、日志、备份与待推送历史。个人运行资料只保存在 Git 之外，不要把私有仓库整体合并或镜像推送到这里。公开访问代码不代表授权操作作者或其他使用者的 VPS；插件也不能绕过私有资源的权限。

## 历史清理后的协作

- 历史重写会改变提交 ID。旧克隆、旧工作树和 Git bundle 应当作为私有恢复材料，不要 merge、pull 后再 push，也不要镜像推送回远端。重新克隆清理后的仓库继续工作。
- 若旧克隆还有未提交工作，先私下备份，只把经过检查的必要文件改动应用到新克隆，不导入整个旧 Git 数据库。
- 提交身份使用自己的 GitHub 公共用户名和 noreply 邮箱；新使用者不要复用作者身份。推送前同时检查文件、提交元数据与所有待推送引用。
- 强制推送不等于删除 GitHub 上全部旧对象。公开前还要检查旧提交地址、PR 引用、Fork、Actions 日志与元数据、附件和缓存。发现仍可取回的个人信息时保持 Private，必要时联系 GitHub Support；不要靠“旧链接不容易猜到”判断安全。
- 本地隐私备份和清理申请中的证据不要上传到 Issue、工作总结或其他公开位置。真实凭据若曾泄漏，清理历史不能替代经授权的凭据轮换。

参考：[GitHub 删除仓库敏感数据说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)。
