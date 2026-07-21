# Progress

更新时间：2026-07-21 CST

## 0.14.0：Air75 V3 官方固件 1.0.16.6 专版

- 产品范围已收口为 NuPhy Air75 V3 ANSI（USB PID `0x1028`、U1 接收器 PID `0x2620`）。其他键盘 Profile、驱动、灯位表、测试和说明已删除；未知型号不会进入 Vendor HID 写入路径。
- 定位官方 1.0.16.6 更新后“USB-C 待响应”的根因：S4 事务需要先发 `0xEE SetSecretKey`，会话密钥为挑战数据第 20 字节；1.0.16.6 回复保留明文路由头但用会话密钥加密 payload，旧固件则可能同时加密路由头和 payload。统一 codec 已兼容两种格式，每个逻辑事务都重新握手，避免 NuPhyIO 或设备重连后沿用失效密钥。
- D5/D6 灯光控制只写 macOS handle 0。官方固件会规范化 Windows handle 1 的保留字段，应用仍会读取并备份它，但不再把这种固件行为误判为写入失败或改写用户的 Windows 配置。
- D8 单键状态灯改为“写入前读取原色 → 写入 → D2 精确回读 → 失败自动恢复”。F1–F6 默认索引为 1–6；旧版异常 Tab 灯位会被清理，用户主动把 Agent 分配到其他已知实体键时灯光仍跟随真实灯位。
- Air75 V3 完整键位安装继续使用 1568-byte B2 回读；配置时把物理 F1–F12 安全改为 F13–F24，并保留完整原始备份。固件升级恢复默认键位后，应用会要求 USB-C 重新配置，不会只相信本机旧记录。
- 当前连接的 Air75 V3 1.0.16.6 已完成实体保护验证：A1 固件读取、D5 双 handle 备份、D6 no-op/临时修改/精确恢复、D2/D8 F1 单灯 no-op/临时修改/精确恢复、B2 1568-byte 全表回读与 F13–F24 Profile 检查全部通过。
- 实机备份保存在 `~/Library/Application Support/Air75AgentBridge/Backups/`，项目清理不会触碰该目录。

## 发行验证

- Universal（arm64 + x86_64）固定签名 App 构建通过，版本 `0.14.0 (54)`，designated requirement 保持 bundle ID `com.nagentbridge.mac` 与固定证书指纹。
- 新 App 已安装；首次启动和完整退出后的第二次冷启动都在约四秒内得到 `LightingAvailable=1`、`LightingConnection=usbCable`、`HIDManagerOpenResult=0`，输入监控、辅助功能和连续 F13–F24 映射保持有效。
- Development DMG CRC、只读挂载、签名、Air75V3 Bundle 资源与内容结构全部通过。SHA-256：`477a34f1d9a411bd91f6f25aa27d4382aba8bdc0bd986d1f6538744d8a911e47`。
- 本机只有 Command Line Tools，缺少完整 Xcode 的 XCTest 平台，因此 `swift test` 明确返回 `XCTest not available`；不依赖 XCTest 的发行版 `Air75CoreSelfTest --software-only` 已全部通过。
- GitHub 源码提交与新的 `v0.14.0-development` Release 待发布；旧 Release 不覆盖。

## 验证命令

```bash
swift build --disable-sandbox --product Air75CoreSelfTest
.build/debug/Air75CoreSelfTest --software-only
.build/release/Air75ProtocolProbe --hardware-validate
./scripts/verify-release.sh
```
