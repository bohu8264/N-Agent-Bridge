# N Agent Bridge

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://github.com/bohu8264/N-Agent-Bridge/releases)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

N Agent Bridge 是一个原生 macOS 工具，把受支持的 NuPhy 键盘变成 Codex Desktop 的实体控制台。它支持稳定的 Agent 对话绑定、批准/拒绝、听写、发送、推理深度控制、任意实体键映射，以及已验证型号的六路实时状态灯。

> 这是独立第三方开源项目，与 OpenAI、Codex 或 NuPhy 无隶属关系。

## 下载与安装

当前可下载版本为 **0.13.1 Development**：

- [下载 0.13.1 测试版 DMG](https://github.com/bohu8264/N-Agent-Bridge/releases/download/v0.13.1-development/NAgentBridge-0.13.1-Development.dmg)
- [查看 0.13.1 发布说明、安装包与源码包](https://github.com/bohu8264/N-Agent-Bridge/releases/tag/v0.13.1-development)
- SHA-256：`5971087e36852805866b8f3a2ab0a38d9e68cb0162eb7425993c82123d7bc2c4`

安装步骤：

1. 下载 DMG，把 **N Agent Bridge.app** 拖入“应用程序”。
2. 第一次设置请使用 USB-C 数据线，并把受支持的 NuPhy 键盘切换到有线模式。
3. 在 macOS“系统设置 → 隐私与安全性”中允许“输入监控”和“辅助功能”。
4. 返回应用，点击“连接并启用”。0.13.1 会读取键盘真实配置，把实体 F1–F12 自动写成专用 F13–F24 事件并完整回读；Air75 V3 与 Node100 LP ANSI 首次配置还会自动选择“指示灯”背光。

从旧版升级、更新过键盘固件或换到另一台 Mac 后，也请用 USB-C 再点一次“连接并启用”。应用不会只相信旧的“已配置”记录，因此不会留下同时触发 Codex 动作和 macOS 原生功能的 F1–F12。历史推理事件 30 分钟没有新活动会自动回到空闲，不再让无任务槽位长期误亮蓝灯。

当前免费测试包使用项目自签名证书，并未经过 Apple 公证。若 macOS 阻止首次打开，请到“系统设置 → 隐私与安全性”确认来源后选择“仍要打开”。不要关闭整个系统的 Gatekeeper。

完整图文步骤见 [中文使用说明](docs/USER-GUIDE.zh-CN.md)。

## 已实现功能

| 实体控制 | Codex 动作 |
| --- | --- |
| Agent 1–6 | 按当前来源模式打开六个对话；单击后台切换，双击唤到前台 |
| F7 | 切换 Fast Mode |
| F8 / F9 | 批准 / 拒绝 |
| F10 | 新建任务 |
| F11 | Codex 原生听写 |
| F12 | 发送 |
| 旋钮左转 / 按下 / 右转 | 降低推理深度 / 打开选择器 / 提高推理深度 |
| Node100 触控条左滑 / 双击 / 右滑 | 降低推理深度 / 打开选择器 / 提高推理深度 |

六个 Agent 状态灯：

- 白色：空闲
- 蓝色：正在思考
- 绿色：任务完成
- 橙色：等待确认
- 红色：发生错误

Agent 对话来源支持 Codex Micro 官方的四种模式：最近对话、置顶对话、优先对话、自定义分配。所有模式都使用 Codex 对话 ID，而不是侧栏的临时位置，因此任务完成后重新置顶不会再让按键打开错误对话。自定义分配按 Codex 左侧栏的“项目 → 对话”层级选择；项目名、顺序和归属来自 Codex 本机状态，任务显示名使用 app-server 正式 `Thread.name`，会随 Codex 左侧栏实时更新。

12 个动作都能学习到数字、字母、F 区或导航键。Air75 V3、Kick75 IO 和 Node100 LP ANSI 上把 Agent 1–6 改到其他已知实体键时，`0xD8` 状态灯会跟随新的实体灯位。

## 硬件支持

目前 **NuPhy Air75 V3、Kick75 IO、Node100 LP ANSI** 已完成 USB-C 硬件验证。Air65 V3、Air100 V3、Node75 和 Node100 其他变体已加入官方身份 Profile，可先使用不写未知固件的安全软件按键模式。

| 型号 | 软件按键控制 | 板载专用层 / 状态灯 / 侧灯写入 |
| --- | --- | --- |
| Air75 V3 | 支持 | 已验证 |
| Air65 V3 | 支持 | 待实机验证 |
| Air100 V3 | 支持 | 待实机验证 |
| Kick75 IO | 支持 | F1–F12、旋钮、USB-C Agent 状态灯及背光/侧灯已验证 |
| Node75 | 支持 | 待实机验证 |
| Node100 LP ANSI | 支持 | F1–F12、触控条、完整 108 键状态灯、背光/点阵灯及休眠已验证 |
| Node100 其他变体 | 支持 | 待逐型号实机验证 |

灯效按型号开放：Air75 V3 侧灯支持流光、霓虹、常亮、呼吸、律动；Kick75 官方只支持前四种；Node100 LP ANSI 使用独立的点阵灯常亮/呼吸白名单。应用不会向型号写入未验证模式。

| 连接方式 | 按键控制 | Agent 实时状态灯 | 说明 |
| --- | --- | --- | --- |
| USB-C | 支持 | 支持 | 首次配置与恢复必须使用 |
| 官方 U1 2.4G | 支持 | 支持 | 需要接收器/键盘固件转发配置命令 |
| Bluetooth | 支持 | 暂不支持 | 当前固件没有可验证的实时灯光配置通道 |

Agent 独立颜色需要包含 `0xD8 SetSignalLights` 的新版固件和对应型号的已验证灯位表。应用不会向未知型号或未经验证的 HID 通道盲目写入数据。

其他 NuPhy 键盘可以继续适配，但必须先新增独立设备 Profile，并逐项完成实机读取、备份、写入、ACK、完整回读和恢复验证。详见 [新增 NuPhy 键盘型号](docs/ADDING-NUPHY-KEYBOARD.zh-CN.md)。

## 隐私与安全

- 只识别受支持键盘和已映射的控制键，不记录普通文字、密码或聊天内容。
- Codex 状态读取仅使用本地线程 ID、app-server `Thread.name`、项目名称/顺序/归属、项目目录、事件类型和时间戳；`thread/list` 附带的首条消息预览会立即丢弃，不读取或保存任务正文与回答正文，所有数据只在本机使用。
- Codex 可见确认卡只读取按钮标签和活动任务 ID，用于让精确 Agent 灯变橙；不读取确认问题或聊天正文。
- 不保存 API Key，不复制 Codex 登录凭据，不上传 HID 报告。
- 合成按键只定向发送给正在运行的 Codex Desktop。
- 所有硬件写入都受型号 driver 白名单、备份、ACK、回读和失败恢复保护。

更多信息见 [隐私说明](docs/PRIVACY.md) 与 [架构说明](docs/ARCHITECTURE.md)。

## 本地开发

要求：

- macOS 13 或更高版本
- Swift 5.9+
- Xcode Command Line Tools；运行 XCTest 建议安装完整 Xcode

```sh
git clone https://github.com/bohu8264/N-Agent-Bridge.git
cd N-Agent-Bridge

CLANG_MODULE_CACHE_PATH=/tmp/nagent-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/nagent-clang-cache \
swift build --disable-sandbox --scratch-path /tmp/nagent-build --product Air75AgentBridge

CLANG_MODULE_CACHE_PATH=/tmp/nagent-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/nagent-clang-cache \
swift run --disable-sandbox --scratch-path /tmp/nagent-build Air75CoreSelfTest --software-only
```

发布和硬件测试前请先阅读 [AGENTS.md](AGENTS.md)、[PROGRESS.md](PROGRESS.md) 与 [BLOCKERS.md](BLOCKERS.md)。协议探测工具会打开 Vendor HID 通道，运行前必须退出正在运行的 N Agent Bridge，避免两个进程争用设备。

## 参与开发

不需要成为仓库协作者：

1. Fork 本仓库；
2. 从 `main` 创建功能分支；
3. 完成代码、文档与相关测试；
4. 向本仓库提交 Pull Request。

具体要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

## 发布说明

普通开发构建由 `scripts/build-release.sh`、`scripts/create-dmg.sh` 和 `scripts/verify-release.sh` 生成。Apple 官方认可的站外发行还需要 Developer ID Application、Notarization 与 Stapling；相关流水线已在 `scripts/release-public.sh` 中实现，详见 [正式站外发行说明](docs/PUBLIC-RELEASE.zh-CN.md)。

## License

本项目使用 [MIT License](LICENSE)。
