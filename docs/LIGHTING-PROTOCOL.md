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

连接的 Air75 V3 与 Kick75 实机原值均为 `01 06 18`（启用、6 分钟、第三字节 `0x18`）。Air75 V3 已通过安装 App 的 UI 完成 6 → 10 → 6 分钟往返；Kick75 的受保护 Probe 完成 F5 同值写入、临时“始终亮着”`00 06 18`、逐次 ACK/F3 精确回读并恢复 `01 06 18`。实际事务在每次写入前读取并持久备份原始三字节，只修改前两项并保留第三字节；任一阶段失败会尝试写回原值。

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

### Kick75 IO（0.12.4）

实机 `19F5:1026` 的 `D1 GetLightCount` 返回 `0x55`（85），`D5` 两个
17-byte 状态与 `D2` 颜色读取有效。D8 对索引 1–6 的 24-byte 测试返回完整
payload 回显并自动恢复；安装后的独立 D2 回查确认 index 0 为 Esc、1–6 为
F1–F6。当前 `nuphy.kick75.ansi-d8` 只发布这组已验证的 F 区映射。

连续只读确认两个 D5 handle 稳定；NuPhyIO 公开型号资料将它们标为 Mac 与 Windows
灯光 Profile。受保护 Probe 因此只写 Mac handle 0，依次验证 D6 no-op、背光模式、
背光常亮 RGB、侧灯模式、侧灯常亮 RGB。每项都完成完整 ACK、延时 D5 回读和测试前
状态精确恢复，最终双 handle 与测试起点一致。RGB 的绿色通道有一次 `0x8B → 0x8C`
固件量化，正式 driver 只对 RGB bytes 6–8 / 14–16 接受 ±1，其余字段必须精确相同。

handle 1 曾把旧内部字段规范化，不能保证逐字节恢复，因此 Kick75 正式 driver 永远
只写 handle 0；读取和备份仍保留两个 handle。任何 ACK 或 D5 回读失败都会尝试恢复
本次操作前的 handle 0。Kick75 的普通背光与侧灯由此解除灰色；U1 路由仍等待独立
实机验证，不得因 USB D6/F3/F5 通过而顺带开放。

Kick75 休眠能力单独验证，不由 D6 结果推断。F3 读取 `01 06 18` 后先生成持久备份，
再以 F5 完成原值 no-op 与 `00 06 18` 临时始终亮着；每次都要求三字节 ACK 完整回显、
220ms 后 F3 精确回读，最终恢复 `01 06 18`。只有通过该流程后，Profile 才加入型号专属
`nuphy.s4.kick75-sleep` 白名单并开放灯光保持时间。

Kick75 的 D8 自定义键布局来自官方 NuPhyIO `Kick75` ANSI 数组。数组源位置 14–16
是旋钮减音量、静音、加音量三个隐藏项，固件可见键 index 必须在此之后减 3；因此
Q 的源位置 33 对应 D8 index 30。受保护 Probe 已对 index 30 完成原色备份、测试色
D8 ACK、D2 精确回读和原色恢复。正式布局同时发布数字、字母、符号、修饰键、空格
和方向键的标准 HID Usage，Agent 1–6 改键后状态颜色随实体位置移动。

官方 Kick75 NuPhyIO 配置只列出四种侧灯模式：`0` 流光、`1` 霓虹、`2` 常亮、
`3` 呼吸；[Kick75 Quick Guide](https://cdn.shopify.com/s/files/1/0268/7297/1373/files/nuphy-kick75-nuphyio-quick-guide.pdf?v=1750241100)
也给出实体切换快捷键 `Fn + M + ←`。Air75 V3 额外拥有的模式 `4`“律动”不能写给
Kick75：实机证明固件虽然返回完整 D6 ACK，却会停在 4 并忽略后续 0–3 切换。
0.12.3 改为型号级白名单，UI 与 driver 都不再向 Kick75 暴露 4。受保护 Probe 对
0–3 四种模式逐项采样到 800ms，全部 D5 精确一致并在每轮后恢复原状态。

D6 ACK 后的正式回读最多尝试五次，每次只发送 D5，不重复发送状态未知的 D6。
如果最终仍不一致，继续沿用写前状态回滚；若回滚后 D5 可读，应用保留灯光通道可用，
不会因为一次无效选择把全部灯光控件永久置灰。

### Node100 LP ANSI（0.13.0）

Node100 LP ANSI 精确身份为 `19F5:1037`。D5 返回两个稳定的 17-byte 状态；受保护 Probe 确认 handle 0 可写，handle 1 保持只读。背光常亮/呼吸/RGB 与第二灯区常亮/呼吸/RGB 都经过 D6 ACK、延时 D5 回读和原值恢复。产品将第二灯区命名为“点阵灯效”，只开放已验证模式，不复用 Air75/Kick75 的侧灯模式列表。

F3 原值为 `01 06 18`。F5 同值写入、临时“始终亮着”`00 06 18`、逐次精确回读和最终恢复均通过，正式 driver 只修改启用位和分钟数。

D1 返回 108，与官方 Node100 LP ANSI 108 键顺序一致，因此 D8 不使用 Kick75 的隐藏旋钮 skip 规则。已确认 F1=1、F12=12、数字 1=25、Q=44、Space=100、Right=105；Q=44 已完成临时蓝色写入、D2 回读和原色恢复。完整标准键布局已写入 `SignalLightLayout`，Agent 动作更换实体键后状态灯随 Usage 移动。

新固件还会在 D5 backlight mode 返回 `0x15`。0.10.0 已把该值纳入合法状态；旧版
只接受 0–20，正是升级固件后侧灯突然停止同步的原因。
