# Privacy

- IOHIDManager 仅将设备 Profile 精确识别的受支持 NuPhy 型号加入运行时集合。
- 非校准模式只发布已映射的 F1–F12/用户学习 Usage、候选旋钮 Consumer Usage 与 vendor-defined Usage。
- 为在 USB-C 与 2.4G 同时枚举时选择正确灯光通道，HID 层会报告“哪个已验证接口刚刚活动”；该信号不包含按键 Usage、value 或文字内容，也不会写入历史记录。
- 灯光写入当前只授权已验证的 Air75 V3 USB VID `0x19F5` / PID `0x1028` 或官方 U1 2.4G VID `0x19F5` / PID `0x2620` 的 usage `1:0` 配置接口；其他已识别型号仍停留在软件模式，不会收到 NuPhyIO 写入 Report。
- 不存储普通键盘文本、密码或其他键盘事件，不上传原始 HID Report。
- 校准事件只在内存保留最近 120 条，退出即消失。
- F11 只触发 Codex Desktop 自带听写；N Agent Bridge 不申请麦克风权限、不录音，也不读取听写结果。
- Codex 复用官方 CLI 登录；应用不读取或复制 token。Profile/备份不含 API Key、聊天内容或源码。
- 为实现最近、置顶、优先和自定义 Agent 分配，应用只读本机 Codex 索引中的线程 ID、兼容标题、项目目录、更新时间，以及全局状态中的未读/置顶线程 ID、项目名称/顺序和线程项目归属。任务最终显示名来自只读 app-server `thread/list` 的 `Thread.name`；同一响应中的 `preview` 会立即丢弃，不会返回到产品状态、写日志或持久化。rollout 只读取尾部事件名称与时间戳，不会解析、记录或上传提示词与回答正文。
- 为识别 rollout 不记录的 Codex 可见确认卡，应用通过已获用户允许的辅助功能只读取 `AXButton` 的标题/说明，并从 Codex Desktop 日志只解析 `active` 和 `conversationId`。不会读取 `AXStaticText`、输入框内容、聊天正文或确认卡问题文本；只在内存保留当前等待线程 ID。
- 高风险批准由用户按键或点击明确触发。
