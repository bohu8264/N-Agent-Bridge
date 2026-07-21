# External Blockers

这里只记录普通应用代码无法自行消除的外部限制。

## 1. macOS 必须由用户授予两项权限

输入监控用于读取 Air75 V3 的专用控制键，辅助功能用于把动作发送到当前 Codex 窗口。macOS 不允许应用或安装包静默授权，因此首次安装仍需用户各确认一次；固定 bundle ID、固定签名与原位升级用于让系统在后续版本中继承授权。

## 2. 免费 Development 包没有 Apple 公证

当前钥匙串只有 `N Agent Bridge Local Signing`，没有 Developer ID Application 证书和 notarytool 凭据。Development DMG 可供已知来源测试，但朋友首次打开可能需要在“系统设置 → 隐私与安全性”点“仍要打开”。不要关闭 Gatekeeper，也不要运行 `spctl --master-disable`。

## 3. 蓝牙没有可用的 S4 配置通道

Air75 V3 蓝牙 HID 可发送普通按键，但当前固件没有暴露 64-byte S4 Vendor 通道，因此板载键位安装和实时 D8 灯光写入只支持 USB-C，以及经过验证的 U1 2.4G 配置路由。软件不能凭空补出固件没有提供的 BLE 特征。

## 4. Codex Desktop 状态不是公开稳定 API

应用以只读方式组合 Codex app-server 的任务 ID/名称、当前窗口辅助功能语义和本地状态事件。后台未渲染的第三方 MCP 确认卡没有公开共享事件流，Codex 更新内部命令或存储结构后可能需要兼容更新。应用遇到未知格式会回退为空闲，不把不确定状态错误写成橙灯或蓝灯。

## 5. 正常字符键的系统级拦截无法精确区分另一把键盘

macOS 的非 root CGEvent session tap 不提供可靠的物理键盘来源。用户把 Agent 动作分配到 Q、数字键等普通键后，Codex 控制开启期间同一虚拟键会被消费；停止控制或退出应用后立即恢复。精确区分多把键盘需要 DriverKit/HIDDriver，不在当前免费应用范围内。
