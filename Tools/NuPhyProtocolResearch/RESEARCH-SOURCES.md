# NuPhy 协议研究来源（2026-07-19）

结论已写入 `docs/LIGHTING-PROTOCOL.md` 与 `BLOCKERS.md`。本文件只记录来源，
便于复核。原始抓取物（含 NuPhyIO 专有 JS，不入仓库）归档在工作区
`../research-nuphy-20260719/`。

## 官方

- NuPhyIO 配置器（真实应用在 drive.nuphy.io，io.nuphy.com 只是营销壳）：
  bundle `https://drive.nuphy.io/static/js/main.f6f60294.js`（2026-07-19 版本）。
  io.nuphy.com 会对非浏览器 TLS 指纹重置连接，抓取需换 UA/走浏览器。
- S4 完整命令表出自 webpack module 40877；帧构造出自 module 36937；
  两个键盘 API 类（S4 机械 / EG 霍尔）在 module 86736。
- 设备目录（全系 VID/PID，含 U1 dongle 2620）出自 Next.js flight payload。

## 社区逆向（交叉印证）

- kelchm/nuphy-tools — S4 家族 PROTOCOL.md、sk 自动检测方法
- fldc/nuphyctl — Rust CLI，Air75 V3 灯光 offset 表、WebHID 抓包方法论
- Z3R0-CDS/nuphy-linux — udev 规则中的 VID/PID 表
- donn/nudelta（仅 V1）、nuphy-src/qmk_firmware（仅 V2）——确认均不适用 V3

## 本仓库自有工具

- `extract-simple-module.mjs` — 从 webpack bundle 按模块 ID 提取模块
- `Air75ProtocolProbe --keylight-read` — 0xD1/0xD2 只读实机探测
- `Air75ProtocolProbe --wireless-enumerate` — 无线验收用只读 HID 枚举
