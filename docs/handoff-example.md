# 交付应该长什么样？ / What should a handoff contain?

[中文首页](../README.md) · [English](../README.en.md) · [验收流程](../skill/vps-proxy-builder/references/validation.md)

这是**说明性示例，不是实际部署报告、测速或可导入订阅**。所有测试状态均为待验证，用来说明用户应向 Codex 索取什么。不要将自己的交付文件上传到 Issue。

This is an illustrative checklist, not deployment evidence or an importable subscription. All results below are unverified. Keep your real handoff private.

## 两个客户端入口 / Two client-labelled entries

| 客户端 / Client | 应交付的内容 / Expected delivery |
| --- | --- |
| Clash / Mihomo | 私密 YAML 订阅入口；说明默认策略与备用切换 / Private YAML entry and routing/fallback explanation |
| v2rayN / v2rayNG / Shadowrocket | 私密 URI/Base64 入口；说明协议兼容性，且不含 Clash 分流组 / Private URI entry with protocol compatibility; no Clash routing groups |

入口保存在用户独占文件中，不在公开聊天、截图或仓库中展示。三个协议是同一台 VPS，不是三个国家。备用订阅只在确有需要时单独标注，不把一串候选链接当交付。

Store entries in an owner-only file. Three protocols do not mean three countries. Label backup subscription entries separately only when needed.

## 已测与未测 / Verification status

| 检查 / Check | 示例状态 / Example status | 需要的证据 / Evidence needed |
| --- | --- | --- |
| 新 SSH 登录与 sudo / Fresh SSH and sudo | 待验证 / Not tested | 新非 root 密钥会话成功，恢复控制台可用 / Fresh key-only session and console access |
| Hysteria2、Trojan、REALITY | 待验证 / Not tested | 各协议真实代理请求成功，不只看服务 active / Actual proxied requests per protocol |
| 订阅导入 / Subscription import | 待验证 / Not tested | 指定客户端和内核版本成功解析 / Named client/core parses successfully |
| 家庭网络与晚高峰 / Home network and peak hours | 待用户验收 / User test pending | 实际网络、时间窗口、请求总数与失败数 / Network, window, request and failure counts |
| 自动切换 / Fallback | 待授权测试 / Approval pending | 受控故障后切换及恢复，不影响现用配置 / Controlled failover and recovery |

## 以后如何维护 / Maintenance handoff

Codex 应另行私密记录：工具箱 revision、协议版本、证书到期及续期检查、恢复点、允许的维护范围、费用责任和未解决问题。区分更新技能、刷新订阅、重载客户端和升级服务器；不要因为一个步骤成功就声称全部验收通过。

Privately record toolkit revision, protocol versions, certificate renewal checks, recovery points, authorized scope, cost responsibilities and unresolved items. Toolkit updates, subscription refreshes, client reloads and server upgrades are separate operations.
