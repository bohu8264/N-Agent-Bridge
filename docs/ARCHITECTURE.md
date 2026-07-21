# Architecture

```text
NuPhy Air75 V3 ANSI (USB / Bluetooth / 2.4G)
  -> HIDDeviceManager + DeviceFingerprintMatcher
  -> MappingEngine
  -> BridgeStore / AgentState
  -> CodexAppServerBackend | ClaudeCodeBackend
  -> OverlayPresenter + SwiftUI

Air75 V3 verified configuration channel (USB / U1 2.4G usage 1:0)
  -> Air75V3LightingController
  -> NuPhyIO 64-byte checksummed reports
  -> backup -> write -> ACK -> delayed readback
```

`Air75AgentBridgeCore` 不依赖 UI，包含 Models、Device/HID、Mapping、Configuration、Agent、Audio 与 Settings。App target 只负责状态编排和呈现。Inspector 复用同一设备识别逻辑，避免诊断工具与产品判断漂移。

Codex Agent 槽位不再等同于侧栏第 1–6 行。`CodexThreadIndexReader` 提供候选线程元数据，`CodexDesktopMetadataReader` 从 Codex 全局状态读取未读/置顶 ID、项目名称/顺序、线程项目归属以及左侧栏 `thread-descriptions-v1` 任务名，`CodexAgentSlotResolver` 按最近、置顶、优先或自定义策略产生六个稳定线程 ID；按键通过 `codex://threads/<thread-id>` 深链打开精确对话。自定义 UI 按 Codex 左侧栏的“项目 → 对话”层级显示，但只绑定具体线程 ID；空槽使用 `codex://threads/new`，并在索引出现新线程后自动绑定。

`CodexDesktopConfirmationObserver` 补齐 rollout 缺失的 Desktop 表单确认：辅助功能遍历时只读取按钮角色/标签，活动日志解析器只接受 `active` 与 `conversationId` 字段；匹配到确认组合后，`CodexDesktopStatusObserver` 对精确线程叠加 `waitingForConfirmation`。焦点按钮走高频轻量路径，完整控件树只低频复核，避免常驻高 CPU。

实体键绑定同时保存可选的 `signalLightIndex`。Air75 V3 使用 NuPhyIO 官方 ANSI 布局与固件 skip 规则，把 HID Usage 转成 D8 灯位；动作换键时灯位一起交换。

设备识别要求 Air75 V3 的 VID/PID、产品别名、制造商、Transport、Usage、序列号与已确认蓝牙别名组合；名称从不单独构成可信匹配。IOHIDManager 不以 seize 方式打开设备，默认只发布 F1–F12、已学习 Usage、候选旋钮 Consumer Usage 或 vendor-defined Usage。灯光控制器使用更严格的精确 USB 身份和配置接口匹配，不与普通键盘输入接口混用。S4 管理事务由进程级协调器串行化，每个逻辑事务先执行 0xEE 会话握手。
