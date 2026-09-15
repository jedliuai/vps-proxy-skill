# 反馈与协作 / Feedback and collaboration

[中文](./README.md) · [English](./README.en.md) · [Security](./SECURITY.md)

最有帮助的反馈是：哪个步骤、期望什么、实际发生什么，以及最小可复现条件。先查看现有 [Issues](https://github.com/jedliuai/vps-proxy-skill/issues) 和[排障参考](./skill/vps-proxy-builder/references/troubleshooting.md)。不提供响应时限或个人服务器代管承诺。

Useful reports identify the step, expected/actual behavior and a minimal reproduction. Search existing issues first. There is no guaranteed response time or managed-server support.

## 报告问题 / Report a problem

- 工具箱 tag/commit；服务器系统与架构；涉及的客户端及内核版本。/ Toolkit revision, OS/architecture, client and core versions.
- 新部署、订阅导入还是已有节点诊断；失败阶段与脱敏错误类型。/ Setup, import or diagnosis; failure stage and redacted error category.
- 已验证与未验证的检查，以及能安全复现的最小步骤。/ Verified/unverified checks and safe reproduction steps.

**不要上传完整日志、订阅 URL/YAML/URI、私钥、IP、真实域名、SSH 配置、云账号或个人路径。** Base64 订阅仍是凭据。安全问题请先读 SECURITY.md；不要在公开 Issue 中发布漏洞利用细节或泄漏凭据。

**Do not upload full logs, subscription payloads, private keys, IPs, real domains, SSH config, cloud IDs or personal paths.** Base64 is not encryption. Read SECURITY.md before reporting security-sensitive details publicly.

## 修改与许可 / Changes and licensing

修改应小而可验证，说明影响范围并遵循 AGENTS.md。文档改动不应连接 VPS；不要为测试关闭 TLS 校验或覆盖现用客户端配置。检查命令见首页，远程部署锁测试不属于本地检查。

Keep changes scoped and testable; follow AGENTS.md. Documentation work must not connect to a VPS. Local checks are listed in the README; the SSH deployment-lock test is not a local check.

仓库尚未选择开源许可证；涉及复用、再分发或代码贡献条款，请先向作者确认。本指南不是额外授权或贡献者协议。

No open-source license has been selected. Clarify reuse, redistribution and contribution terms with the author first. This guide does not grant additional rights or establish a contributor agreement.
