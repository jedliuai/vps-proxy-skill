<div align="center">

# 🌐 VPS Proxy Skill

### 你准备服务器，Codex 交付节点。

**把仓库地址发给 Codex，让它帮你搭好自己的 VPN 节点。**

![Codex](https://img.shields.io/badge/Built_for-Codex-18181B?style=for-the-badge)
![Protocols](https://img.shields.io/badge/节点方案-3_种-0F766E?style=for-the-badge)
![Clients](https://img.shields.io/badge/Clash_·_V2Ray_·_Shadowrocket-订阅交付-2563EB?style=for-the-badge)

[![Repository checks](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml/badge.svg)](https://github.com/jedliuai/vps-proxy-skill/actions/workflows/validate.yml)

[🚀 一步开始](#quick-start) · [✨ 三种节点](#nodes) · [English](./README.en.md) · [版本发布](https://github.com/jedliuai/vps-proxy-skill/releases)

</div>

---

**小白也能一步开始，不需要学习 VPS、网络或 VPN 搭建知识。**

你只需要按 Codex 的提示提供服务器信息、连接好 SSH。条件检查通过并获得你的授权后，安装、配置、测试和生成订阅，都由 **Codex 自动执行**，不需要你照着教程敲命令。

<a id="quick-start"></a>

## 🚀 只需把这句话发给 Codex

```text
请用这个仓库帮我自动搭建自己的 VPN 节点：
https://github.com/jedliuai/vps-proxy-skill

获取完整仓库，先阅读 AGENTS.md 和 skill/vps-proxy-builder/SKILL.md。
需要什么 VPS 信息请直接问我，先帮我连接好 SSH。
检查条件并取得我的授权后，请直接执行完整部署和测试，
不要把技术步骤交给我手动操作。最后把适合我客户端的订阅交付给我。
```

**然后跟 Codex 聊就行，不用先读完这个仓库。**

Codex 会向你询问 VPS 连接信息；不知道在哪里找，就让它告诉你。SSH 就是让 Codex 能远程操作你的服务器——连接好后，剩下的技术工作交给它。

本文默认你已在 Codex 安装好 **GitHub 和 Cloudflare 插件**，并允许它使用终端与网络。遇到账号授权提示时，按提示确认即可。

---

<a id="nodes"></a>

## ✨ 一次搭建，三种节点

**Hysteria2、Trojan、VLESS REALITY**——本项目选用的三种互补方案，Codex 会完成配置和检查，你不用先研究该怎么搭。

| 节点 | 特点 | 对你有什么用？ |
| :--- | :--- | :--- |
| ⚡ **[Hysteria2](https://v2.hysteria.network/)** | 面向高延迟、易丢包网络的性能设计 | 看视频、下载时可优先尝试，实际表现由你的线路决定 |
| 🛡️ **[Trojan](https://xtls.github.io/en/config/transport.html)** | 使用常见的 TLS 加密连接方式 | 日常使用的另一选择，也可在 Hysteria2 所需网络通道受限时尝试 |
| 🧩 **[VLESS REALITY](https://xtls.github.io/en/config/transports/reality.html)** | 让连接外观接近普通网页访问 | 提供不同的连接方案，与前两种互为备选 |

不必记住这些名字，告诉 Codex 你用的是 Clash、V2Ray 还是小火箭即可。它会核对客户端支持情况并交付订阅。**三种节点共用你的同一台 VPS，不是三个国家的线路**；没有一种协议能保证在所有网络下都最快或永不断连。

---

## 📦 你准备服务器，它负责搭建

你需要自己可管理的 **VPS 和域名**。还没准备好，或不知道现有服务器能不能用，直接问 Codex；它会先检查要求，不需要你提前研究技术参数。

你不用挑协议、写配置、安装面板或排查命令报错。Codex 会完成适用范围内的部署与检查，最后给你适合 **Clash、V2Ray 或小火箭**的私密订阅入口。导入自己的客户端，就可以开始试用。

购买、账号登录和必要授权由你完成；最后还需要你在自己的网络上试一下。**“一步”指一步发起任务，不代表任何服务器都能无条件部署成功。** 条件不满足时，Codex 会告诉你缺什么，不会硬装或擅自扩大操作范围。

## 💬 以后出问题，也交给 Codex

不必重新找教程，也不用先学会排障。告诉 Codex：

> 我的节点最近经常断连，请按这个仓库的技能检查原因，先保住现有可用节点。

它会检查问题，再根据证据处理；需要额外授权时会问你。这里的经验不只用于第一次搭建，也用于以后的检查和维护。

## 💡 为什么做这个项目？

为了搭一个节点，反复看 YouTube 视频、翻 X 上的教程，仍然可能卡在某个细节。每个人都重新学一遍，没有必要。

**把搭建经验写给 Codex，把能用的结果交给用户。**

这里所说的自建 VPN、翻墙、科学上网或“魔法”，指在你自己的服务器上搭建私人代理节点。本仓库不提供免费服务器或公共订阅，服务器、域名等费用由你承担。不要公开自己的订阅链接或密钥。

---

<div align="center">

### 少看一份教程，多一个能用的节点。

由 [jedliuai](https://github.com/jedliuai) 维护 · [更多项目](https://github.com/jedliuai?tab=repositories)

有帮助就点个 **Star**，或把这个仓库发给同样不想折腾教程的朋友。

[给 Codex 的完整技能](./skill/vps-proxy-builder/SKILL.md) · [反馈问题](./CONTRIBUTING.md) · [安全约定](./SECURITY.md) · [许可说明](./CONTRIBUTING.md#修改与许可--changes-and-licensing)

</div>
