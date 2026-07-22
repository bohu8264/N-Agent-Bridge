# Progress

更新时间：2026-07-22 CST

## 0.14.1：橙色确认灯误判修复

- Codex 辅助功能扫描现在只读取当前焦点窗口；`AXVisibleChildren` 明确为空时视为隐藏，不再遍历 Electron 保留的已关闭卡片和离屏窗口。
- 单个“安装 / 允许 / 批准”按钮不再足以点亮橙灯。只有同一个可见控件组同时出现权限类肯定动作与拒绝动作，才判定为正在等待用户确认；普通“确认 / 取消”界面不会误触发。
- rollout 状态解析改为只接受明确的 `request_user_input`、approval request 或 permission request 事件；带 `approval` 字样的普通元数据不再误判，工具输出和已完成/拒绝的确认结果会立即清除等待状态。
- 新增中文、英文、隐藏卡片、单按钮、普通确认框、命名工具输出与无关 approval 元数据回归检查。`Air75CoreSelfTest --software-only` 全部通过，Universal App 完整编译通过。
- 本机已安装 `0.14.1 (55)` 并冷启动验证：Air75 V3 识别正常、`LightingAvailable=1`，无确认卡片时 `CodexVisibleConfirmationWaiting=0`，延时复查没有重新变橙。
- 本地 Development DMG：`dist/NAgentBridge-0.14.1-Development.dmg`；CRC 有效，SHA-256：`83edbae8f6b88c101ab1f976314a0b4c26dc7ccc70f21d5a8aff8f9edb239fa3`。固定自签名证书未加入系统信任链，因此严格 `codesign --verify` 返回 `CSSMERR_TP_NOT_TRUSTED`；包内容、指定要求与双架构均正常。
- 源码已推送到公开仓库，`v0.14.1-development` Pre-release 已上传 Universal DMG 与 GitHub 自动生成的源码压缩包；0.14.0 保留且未覆盖。

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
