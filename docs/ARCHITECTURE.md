# Architecture

```text
Air75 V3 (USB / Bluetooth)
  -> HIDDeviceManager + DeviceFingerprintMatcher
  -> MappingEngine
  -> BridgeStore / AgentState
  -> CodexAppServerBackend | ClaudeCodeBackend
  -> OverlayPresenter + SwiftUI

Air75 V3 (USB usage 1:0 only)
  -> Air75V3LightingController
  -> NuPhyIO 64-byte checksummed reports
  -> backup -> write -> ACK -> delayed readback
```

`Air75AgentBridgeCore` 不依赖 UI，包含 Models、Device/HID、Mapping、Configuration、Agent、Audio 与 Settings。App target 只负责状态编排和呈现。Inspector 复用同一设备识别逻辑，避免诊断工具与产品判断漂移。

设备识别要求 VID/PID、产品别名、制造商、Transport、Usage、序列号与已确认蓝牙别名组合；名称从不单独构成可信匹配。IOHIDManager 不以 seize 方式打开设备，默认只发布 F1–F12、已学习 Usage、候选旋钮 Consumer Usage 或 vendor-defined Usage。灯光控制器使用更严格的精确 USB 身份和配置接口匹配，不与普通键盘输入接口混用。
