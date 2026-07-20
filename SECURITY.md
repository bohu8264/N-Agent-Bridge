# Security Policy

## 支持范围

安全修复优先针对 `main` 和 GitHub Releases 中最新版本。Development 构建不是 Apple 公证的正式发行包，但仍接受安全报告。

## 私下报告安全问题

请使用 GitHub 仓库的 **Security → Report a vulnerability** 私密报告入口。不要在公开 Issue 中发布以下内容：

- 可利用的 HID 写入序列或可能损坏设备的复现步骤；
- 用户凭据、Token、聊天内容或本机隐私数据；
- 未公开的设备序列号、固件或厂商资料；
- 代码签名、公证或供应链凭据。

报告请包含受影响版本、macOS 版本、键盘型号/固件、连接方式、复现步骤和影响范围；个人信息与抓包内容请先脱敏。

## 安全边界

本项目不会尝试绕过 macOS 输入监控、辅助功能或 Gatekeeper 授权。未知键盘和未经验证的 Vendor HID 协议默认不可写。请勿提交关闭系统安全机制作为解决方案。
