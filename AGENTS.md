# N Agent Bridge 开发入口

开始修改前依次阅读 `README.md`、`PROGRESS.md`、`BLOCKERS.md`。当前产品范围只包含 **NuPhy Air75 V3 ANSI**，不要恢复已删除的其他键盘 Profile 或复用未验证驱动。

## 当前基线

- 产品：N Agent Bridge `0.15.0 (57)`
- Bundle ID：`com.nagentbridge.mac`
- 固定本地签名：`N Agent Bridge Local Signing`
- 目标固件：Air75 V3 官方 `1.0.16.6`
- 有线身份：`19F5:1028`
- 官方 U1 接收器：`19F5:2620`
- Profile：`nuphy.air75-v3`
- macOS 13+，Swift 5.9+

## 不能破坏的硬件安全规则

1. 所有管理请求只匹配白名单 64-byte usage page/usage `1:0` 配置接口。
2. 每个逻辑事务先发送 `0xEE SetSecretKey`，会话 key 为 56-byte challenge 的 byte 20。
3. 解码必须同时兼容旧固件“路由头+payload 加密”和 1.0.16.6“路由头明文、payload 加密”。
4. S4 响应没有 transaction ID，键位、灯光、状态灯和休眠帧必须通过 `NuPhyHIDOperationCoordinator` 串行执行。
5. 写入前读取并持久备份；写入后要求 ACK、延时回读和严格验证；失败尝试恢复。
6. D5 读取 handle 0/1，但 D6 只写 macOS handle 0。1.0.16.6 会规范化 Windows handle 1 的未使用元数据，禁止修改它。
7. D8 写前用 D2 读取原色，写后 D2 精确回读；失败恢复。稀疏灯位按不超过 54-byte 的连续窗口读取。
8. 键位表必须恰好 1568 bytes。密文、未知矩阵、混合半写状态不得保存成原始备份。
   Air75 V3 官方 1.0.16.6 只允许第 8 层旋钮按下 p60 为空值 `0x0000`，安装时规范化为 `0x0048`；不得把空值白名单扩展到其他层或位置。
9. 禁止发送 `0xEF SetIapMode`、`0xF1 RestoreFactory` 或猜测的固件命令。
10. 不删除 `~/Library/Application Support/Air75AgentBridge/Backups`。

## 产品行为

- 首次 USB-C 配置把物理 F1–F12 改为 F13–F24，旋钮改为唯一专用事件，并完整回读。
- 每次 USB-C 重连都核对键盘真实键位；固件升级恢复原生层时要求重新配置。
- F1–F6 / 自定义 Agent 键使用 D8 显示五种状态；Esc=0，F1–F6=1–6，旧 Tab=30 只在不是当前绑定时清除。
- Agent 使用稳定 thread ID，支持最近、置顶、优先、自定义四种来源。
- 输入监控与辅助功能必须由用户本人授权，不能静默批准。
- Bluetooth 没有可验证的 S4 灯光通道，不得模拟支持。

## 验证命令

```sh
swift build --disable-sandbox --product Air75CoreSelfTest
.build/debug/Air75CoreSelfTest --software-only

# 真机验证前退出 N Agent Bridge 和 NuPhyIO
swift build --disable-sandbox -c release --product Air75ProtocolProbe
.build/release/Air75ProtocolProbe --hardware-validate
```

真机验证必须输出 D6 原值与临时值回读、D8 原值与临时值回读、B2 键位表及最终恢复全部 PASS。Probe 会先写持久备份。

发布使用 `scripts/build-release.sh`、`scripts/create-dmg.sh`、`scripts/verify-release.sh`。发布前还要运行 App Bundle 资源测试、固定签名检查、冷启动诊断与 DMG 只读挂载验证。

## 目录

- `Sources/Air75AgentBridgeCore/`：协议、HID、配置、状态与映射
- `Sources/Air75AgentBridgeApp/`：SwiftUI 与运行编排
- `Sources/Air75ProtocolProbe/`：受保护硬件验收
- `Sources/Air75CoreSelfTest/`：软件回归
- `Tests/`：XCTest（完整 Xcode 环境运行）
- `Distribution/`、`scripts/`：签名与发行
- `docs/`：协议、用户与架构文档

不要提交 `.build/`、`dist/`、硬件捕获、用户配置、备份、证书私钥或 API 凭据。
