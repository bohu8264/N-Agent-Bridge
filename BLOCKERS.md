# External Blockers

这里只记录无法由普通应用代码自行解决的外部阻塞。

## 1. 蓝牙实机验收等待实体切换

当前键盘通过 USB 连接。系统记录 `Air75 V3-2` 已配对但未连接。蓝牙 VID/PID、HID Usage、旋钮事件、休眠/唤醒必须在用户拔线并切换硬件模式后实测，不能用 USB 结果代替。验收时先运行 `Air75ProtocolProbe --wireless-enumerate`（只读）记录蓝牙侧全部 HID 接口。

2026-07-20 复核：NuPhyIO 设备目录中 Air75 V3 仍为 `bleConnectionConfig=null`；蓝牙 HID 只提供按键输入与很小的标准 LED 输出报告，没有 S4 所需的 64-byte usage 1:0 配置接口。蓝牙下按键和板载灯效可用，但 F1–F6 实时任务颜色仍需等待固件新增公开、可回读的 BLE 配置特征；普通应用无法通过权限或软件模拟补出该通道。

## 3. 普通键自定义的 macOS 设备归属限制

0.8.0 可以把 Codex 动作分配到数字、字母、F 区或导航键，并在控制开启时用 session event tap 消费原字符。IOHID 回调只接受已识别 Air75，但 macOS 公开的非 root CGEvent session tap 不提供事件来自哪一把实体键盘的可靠身份，因此相同虚拟键在其他键盘上也会被消费。应用只在用户明确开启 Codex 控制时启用该规则，停止或退出后立即解除；如需多键盘并精确区分来源，需要 DriverKit/HIDDriver 或板载任意矩阵写入协议，当前不猜测实现。

## 4. Apple 公证的公开分发凭据缺失

2026-07-20 已完成软件侧发行流水线：arm64/x86_64 分别编译并合并 Universal、无多余 entitlement、Developer ID 与 TeamIdentifier 强校验、Hardened Runtime、安全时间戳、DMG 签名、notarytool 公证、Stapling、Gatekeeper、磁盘映像和最终 SHA-256 校验。开发包已改名为 `NAgentBridge-Development.dmg`，正式文件名只会在公开流水线中产生。

当前钥匙串仍只有 `N Agent Bridge Local Signing`，没有 Developer ID Application；也没有可用的 notarytool Keychain profile。Apple Developer Program 账号持有人必须先取得并安装 Developer ID Application 证书，并在本机交互式保存公证凭据。没有这两项外部身份时，不能向 Apple 提交、不能生成 Apple 已认可的正式 `NAgentBridge.dmg`，本地证书也不适合发给其他 Mac。

## 5. macOS 用户授权与 Codex Desktop 命令兼容性

中继与系统事件拦截必须获得输入监控和辅助功能权限。macOS 明确要求用户本人在系统设置中确认，应用和安装包不能静默授权。应用只匹配 Air75 V3 的专用 Usage，并只向当前 `com.openai.codex` 进程发送映射后的快捷键。

按键动作仍沿用经 0.5.0 验证的 Codex Desktop 中继，写入当前支持的 `~/.codex/keybindings.json` 命令。0.11.5 新增的独立 app-server 连接只调用只读 `thread/list` 获取 ID 与正式 `Thread.name`，不承接 Codex Desktop 的任务执行或批准。F11 直接使用 Codex 原生 `Control-Shift-D`；Codex Desktop 更新后若调整其他内部命令名，需要重新校验命令表。应用保留用户原快捷键并为改写前文件创建备份。

## 6. Codex 后台审批实时状态仍缺公开稳定通道

0.11.3 已用辅助功能按钮语义和 Desktop 活动 `conversationId` 补齐当前可见任务的安装、MCP 表单与普通审批橙灯，不读取聊天正文。剩余风险是：Codex Desktop 的 app-server 使用私有 stdio，另起进程无法读取其 `waitingOnApproval/waitingOnUserInput`；后台未渲染任务的 MCP 确认卡也不在辅助功能树中。因此“六个后台任务全部实时审批”仍需未来稳定、可共享的 app-server RPC 或官方事件接口。本地 `state_<N>.sqlite` 同样没有兼容承诺，升级改列时应用会自动回退目录扫描。

## 7. 新增 NuPhy 型号的硬件写入等待实机

Air65 V3、Air100 V3、Node75、Node100 已能凭官方 PID/产品名进入安全软件按键模式。NuPhyIO 目录表明它们属于 S4 家族并有背光/侧灯，但这不能替代实机验证：键位表长度、矩阵地址、D8 固件、灯位 skip 规则和 U1 路由都可能不同。拿到每个型号后必须分别完成读取、备份、写入、ACK、完整回读和恢复，之后才能在 `KeyboardDriverRegistry` 注册 driver。当前禁止为了“看起来支持”而复用 Air75 V3 写入 driver。

Kick75 IO 已在 `19F5:1026` 实机完成独立 1472-byte 键位 driver、D1/D2/D5 读取、D8 F1–F6 单键状态灯、D6 Mac handle 0 的背光/侧灯模式、颜色与精确恢复，以及 F3/F5 休眠时间验证。Windows handle 1 原值写回会被固件规范化部分内部字段，因此正式 driver 永不写入 handle 1；只剩 Kick75 U1 路由保持关闭，等待独立验证。

Kick75 的普通侧灯不是外部阻塞：官方只提供模式 0–3，0.12.3 已逐项实机通过。模式 4 是 Air75 V3 专属效果，不能作为 Kick75 能力暴露；若旧版曾写入 4，需在键盘上按一次 `Fn + M + ←` 让固件回到有效模式。
