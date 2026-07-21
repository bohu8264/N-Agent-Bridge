# 新增 NuPhy 键盘型号

N Agent Bridge 从 0.9.0 起把“识别设备”和“向设备写入”分成两层。新增型号不能复制 Air75 V3 的 VID/PID 后直接复用写入协议。

## 第一阶段：安全识别

1. 在 `Sources/Air75AgentBridgeCore/Resources/DeviceProfiles/` 新建独立 JSON。
2. 为型号分配永久 ID，例如 `nuphy.air96-v3`；ID 发布后不改名。
3. 填入实机读取的 USB VID/PID、蓝牙产品名、厂商名和 Usage Page。
4. `protocolFamily` 不确定时使用 `unknown`，`capabilities` 中的 driver ID 全部留空。

完成这一阶段后，应用可以识别和显示该型号，也可以使用经过过滤的软件按键路径；它不会获得 Vendor HID 写入权限。

当前 Air65 V3、Air100 V3、Kick75、Node75、Node100 已完成这一阶段。Profile 的 PID 来自官方 NuPhyIO 设备目录，但 `capabilities` 中没有 driver ID，因此用户可以把数字、字母、F 区或导航键映射到 Codex，而应用不会改写键盘固件。

## 第二阶段：硬件能力验证

每项能力分别验证，不能由同系列型号推断：

- 完整读取键位表并确认长度、分块地址和校验算法；
- 写入前创建带型号 ID、设备指纹和字节长度的原始备份；
- 写入后等待设备 ACK，并完整读回逐字节比较；
- 用同一份原始备份执行恢复，再完整读回；
- 灯光协议需分别确认背光与侧灯字段，未知 Report 永不试写；
- 单键状态灯还需确认该型号固件包含 `0xD8`、取得可回读灯数，并根据官方布局/实机逐键确认 `signalLightLayoutID`；
- USB、2.4G 与蓝牙是三条独立通道，不能互相代替验收。

验证完成后，在 `KeyboardDriverRegistry` 注册一个代码中的 driver ID，并把同一 ID 写入该型号 JSON。只有这里的白名单能开启硬件写入。

## 兼容与恢复规则

- `hardwareProfileID` 记录当前哪一种键盘拥有板载专用层；连接另一型号时必须先恢复原键盘。
- 键位和灯光备份按 Profile ID 隔离，禁止跨型号恢复。
- 旧版 Air75 V3 配置迁移为 `nuphy.air75-v3`；Application Support 目录暂时保留旧名，以保护历史原始备份。
- 对外品牌、Bundle ID 与代码签名证书不得随新增型号变化；这保证 macOS 输入监控和辅助功能权限身份稳定。
