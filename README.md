# N Agent Bridge

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://github.com/bohu8264/N-Agent-Bridge/releases)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

N Agent Bridge 是面向 **NuPhy Air75 V3 ANSI** 的原生 macOS 工具，把键盘的 F 区与旋钮变成 Codex Desktop 实体控制台。当前版本只保留 Air75 V3，避免把未验证协议写入其他型号。

> 独立第三方开源项目，与 OpenAI、Codex 或 NuPhy 无隶属关系。

## 下载

当前版本：**0.14.2 Development**，适配 NuPhy Air75 V3 官方固件 **1.0.16.6**。

- [下载 0.14.2 DMG](https://github.com/bohu8264/N-Agent-Bridge/releases/download/v0.14.2-development/NAgentBridge-0.14.2-Development.dmg)
- [发布说明与源码](https://github.com/bohu8264/N-Agent-Bridge/releases/tag/v0.14.2-development)
- SHA-256：`9e5cf34158d0259521778292e23330902f9cd11c2c1fc506d898744703428ed6`

Development 包使用项目固定自签名证书，未经过 Apple 公证。macOS 第一次拦截时，请到“系统设置 → 隐私与安全性”选择“仍要打开”，不要关闭整个 Gatekeeper。

## 首次使用

1. 把 App 从 DMG 拖到“应用程序”，不要直接在 DMG 内运行。
2. 将 Air75 V3 更新到官方固件 `1.0.16.6`，切换到有线模式并使用数据 USB-C 线连接。
3. 完全退出浏览器中的 NuPhyIO 配置页，避免两个配置器争用同一个 HID 通道。
4. 在 macOS“隐私与安全性”中允许 N Agent Bridge 的“输入监控”和“辅助功能”，然后退出并重新打开 App。
5. 点击“连接并启用”，等待应用完成键位备份、F13–F24 写入、完整回读和指示灯初始化。

macOS 的两项权限都必须由用户本人批准，安装包不能静默授予。完整说明见 [中文使用说明](docs/USER-GUIDE.zh-CN.md)。

## 功能

| 实体控制 | Codex 动作 |
| --- | --- |
| F1–F6 | Agent 1–6 |
| F7 | 切换 Fast Mode |
| F8 / F9 | 批准 / 拒绝 |
| F10 | 新建任务 |
| F11 | Codex 原生听写 |
| F12 | 发送 |
| 旋钮左转 / 按下 / 右转 | 降低推理深度 / 打开选择器 / 提高推理深度 |

应用把物理 F1–F12 的板载键值改为 F13–F24，因此不会同时触发 macOS 原生亮度、媒体或音量功能。停止控制时可通过 USB-C 安全恢复原始键位。

六个 Agent 键支持自定义到其他已知实体键，状态灯会跟随新的实体位置：白色空闲、蓝色思考、绿色完成、橙色等待确认、红色报错。Agent 来源支持最近、置顶、优先和自定义四种策略，并按稳定对话 ID 绑定，不依赖会变化的侧栏位置。

## 连接能力

| 连接 | 按键控制 | F1–F6 状态灯 | 管理设置 |
| --- | --- | --- | --- |
| USB-C | 支持 | 支持 | 首次配置、恢复与全部灯效 |
| 官方 U1 2.4G | 支持 | 支持 | 固件提供 S4 转发时可用 |
| 蓝牙 | 支持 | 暂不支持 | 官方固件未暴露可回读的实时灯光通道 |

## 1.0.16.6 兼容修复

官方 NuPhyIO 会先发送 `0xEE SetSecretKey` 建立单字节 XOR 会话。固件 1.0.16.6 的响应保留明文路由头、仅加密 payload；旧固件则会加密路由头和 payload。应用在每个逻辑事务前重新握手，同时兼容两种返回格式。

灯光 D5 仍读取 macOS/Windows 两个 Profile，但 D6 只写 macOS handle 0。新版固件会在写 handle 1 时规范化未使用字段，旧逻辑因此误报“USB-C 待响应”。D6、D8、D2、完整 1568-byte 键位表及失败恢复都已在 Air75 V3 1.0.16.6 真机验证。

部分 Air75 V3 在官方 1.0.16.6 固件下会把第 8 层旋钮按下位置 p60 保持为未分配值 `0x0000`。0.14.2 只在这个已确认的位置接受空值，配置时将其初始化为专用事件 `0x0048`，再对完整 1568-byte 键位表逐字节回读；其他层、其他位置和未知矩阵值仍会停止写入。

## 隐私与安全

- 不记录普通文字、密码或聊天正文。
- 不保存 API Key，不上传 HID 报告。
- 硬件写入只匹配 Air75 V3 精确 VID/PID 与配置接口。
- 键位、灯光和休眠事务均先备份，再写入、ACK、延时回读；失败自动恢复。
- 配置和硬件备份保存在用户本机。

## 本地开发

```sh
git clone https://github.com/bohu8264/N-Agent-Bridge.git
cd N-Agent-Bridge
swift build --disable-sandbox --product Air75AgentBridge
swift run --disable-sandbox Air75CoreSelfTest --software-only
```

发布或硬件测试前必须阅读 [AGENTS.md](AGENTS.md)、[PROGRESS.md](PROGRESS.md) 与 [BLOCKERS.md](BLOCKERS.md)。开发者可以 Fork 仓库后提交 Pull Request；详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT License](LICENSE)
