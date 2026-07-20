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

0.8.0 沿用经 0.5.0 验证的 Codex Desktop 中继，写入当前支持的 `~/.codex/keybindings.json` 命令，不启动独立的 Codex app-server。F11 直接使用 Codex 原生 `Control-Shift-D`；Codex Desktop 更新后若调整其他内部命令名，需要重新校验命令表。应用保留用户原快捷键并为改写前文件创建备份。

## 6. 六任务侧栏顺序依赖 Codex 内部实现

六任务状态读取 `~/.codex/state_<N>.sqlite` threads 表（只读、只查结构列）。两个已知风险：该库 schema 无兼容承诺，Codex 升级可能改名/改列（应用已按最高版本号自动发现并保留目录扫描回退）；侧栏处于 `mode="project"` 分组模式时，Command+1..6 的可见顺序可能与纯 recency 排序错位，上线前需一次 UI 实测核对。另外 rollout 文件中没有任何审批类事件，"橙色待确认"当前无法从磁盘数据触发——真实审批信号只存在于 app-server RPC 通道，需后续接入。
