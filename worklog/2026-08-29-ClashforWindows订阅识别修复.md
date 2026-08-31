# Clash for Windows 订阅识别修复

## 做了什么

让 Worker 的受控 Clash UA 规则正确识别 `Clash for Windows/0.20.x`，并添加了对应回归测试。

## 为什么做

上一轮安全收紧后，规则只接受无空格的 `ClashforWindows`，会把正常 Windows 客户端误判成 Base64 订阅。

## 值得记住的决策、坑和技术点

- 放宽的是产品名内部的标准分隔符，不是把 `clash` 变回任意子串匹配。
- UA 协商的顺序保持 V2Ray 优先，因此混合 `v2rayNG ... clash-compatible` 仍安全地拿到 Base64。

## 一句话亮点

安全白名单既不误伤 Clash for Windows，也不放开模糊的 clash 关键词。
