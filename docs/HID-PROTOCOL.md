# HID Protocol

## 已验证 USB 身份

- VID `0x19F5` / PID `0x1028` / Product `Air75 V3` / Manufacturer `NuPhy`。
- 4 个 top-level HID interface：Mouse(1/2)、Keyboard(1/6)、vendor channel candidate(1/0)、第二 Keyboard(1/6)。
- usage 1/0 接口的 MaxInput/MaxOutput 均为 64 bytes。

NuPhy 官方 WebHID 应用的公开脚本包含 Air75 V3 同一 VID/PID，并通过 report 0 发送 64-byte Output Report。这证明存在配置通道，不证明任意命令格式或蓝牙可用性。未经已知命令、长度、校验和与恢复流程验证，不写入该通道。

Inspector 的 `--listen` 只读捕获输入；应用默认过滤普通 Keyboard Usage。校准模式会显示已识别 Air75 V3 的所有 Usage，但不持久化按键内容。
