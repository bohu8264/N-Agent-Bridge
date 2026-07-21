# Lighting Protocol

## 已验证的 Air75 V3 USB 协议

当前 NuPhyIO WebHID 客户端对 VID `0x19F5`、PID `0x1028`、usage page/usage `1:0` 使用 64-byte Output/Input Report：

- request byte 0 为 `0x55`，response byte 0 为 `0xAA`；
- byte 1 为命令，byte 2 恒为 0；
- byte 3 是 byte 4–63 的 8-bit 加和校验；
- byte 4 为 payload 长度，byte 5–6 为 little-endian address，byte 7 为 handle；
- payload 从 byte 8 开始。

已在连接的 Air75 V3 上验证：

- `0xA1 GetFirmwareInfo`；
- `0xD5 GetLightState`，handle 0/1 各返回 17 bytes；
- `0xD6 SetLightState`，ACK 回显 17-byte payload；
- `0xD1 GetLightCount`：实机返回 `0x68`（104 = 84 键 + 20 侧灯）；
- `0xD2 GetKeyLightColor`：只读逐 LED 颜色。按 3 字节 RGB × 104 = 312 字节，
  地址为表内字节偏移、分块 ≤ 54 读取。实机验证 LED 0–83 为按键区、LED
  84–103 为侧灯区，边界与官方参数完全一致（`Air75ProtocolProbe --keylight-read`）；
- `0xD8 SetSignalLights`：2026-07-20 的 Air75 V3 新固件新增。地址和 handle
  均为 0，payload 为重复的 `[index, red, green, blue]`，最多 14 组。实机照片
  确认索引 0 是 Esc，索引 1–6 才对应 F1–F6；一次写入 6 灯为 24-byte payload。已验证
  请求、8-bit 校验和及完整 ACK 回显；
- 背光与侧灯 mode、界面 0–100 亮度、RGB 颜色；侧灯在线路中使用 0–255 原始亮度并换算为百分比；
- 背光亮度为 byte 1，线路直接使用 0–100。0.9.4 已通过安装应用的真实 UI 对两个 handle 验证 `0x64 (100%) → 0x14 (20%) → 0x64 (100%)`；
- 写入后延时读取、状态范围校验和最多 5 次重试；
- 常亮蓝色写入后两个 handle 都成功回读，再恢复测试前原状态。

17-byte 状态由 9-byte 背光和 8-byte 侧灯组成。应用只修改明确字段，其他字节原样保留，并在第一次修改前保存两个 handle 的完整原始数据。

## 灯光保持时间与自动休眠（0xF3 / 0xF5）

官方 NuPhyIO 将灯光保持时间与键盘自动休眠作为同一项固件配置：键盘达到设定的无操作时间后熄灯并休眠。S4 协议使用：

- `0xF3 GetSleepInfo`：读取严格 3-byte payload；
- `0xF5 SetSleepCfg`：写入 `[sleepEnable, sleepTimeMinutes, deepSleepTime]`，ACK 回显同一 3-byte payload；
- `sleepEnable` 只能为 0 或 1，分钟数有效范围为 1–127；选择“始终亮着”只把启用位改为 0，仍保留上一次分钟数；
- `deepSleepTime` 的含义不在产品界面开放，任何设置都必须原样保留该字节。

连接的 Air75 V3 实机原值为 `01 06 18`（启用、6 分钟、第三字节 `0x18`）。已验证同值写入 ACK 与延时回读完全一致，并通过已安装 App 的 UI 完成 6 → 10 → 6 分钟往返，最终恢复原值。实际事务在每次写入前读取并持久备份原始三字节，写入后要求 ACK 和 `0xF3` 回读一致；任一阶段失败会尝试写回原值。

## S4 命令表（自官方 NuPhyIO bundle 反混淆，2026-07-19）

读：`0x2F GetDongelName`、`0xA0 GetBase`、`0xA1 GetFirmwareInfo`、`0xB1 GetDefaultKeys`、
`0xB2 GetUseKeys`、`0xB5/B8/BB Get SOCD/TapDance/TGL`、`0xC2 GetMacro`、
`0xD1 GetLightCount`、`0xD2 GetKeyLightColor`、`0xD5 GetLightState`、
`0xE1 GetKeyboardFunc`、`0xF3 GetSleepInfo`、`0xFA GetAppDefineSize`、`0xFB GetAppDefine`。

写：`0xB3 SetUseKeys`、`0xB4 RestoreUseLayers`、`0xB6/B9/BC Set SOCD/TapDance/TGL`、
`0xC1 SetKeyUpload`、`0xC3 SetMacro`、`0xD6 SetLightState`、`0xD8 SetSignalLights`（新固件）、`0xE2 SetKeyboardFunc`、
`0xEE SetSecretKey`、`0xEF SetIapMode`（进 bootloader，禁止发送）、`0xF1 RestoreFactory`、
`0xF5 SetSleepCfg`、`0xFC SetAppDefine`。

## 会话密钥（0xEE）与冲突检测

NuPhyIO 连接时会用 `SetSecretKey (0xEE)` 与固件协商一个单字节 XOR 密钥（sk），
之后帧头 byte 4–7 与 payload 均被 XOR，校验和在 XOR 后计算。sk 保存在键盘
固件中直到断电。若本应用在 sk ≠ 0 时用明文帧通信，响应会呈现稳定的"乱码"。
两个控制器现在会用响应 byte 4–7 与请求字段的四元 XOR 一致性检测该状态，
并报出 `sessionKeyConflict` 引导用户关闭其他配置器并重新插拔键盘。本应用
不发送 0xEE，保持明文会话。

## 无线传输

- **2.4G 接收器（官方支持）**：U1 dongle VID `0x19F5` / PID `0x2620` 暴露同样的
  usage 1:0 64-byte 配置接口，说同一 S4 协议。NuPhyIO 通过它无线配置键盘。
  两个控制器与 Probe 已同时匹配 0x1028 与 0x2620。0.9.7 根据最近一次真实输入
  来自有线键盘还是接收器选择活动配置通道，并记住成功响应的通道；优先通道无响应时
  只在这两个白名单接口之间回退。无线休眠后的第一下任意按键会触发重新握手并补发
  状态色。0.9.8 已在用户实机只保留 U1 时完成 D5/D6 写入、ACK 与回读；A1 固件信息
  和 F3 休眠管理按可选能力处理，不再阻断已经工作的 RGB 通道。
- **蓝牙（官方不支持配置）**：NuPhyIO bundle 中所有设备 `bleConnectionConfig`
  均为 null，蓝牙下无任何官方配置通道；本机蓝牙验收时可用
  `Air75ProtocolProbe --wireless-enumerate` 只读确认是否存在 usage 1:0 接口。

## 六个 Agent 任务指示灯

旧固件确实没有单灯写入路径，因此此前只使用软件六格与侧灯聚合。NuPhy 研发新增
`0xD8` 后，应用按一个事务向索引 1–6 发送 F1–F6 六组颜色：白色空闲、蓝色推理、
绿色完成、橙色待确认、红色报错；0.11.0 起未分配槽位写黑熄灭，已分配但空闲才显示白色。0.10.0 曾按
索引 0–5 写入，实机表现为 Esc、F1–F5 点亮而 F6 不亮；0.10.1 已依据真实布局修正。
由于 D8 颜色会保留，0.10.1 每次同步还会显式写入 `index 0 = 00 00 00`，清除旧版留在 Esc 上的状态色。

F1–F6 能独立显示后，Codex 不再写侧灯。schema 8 升级会从最早的硬件灯光备份
恢复一次侧灯 9–16 字节，之后普通侧灯完全由键盘原灯效和用户设置控制。

0.11.0 不再把六路状态永久硬编码在 F1–F6。`KeyBinding.signalLightIndex` 与实体 Usage 一起保存；Air75 V3 ANSI 使用 NuPhyIO 官方布局的可见键顺序，并按 `skipPos=14 / skipSize=3` 去除三个隐藏旋钮项。例如 F1 为 1、数字 1 为 16。Agent 动作改键或与另一个动作交换时，D8 灯位同步移动，旧灯位会写黑清除。没有已验证 `signalLightLayoutID` 的型号不会执行这种写入。

新固件还会在 D5 backlight mode 返回 `0x15`。0.10.0 已把该值纳入合法状态；旧版
只接受 0–20，正是升级固件后侧灯突然停止同步的原因。
