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

0.11.0 起，绑定同时保存可选的 `signalLightIndex`。Air75 V3 ANSI 的索引来自 NuPhyIO 官方可见键顺序，并应用 `skipPos=14 / skipSize=3` 去除三个隐藏旋钮项；F1 为 1，数字 1 为 16。Kick75 也按官方数组排除源位置 14–16 的三个隐藏旋钮项；F1 为 1、Q 为 30。Node100 LP ANSI 直接使用官方 108 键顺序（D1 同样返回 108），F1 为 1、F12 为 12、数字 1 为 25、Q 为 44、Space 为 100、Right 为 105。Agent 1–6 学到新实体键时，灯位随 Usage 实时解析；两个动作交换实体键时灯位也交换。没有已验证 `signalLightLayoutID` 的型号只保存 Usage，不执行 D8 灯位写入。

Node100 LP ANSI 的键位表为 8 层、每层 119 项、共 1904 bytes。只修改 Mac/Windows 基础层的 F1–F12，以及触控条静音/减音量/加音量入口；触控条左滑、双击、右滑分别产生 Scroll Lock、Pause、Print Screen。Fn 层和其他字节必须保持不变，写后要求完整 1904-byte 回读。

Agent 1–6 的目标由最近、置顶、优先、自定义四种来源策略选出，最终都保存/使用线程 ID。实体键不会再通过 Command+1…6 猜测侧栏位置，而是打开 `codex://threads/<thread-id>`。
