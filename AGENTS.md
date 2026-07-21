# N Agent Bridge — AI 接手说明

更新时间：2026-07-21（Asia/Shanghai）

## 1. 项目目标

这是一个面向 NuPhy 键盘的原生 macOS SwiftUI 菜单栏应用，把受支持型号的实体控制中继到当前 Codex Desktop。型号 Profile 与硬件写入 driver 分离；当前完整验证 Air75 V3、Kick75 IO 与 Node100 LP ANSI。未知型号默认只有安全识别能力，不记录普通文字输入，不冒充 OpenAI 官方硬件，也不猜测未知固件写入协议。

当前已构建开发版：`0.13.2 (50)`（精准修复朋友电脑的 F13/F15/Tab/F16… 异常序列；首次配置与灯光读取串行，避免延迟生效；保留真正的用户自定义键）。

- 源码根目录：本文件所在目录
- 0.13.0 按 NuPhyIO 官方 Node100 LP ANSI 的 108 键顺序补齐 D8 布局；Q=44 已完成写入、D2 回读和原色恢复实测。
- 当前安装位置仍可能是上一版；`dist/N Agent Bridge.app` 与 `dist/NAgentBridge-0.13.2-Development.dmg` 已构建校验。最终复核时没有 NuPhy 键盘在线，不能把本轮 USB-C 键位/灯光实写记为已验收；下次接入已验证型号后必须点一次“连接并启用”，确认完整键位回读、灯光通道、HID open、输入监控与辅助功能。
- 当前签名：固定本机身份 `N Agent Bridge Local Signing`，Bundle ID `com.nagentbridge.mac`；不是 Developer ID/Apple 公证的公开发行签名

## 2. 接手后先读

按这个顺序了解项目：

1. `README.md`：产品能力和使用入口
2. 本文件：当前事实、风险和任务清单
3. `PROGRESS.md`：按版本记录的实机结果
4. `BLOCKERS.md`：外部阻塞
5. `docs/ARCHITECTURE.md`：架构
6. `docs/KEYMAP.md`：实体按键映射
7. `docs/LIGHTING-PROTOCOL.md`：已验证灯光协议
8. `docs/USER-GUIDE.zh-CN.md`：安装用户实际操作
9. `docs/ADDING-NUPHY-KEYBOARD.zh-CN.md`：新增 NuPhy 型号的 Profile、driver 与验收规则
10. `docs/PUBLIC-RELEASE.zh-CN.md`：Developer ID、Universal、公证和正式 DMG 流程

`RELEASE.md` 是历史发布记录，不应代替当前任务清单。

## 3. 核心文件地图

- `Sources/Air75AgentBridgeApp/BridgeStore.swift`：应用状态编排、权限、按键动作、灯光同步
- `Sources/Air75AgentBridgeApp/ContentView.swift`：四页 SwiftUI 产品界面
- `Sources/Air75AgentBridgeApp/CodexDesktopRelay.swift`：向当前 Codex Desktop 定向发送原生快捷键，并通过 `codex://threads/<id>` 打开稳定对话
- `Sources/Air75AgentBridgeApp/CodexDesktopStatusObserver.swift`：读取本地线程索引和 rollout 事件，并合并实时确认状态，分别跟踪六个用户任务
- `Sources/Air75AgentBridgeApp/CodexDesktopTitleObserver.swift`：只读调用 Codex app-server `thread/list`，只转发线程 ID 与最终 `Thread.name`
- `Sources/Air75AgentBridgeApp/CodexDesktopConfirmationObserver.swift`：只读 Codex 按钮语义和活动 `conversationId`，识别 rollout 不记录的可见确认卡
- `Sources/Air75AgentBridgeApp/DedicatedKeyEventSuppressor.swift`：消费 F13–F24，防止同时触发系统亮度等功能
- `Sources/Air75AgentBridgeCore/HID/HIDDeviceManager.swift`：Air75 HID 发现、输入监控和隐私过滤
- `Sources/Air75AgentBridgeCore/Device/DeviceProfileRegistry.swift`：加载全部型号 Profile 并选择匹配设备
- `Sources/Air75AgentBridgeCore/Device/KeyboardDriverRegistry.swift`：已验证硬件写入 driver 的唯一白名单
- `Sources/Air75AgentBridgeCore/Configuration/Air75V3KeymapController.swift`：1568-byte 板载键位表备份、修改、回读与恢复
- `Sources/Air75AgentBridgeCore/Configuration/CodexKeybindingInstaller.swift`：安装/迁移 Codex 快捷键
- `Sources/Air75AgentBridgeCore/Lighting/Air75V3LightingController.swift`：NuPhyIO USB 灯光协议
- `Sources/Air75AgentBridgeCore/Power/KeyboardSleepConfiguration.swift`：键盘自动休眠三字节配置的严格解析与编码
- `Sources/Air75AgentBridgeCore/Codex/CodexTaskLightState.swift`：五状态解析和颜色映射
- `Sources/Air75AgentBridgeCore/Lighting/SignalLightLayout.swift`：已验证型号的实体 Usage → D8 灯位映射
- `Sources/Air75AgentBridgeCore/Resources/DeviceProfiles/Air75V3.json`：实际参与打包的设备识别资源；不要用根目录重复副本
- `Sources/Air75ProtocolProbe/main.swift`：硬件协议读取和受保护的实机验证
- `Sources/Air75CoreSelfTest/main.swift`：无 XCTest 环境下的核心自测
- `Distribution/`：Info.plist、权限声明和图标源文件
- `scripts/`：构建、签名、公证、DMG 和校验脚本

## 4. 当前已验证事实

- Air75 V3 USB：VID `0x19F5`、PID `0x1028`、usage `1:0` 配置通道为 64-byte Input/Output Report。
- 实体 F1–F12 已写成板载 F13–F24；旋钮写成 Scroll Lock / Pause / Print Screen 专用事件。
- 当前配置的完整 1568-byte 键位表已备份，写后完整回读通过。
- F1–F6 → Codex 当前任务 1–6；F7 Fast Mode；F8/F9 批准/拒绝；F10 新任务；F11 听写；F12 发送。
- F11 中继目标是 Codex 原生 `Control-Shift-D`，并保留真实 keyDown/keyUp 时长。
- 0.9.1 从 0.9.0 真实升级并完整重启后，当前 macOS 运行诊断：输入监控 `1`、辅助功能 `1`、HID manager open result `0`；固定权限身份已通过升级验证。
- 最近一次实体 F11 已被识别为 usage `0x72`，Bridge 动作为 `pushToTalk / longPress`；仍需用户确认 Codex UI 中听写是否真实启动。
- USB `GetLightState (0xD5)` / `SetLightState (0xD6)`、17-byte 背光/侧灯状态、ACK、延时回读和恢复均已实机验证。
- 背光亮度为 17-byte 状态的 byte 1，直接使用 0–100；0.9.4 已从安装应用真实操作滑块，两个 Profile 均验证 `0x64 → 0x14 → 0x64`。不要再依赖 SwiftUI Slider 偶发缺失的 `onEditingChanged(false)` 回调。
- 自动休眠 `GetSleepInfo (0xF3)` / `SetSleepCfg (0xF5)` 已从官方 NuPhyIO 协议确认，并分别在 Air75 V3 与 Kick75 实机验证；两把当前原值均为 `01 06 18`（启用、6 分钟、保留的深度休眠字段）。应用写前持久备份、只修改启用位与分钟数、保留第三字节，并要求 ACK 与延时回读完全一致；失败时恢复原值。
- 任务侧灯五色已验证：白色空闲、蓝色推理、绿色完成、橙色待确认、红色报错；只修改侧灯字节 9–16。0.7.0 起侧灯显示六任务聚合（红 > 橙 > 蓝 > 绿 > 白）。
- 0.8.0 起五种侧灯颜色可自定义；写入仍只走已验证的侧灯字段、备份、ACK 与完整回读流程。
- 0.8.0 起 12 个 Codex 动作可学习到普通键盘 Usage；普通键只在 Codex 控制开启时由 session tap 消费，媒体键不开放学习。
- `usagePage 0x07 / usage 0xFFFFFFFF` 是 IOHID 键盘数组占位值，不是真实按键。0.9.5/schema 7 会把已有无效绑定按当前硬件 Profile 单项修复，并在 HID 发布、按键学习、映射和事件拦截四层拒绝它；不得重新把它当作可学习按键保存。
- 停止控制必须先通过 USB-C 恢复原始 1568-byte 键位并完整回读。历史备份中较新的多份已经是 Bridge Profile，恢复器必须用 `hasBridgeProfile` 跳过，当前可验证原始备份为 `2026-07-19T02-31-31Z-hardware-keymap.json`。
- `GetLightCount (0xD1)`、`GetKeyLightColor (0xD2)` 只读已实机验证：104 LED = 84 键（0–83）+ 20 侧灯（84–103），312 字节 RGB。
- 旧固件没有单键颜色写入；2026-07-20 的新固件新增 `0xD8 SetSignalLights`。24-byte 六灯写入、8-bit 校验和、完整 ACK 和实机索引 1–6 均已验证；索引 0 是 Esc，不得再次把 F1 映射到 0。
- 六任务状态来源 `~/.codex/state_<N>.sqlite` threads 表（只读、只查结构列），每任务独立解析 rollout 尾部。0.11.3 对 rollout 不记录的 MCP 安装/审批卡，额外只读当前 Codex 窗口按钮角色，并用 Desktop 日志中的活动 `conversationId` 精确覆盖为橙色；不读取聊天正文。
- 0.11.0 查询线程 ID、标题、cwd、recency 与本机未读 ID；不查询提示词、回答或预览。四种 Agent 来源模式最终都绑定线程 ID，不再把 Command+1...6/侧栏位置当身份。
- 0.11.2 自定义分配额外只读 Codex 全局状态中的 `local-projects`、`project-order` 与 `thread-project-assignments` 结构字段，以 Codex 自己的项目层级展示最多 500 个未归档用户对话。0.11.4 读取 `thread-descriptions-v1` 仍会遗漏主任务；0.11.5 已改为 app-server `thread/list(useStateDbOnly: true)` 的正式 `Thread.name`，持久化短描述和 SQLite `title` 仅作兼容兜底。状态解析仍只处理最近 50 个及置顶/自定义精确 ID。
- Air75 V3 ANSI 的 NuPhyIO 可见键顺序与 `skipPos=14/skipSize=3` 已编码为灯位表：例如 F1 = 1、数字 1 = 16。Agent 动作学习到新实体键后，灯位随绑定保存和交换。
- Air65 V3、Air100 V3、Node75 与未实测 Node100 变体的官方 PID/别名已加入安全 Profile。Kick75 IO（`19F5:1026`）已注册独立 1472-byte keymap、D8 与 D6 driver。Node100 LP ANSI（`19F5:1037`）已注册独立 1904-byte keymap（8 层、每层 119 项）、完整 108 键 D8、D6 背光/点阵灯及 F3/F5 driver；只写实机验证通过的 Mac handle 0，handle 1 永不写入。
- Node100 LP ANSI 的基础层 F1–F12 映射为 F13–F24；触控条左滑/双击/右滑分别映射为 Scroll Lock / Pause / Print Screen，Fn 层与未管理字节保持不变。完整写入、1904-byte 回读、原始恢复均已实机验证。
- “连接并启用”在 USB-C 存在时必须读取并验证键盘实际内容，不能只相信本机 `installed` 记录；这用于自动修复固件升级、旧安装或跨机器配置导致的 F1–F12 双重功能。首次成功设置 Air75 V3/Node100 LP ANSI 时仅一次选择 D6“指示灯”背光，之后不覆盖用户选择。
- rollout 推理状态超过 30 分钟没有任何新事件时视为中断并回到空闲；未读只允许完成绿灯延长，不得绕过推理状态过期。
- Kick75 官方 NuPhyIO 只开放侧灯 0 流光、1 霓虹、2 常亮、3 呼吸；模式 4“律动”只属于 Air75 V3。曾被写入 4 时，Kick75 会 ACK 但忽略后续 D6 模式切换，需按实体键 `Fn + M + ←` 恢复一次；产品 UI 不得再向 Kick75 暴露模式 4。
- 其他配置器（NuPhyIO 等）会通过 `SetSecretKey (0xEE)` 给固件设置 XOR 会话密钥，导致本应用读到稳定乱码；控制器已内置 sessionKeyConflict 检测。诊断"灯光状态无效"时先想到这一点，不要先怀疑硬件。
- 官方 U1 2.4G 接收器 VID `0x19F5` / PID `0x2620` 暴露同一 S4 配置通道；用户实机已经枚举到 usage `1:0`、64-byte Input/Output。0.9.8 在数据线拔除、只保留 U1 时完成 D5/D6 状态侧灯写入、ACK 与回读，推理蓝色已验证；A1/F3 是否由接收器转发不再影响 RGB 就绪。蓝牙无官方配置通道（bleConnectionConfig=null）；当前固件不可能由普通 macOS 应用实时写侧灯 RGB。
- 运行 SelfTest 或 Probe 的硬件测试前必须先从菜单栏退出正在运行的 N Agent Bridge；两个进程并发访问 vendor 通道会互相污染响应。

## 5. 安全与产品约束

- 未知 Vendor HID 写入一律禁止猜测。任何硬件写入必须有：完整备份、已知命令/长度、ACK、完整回读、失败恢复。
- 不要把“键盘有单键 RGB LED”写成“电脑可以实时设置任意单键颜色”；这两件事不同。
- 不读取、记录或上传用户提示词和回答正文。Codex 状态只解析事件类型、线程来源和时间戳。
- 输入事件只匹配设备 Profile 中的可信身份和受管 Usage；不要监听所有键盘输入。
- 合成事件只能定向发送给当前 `com.openai.codex` 进程，不广播给其他应用。
- 不要删除 `~/Library/Application Support/Air75AgentBridge/Backups`；这里存放用户键位和灯光恢复数据，不属于源码目录。
- 本机开发构建必须继续使用固定 Bundle ID 与 `N Agent Bridge Local Signing`。不得退回 ad-hoc，也不得重新生成同名证书；两者都会再次改变 macOS TCC 身份。
- 正式分发必须使用 Developer ID Application、Hardened Runtime、Notarization 和 Stapling。

## 6. 当前任务清单

### P0 — 可用性与发布身份

- [ ] 获取 Developer ID Application 证书和 notarytool Keychain profile。
- [x] 建立失败即停止的公开发行流水线：双架构分别编译并合并 Universal、Developer ID 强校验、DMG 签名、Notarization、Stapling、Gatekeeper 与 SHA-256 最终校验。
- [x] 删除应用未使用的麦克风/网络签名权限；Universal 本机包不再出现 invalid entitlements blob 警告。
- [x] 用固定本机身份签名 App；构建号 14/999 的 CDHash 不同但 Designated Requirement 完全一致。
- [x] 用户为新固定身份完成最后一次授权；完整重启 App 后输入监控/辅助功能均为 `1`，HID manager open result 为 `0`。
- [ ] 在当前已授权状态下做一次 F1–F12、旋钮、F11 听写的完整 Codex Desktop 端到端验收。
- [ ] 若 F11 仍只被 Bridge 捕获而 Codex 不响应，核对当前 Codex 的 `Control-Shift-D` 和 `composer.startDictation`，不要再修改 Air75 板载键位。
- [x] 已确认内容和敏感信息，并创建 Git 基线提交用于 GitHub 托管。
- [ ] 安装 0.9.0 后实测：数字键自定义不会同时输入字符；停止并恢复成功提示后拔线，F 区与旋钮回到键盘原生功能。
- [x] 修复 F1 被学习为 `P07/UFFFFFFFF` 后任意打字跳转任务 1；真实配置已迁移为 F13（usage `0x68`），F2–F12 自定义绑定保持不变。

### P1 — 六个 Agent 任务与状态灯

- [x] 软件侧把 `CodexDesktopStatusObserver` 从单个最近任务扩展为最多六个用户任务快照（state_<N>.sqlite threads 表 + 每任务 rollout 解析）。
- [x] 在 UI 中显示六路状态（概览与灯光页 SixTaskStatusRow），侧灯改为聚合策略并有自测。
- [x] 删除 Command+1..6 与 recency 可见顺序强关联；四种模式使用稳定线程 ID 和 `codex://threads/<id>`。
- [ ] 实机验收单击后台切换、350ms 内双击前台显示，以及自定义空槽自动绑定新对话。
- [x] 当前可见的 MCP 安装/审批确认卡通过辅助功能按钮语义与活动线程 ID 映射为橙灯，处理后自动恢复。
- [ ] 后台未渲染任务的确认状态仍等待 Codex Desktop 提供可共享 app-server/正式事件接口。
- [x] 旧固件能力调查完成，0xD1/0xD2 只读实机打通；新固件 `0xD8` 六灯写入、ACK、实机布局与 F1–F6 状态同步均已验证。
- [x] 修正 `0 = Esc、1–6 = F1–F6`，并让 Codex 任务灯与官方侧灯灯效完全分离。

### P1 — 无线验收

- [x] 软件侧建立独立 `KeyboardLightingConnection`，实现 U1 2.4G 通道识别、传输切换重连、任务颜色实时写入与休眠唤醒补发。
- [x] 用户插入 U1 2.4G 接收器：`--wireless-enumerate` 已确认 `19F5:2620` usage `1:0`、64/64 配置接口。
- [x] 0.9.8 在只保留 U1 接收器的真实 2.4G 环境中完成状态侧灯写入、ACK 和回读；推理状态蓝色已验证，应用诊断为 `twoPointFourGHzReceiver / available=1`。
- [ ] 继续观察一次长时间休眠后的任意键唤醒补发；基础 2.4G 实时同步不再阻塞。
- [ ] 用户拔掉 USB 并切换 Air75 V3 到 Bluetooth，确认 `Air75 V3-2` 真正连接；先跑 `--wireless-enumerate` 记录蓝牙 HID 身份和 Usage。
- [ ] 蓝牙下验证 F1–F12、旋钮、休眠/唤醒、断线重连以及板载 Profile 保留。
- [x] 蓝牙灯光能力定案：官方目录 `bleConnectionConfig=null`，macOS 枚举也没有 S4/Vendor 配置接口；当前固件下只支持按键，实时侧灯需要切换到 2.4G。若未来固件新增已公开且可回读的 BLE 配置通道，再增加独立 driver。

### P2 — 工程质量

- [ ] 安装完整 Xcode 后恢复 `swift test` 的 XCTest 验证。
- [ ] 为六任务状态排序、过期、完成保持 60 秒、报错保持 120 秒补充测试。
- [ ] 在干净 Mac 做拖拽安装、首次授权、Codex 重启、登录启动、升级和卸载验收。
- [x] 把新固件 `0xD8`、实机索引和侧灯恢复结论同步到 `docs/LIGHTING-PROTOCOL.md`。
- [x] 加入 Air65 V3、Air100 V3、Kick75、Node75、Node100 官方身份 Profile 与软件模式能力分级。
- [ ] 继续按型号验证 Air65 V3、Air100 V3、Node75 及 Node100 其他布局/高度版本的板载键位、灯位、U1 路由和恢复；Node100 LP ANSI 的 USB-C 能力已完成，2.4G 路由仍待独立验证。

## 7. 构建与验证

当前这台 Mac 只安装了 `/Library/Developer/CommandLineTools`，没有完整 Xcode（`swift test` 的 XCTest 不可用，核心测试用 `Air75CoreSelfTest`）。在 Codex 沙箱中构建要把 ModuleCache 放到 `/tmp` 并关闭 SwiftPM 自己的二次沙箱。

注意：SelfTest 与 Probe 的硬件测试会打开 vendor HID 通道，运行前先退出正在运行的 Air75AgentBridge 应用，否则两个进程的响应帧互相污染（会看到稳定的"灯光状态无效"乱码）。

为避免把大型缓存重新留在源码目录，普通验证优先使用临时 scratch path：

```sh
CLANG_MODULE_CACHE_PATH=/tmp/air75-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/air75-clang-cache \
swift build --disable-sandbox --scratch-path /tmp/air75-agent-bridge-build --product Air75AgentBridge

CLANG_MODULE_CACHE_PATH=/tmp/air75-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/air75-clang-cache \
swift run --disable-sandbox --scratch-path /tmp/air75-agent-bridge-build Air75CoreSelfTest --software-only
```

发布构建会按设计生成本地 `.build` 和 `dist`：

```sh
./scripts/build-release.sh
./scripts/create-dmg.sh
./scripts/verify-release.sh
```

上面只生成带版本号的 `NAgentBridge-<版本>-Development.dmg`。正式站外发行必须先准备 Developer ID 与 notarytool Keychain profile，然后设置版本、构建号、身份和 profile，运行：

```sh
./scripts/release-public.sh
```

只有该脚本完整成功后才会产生可外发的 `dist/NAgentBridge.dmg`；不得把带 `Development` 的文件发给其他 Mac。

发布脚本默认要求固定本机签名身份；缺失时先运行 `scripts/ensure-local-signing-identity.sh`，不要用 `-` 绕回 ad-hoc。不要为了“试一下”覆盖 `/Applications/N Agent Bridge.app`。

## 8. 完成标准

任何功能只有同时满足以下条件才能标记完成：

1. 源码编译和 `Air75CoreSelfTest` 通过；
2. 在当前 Codex Desktop 上做真实端到端验证；
3. 涉及键盘写入时有写前备份、写后回读和恢复结果；
4. 涉及 macOS 权限时重启 App 后仍然有效；
5. 用户可从 `docs/USER-GUIDE.zh-CN.md` 独立完成安装和使用；
6. 未验证、协议阻塞和仅推断能力必须明确标注，不能包装成已支持。
