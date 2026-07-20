# Keymap

| 实体键 / HID Usage | 默认动作 |
|---|---|---|
| F1–F6 (`0x3A–0x3F`) | Agent 1–6 |
| F7 (`0x40`) | Quick Action / Skill |
| F8 (`0x41`) | Approve |
| F9 (`0x42`) | Decline |
| F10 (`0x43`) | New Chat |
| F11 (`0x44`) | Push to Talk |
| F12 (`0x45`) | Send |

以上是项目默认映射，不是 OpenAI 官方默认。“一键启用”会先备份完整 1568-byte 键位表，再把实体 F1–F12 在 Mac/Windows 基础层中映射为内部 F13–F24；旋钮左转、按压、右转映射为 Scroll Lock、Pause、Print Screen。写入后读取完整键位表逐字节验证，失败自动恢复。

0.8.0 起，每个 Codex 动作可以在“按键”页学习到数字、字母、F 区或导航键。自定义普通键只改变软件输入绑定，不盲写未知键盘矩阵位置；Codex 控制开启时，CGEvent session tap 消费对应 macOS 键盘事件，防止原字符同时输入。停止控制时必须连接 USB-C：应用从可验证的原始备份恢复完整键位表并回读成功后才关闭控制。自定义绑定在专用层安装与原始层恢复之间保留。

0.9.5 起，按键学习会识别 IOHID 键盘数组报告：`usage 0xFFFFFFFF` 只是数组占位值，绝不是可保存的实体键。学习器只从报告 value 提取受支持的真实 Usage，并拒绝 0/1 等占位值；schema 7 会自动修复旧配置中的无效绑定，运行时映射也会忽略它。
