# Air75 V3 HID Protocol

## 身份与接口

- USB：VID `0x19F5`、PID `0x1028`、产品名 `Air75 V3`。
- U1 接收器：VID `0x19F5`、PID `0x2620`；只在能回读目标键盘身份时使用。
- S4 配置通道：Usage Page `0x01` / Usage `0x00`，64-byte input/output report，report ID 0。

## 会话

官方固件 1.0.16.6 在普通 S4 命令前要求 `0xEE SetSecretKey`。请求携带 56-byte challenge；challenge 第 20 字节是当前 XOR 会话密钥。每个逻辑事务重新握手，以兼容重连、休眠或 NuPhyIO 改变设备 RAM 中密钥的情况。

1.0.16.6 回复保留明文路由头并加密 payload；旧固件可能同时加密路由头和 payload。解码器会验证命令、长度和校验和后才接受任一格式，不用“看起来像数据”的启发式猜测。

## 已验证命令

- `A1`：固件版本。
- `B2/B3`：1568-byte Air75 V3 键位读取/写入。
- `D1/D2`：灯数与单灯颜色读取。
- `D5/D6`：灯效状态读取/写入；正式应用只写 macOS handle 0。
- `D8`：单灯颜色写入；写后必须 D2 精确回读。
- `F3/F5`：休眠设置读取/写入。

协议细节、D5 字段和 D8 数据结构见 `docs/LIGHTING-PROTOCOL.md`。任何未知 PID、长度、ACK、校验和或回读结果都会停止写入。
