# Air75 V3 Lighting Protocol

当前实现只允许 NuPhy Air75 V3 ANSI：VID `0x19F5`，有线 PID `0x1028`，官方 U1 接收器 PID `0x2620`，配置接口 usage page/usage `1:0`，64-byte Input/Output Report。

## 帧格式

- 请求 byte 0：`0x55`；响应 byte 0：`0xAA`
- byte 1：命令
- byte 3：byte 4–63 的 8-bit 加和校验
- byte 4：payload 长度
- byte 5–6：little-endian address
- byte 7：handle
- byte 8 起：payload

## 0xEE 会话握手

官方 NuPhyIO 在普通命令前发送 `0xEE SetSecretKey`，payload 为 56 个随机字节；payload byte 20 是本次单字节 XOR 会话密钥。随后的请求会对路由字段 byte 4–7 和 payload 进行 XOR，再计算校验和。

固件 1.0.16.6 的响应会保持路由字段明文，只对 payload XOR；旧版固件可能同时 XOR 路由字段和 payload。`NuPhyS4ProtocolCodec` 接受这两种官方返回形式。每个逻辑事务都会重新建立会话，不复用可能被 NuPhyIO 改写的 RAM 密钥。

## 已验证命令

- `0xA1 GetFirmwareInfo`
- `0xB2 GetUseKeys` / `0xB3 SetUseKeys`
- `0xD2 GetKeyLightColor`
- `0xD5 GetLightState`
- `0xD6 SetLightState`
- `0xD8 SetSignalLights`
- `0xF3 GetSleepInfo` / `0xF5 SetSleepCfg`

禁止产品发送 `0xEF SetIapMode`、`0xF1 RestoreFactory` 或其他未经产品流程验证的破坏性命令。

## D5 / D6

D5 handle 0/1 各返回 17 bytes：9-byte 背光与 8-byte 侧灯。应用读取并备份两个 handle，但只写 macOS handle 0。

固件 1.0.16.6 会在写 handle 1 时把未使用的 Windows Profile 元数据（实机观察到 `0x27`）规范化为 `0x00`。旧逻辑同时写两个 handle，因此把这种固件自动整理误报为“D5 回读不一致”。0.14.0 不再修改 handle 1。

D6 要求完整 ACK 回显、延时 D5 回读和最多五次只读重试。失败时只恢复本次修改前的 handle 0，不重复发送结果未知的写命令。2026-07-21 在 Air75 V3 1.0.16.6 真机完成：原值写回、临时亮度改变、精确 D5 回读和最终恢复。

## D8 单键状态灯

payload 是重复的 `[index, red, green, blue]`，每帧最多 14 组。Air75 V3 ANSI：Esc=0，F1–F6=1–6，数字 1=16。状态灯改到其他实体键时，`SignalLightLayout` 根据 HID Usage 解析目标 index。

D8 写入前先用 D2 读取原色，写后再用 D2 精确回读；失败自动写回原色。D2 按稀疏 index 拆成不超过 54-byte 的连续窗口，避免自定义到远端键位时越过单帧上限。真机已完成 D8 原值写回、临时 F1 颜色改变、精确 D2 回读和恢复。

颜色：白色空闲、蓝色推理、绿色完成、橙色等待确认、红色错误。旧版误亮的 Esc 与 Tab index 30 会在不属于当前 Agent 绑定时清除。

## 休眠设置

F3 返回 `[sleepEnable, sleepTimeMinutes, deepSleepTime]`。F5 只修改前两项并保留第三字节，ACK 后延时 F3 精确回读；失败恢复原值。“始终亮着”只把 `sleepEnable` 改为 0。

## 传输

USB-C 与 U1 2.4G 都使用白名单 64-byte S4 配置接口。蓝牙 HID 当前没有官方可验证的 S4 配置特征，因此蓝牙下不写实时灯光。
