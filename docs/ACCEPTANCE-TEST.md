# Air75 V3 Acceptance Test

## 自动化

- `Air75CoreSelfTest --software-only` 全部通过。
- App 为 Universal `arm64 + x86_64`，Bundle 只含 `Air75V3.json`。
- 固定签名 designated requirement 与上一版一致。
- DMG 可只读挂载，App、Applications 链接和中文安装说明齐全，`hdiutil verify` 通过。

## USB-C 实机（官方固件 1.0.16.6）

- 精确识别 `19F5:1028`，未知型号不进入写入路径。
- A1 固件读取成功；每个逻辑事务先完成 0xEE 会话握手。
- D5 能读取 macOS/Windows 两个灯光状态；正式 D6 只写 macOS handle 0。
- D6 no-op、临时变化、D5 精确回读和最终恢复通过。
- D8 no-op、临时单灯变化、D2 精确回读和最终恢复通过。
- B2 1568-byte 键位表完整读取；配置后 F1–F12 对应 F13–F24，旋钮与原始备份可恢复。
- 拔插、应用重启和 Mac 唤醒后不会长期停在“USB-C 待响应”。

## 全新 Mac

1. 拖入 Applications。
2. 首次被 Gatekeeper 拦截时只点“仍要打开”。
3. 授予输入监控和辅助功能后完整退出并重开。
4. 退出 NuPhyIO，键盘切到有线模式，点“连接并启用”。
5. 应用只有在键位回读、权限和灯光握手全部成功后才显示就绪。

## 无线边界

- U1 2.4G 只走已验证路由；首次板载配置必须 USB-C。
- 蓝牙没有 S4 配置通道，因此只保证按键输入，不宣称实时单键灯光。
