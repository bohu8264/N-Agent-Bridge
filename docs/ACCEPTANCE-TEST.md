# Acceptance Test

## 自动化

- `swift build --product Air75AgentBridge`
- `swift build --product Air75HIDInspector`
- `swift test`
- `scripts/verify-release.sh`

## USB

- 识别 VID/PID/序列号与全部接口；不识别名称相同但 VID/PID 不符的 USB 键盘。
- 一键启用先创建可读回备份；UI 显示真实 Mapping Mode。
- Inspector 逐项校准 F-row、方向键和旋钮；不写未知 Report。

## 纯 Bluetooth（必须拔掉 USB）

- 关联同一设备且不重复；不接管内置/其他键盘。
- Agent 1–6、6 个 Command、方向工作流、旋钮左/右/按压/长按全部通过。
- 创建/切换/发送/停止/继续/批准/拒绝反映真实 Codex 状态。
- 按住说话与双击持续录音转写到 Composer，不自动发送。
- 睡眠、键盘休眠、Mac 重启后自动恢复。
- 蓝牙 RGB 各状态实测；若协议不可用则验收失败，不能以浮层替代。

## 安装

- 干净 Mac 无 Xcode/Homebrew/Node；拖入 Applications 后运行。
- 权限说明清楚，完全退出后无监听/残留进程。
- Developer ID、Hardened Runtime、Notarization、Stapling、DMG SHA-256 均验证通过。
