# Privacy

- IOHIDManager 仅将已识别 Air75 V3 加入运行时集合。
- 非校准模式只发布已映射的 F1–F12/用户学习 Usage、候选旋钮 Consumer Usage 与 vendor-defined Usage。
- 为在 USB-C 与 2.4G 同时枚举时选择正确灯光通道，HID 层会报告“哪个已验证接口刚刚活动”；该信号不包含按键 Usage、value 或文字内容，也不会写入历史记录。
- 灯光写入只匹配已验证的 Air75 V3 USB VID `0x19F5` / PID `0x1028` 或官方 U1 2.4G VID `0x19F5` / PID `0x2620` 的 usage `1:0` 配置接口，不会向未知键盘发送 NuPhyIO Report。
- 不存储普通键盘文本、密码或其他键盘事件，不上传原始 HID Report。
- 校准事件只在内存保留最近 120 条，退出即消失。
- F11 只触发 Codex Desktop 自带听写；N Agent Bridge 不申请麦克风权限、不录音，也不读取听写结果。
- Codex 复用官方 CLI 登录；应用不读取或复制 token。Profile/备份不含 API Key、聊天内容或源码。
- 高风险批准由用户按键或点击明确触发。
