# Release

## 0.13.2 Development Build

- 版本：`0.13.2 (50)`。
- 自动迁移朋友电脑上出现的 `F13 / F15 / Tab / F16…F24` 异常默认序列为连续 F13–F24；整组精确匹配，不覆盖真正的用户自定义键。
- 首次配置与灯光读取改为串行事务，避免键位写入、Codex 中继安装和指示灯模式互相抢占同一 HID 通道；配置完成前界面显示“正在配置”。
- Debug App、software-only SelfTest、Universal（arm64 + x86_64）App、固定签名、Bundle 资源与 DMG CRC/结构验证：通过。
- Development DMG SHA-256：`83b95375a3dbc8cc6643dff976178a9315194353b39d49cca23b9d9957faeb28`。

## 0.13.1 Development Build

- 版本：`0.13.1 (49)`。
- USB-C 启用不再只相信旧的“已安装”记录；每次都会读取实体键位、自动修复 F1–F12 为专用 F13–F24，并完成完整回读，避免 Codex 动作与 macOS 原生功能同时触发。
- Air75 V3 与 Node100 LP ANSI 首次配置会一次性选择“指示灯”背光；以后不覆盖用户手动选择的灯效。
- 未读任务不再绕过推理状态过期；30 分钟没有新推理或工具事件会回到空闲，避免没有任务时长期误亮蓝灯。
- 包含 Node100 LP ANSI 完整实机适配及此前 Kick75 的安全灯光、休眠和自定义键位状态灯修复。
- Debug App、software-only SelfTest、Universal（arm64 + x86_64）App、固定签名、DMG CRC/结构验证和 0.13.1 (49) 原位安装：通过；最终复核时无键盘在线，USB-C 实写需在下次接入时验收。
- Development DMG SHA-256：`5971087e36852805866b8f3a2ab0a38d9e68cb0162eb7425993c82123d7bc2c4`。

## 0.11.7 Development Build

- 版本：`0.11.7 (34)`。
- 灯光页移除普通背光与普通侧灯的亮度滑块和百分比，保留灯效、常亮颜色、休眠时间与 Codex 六任务状态灯。
- 删除界面层亮度临时状态及延迟 HID 写入任务；底层协议字段仍保留，切换灯效不会主动改变键盘现有亮度。
- Debug App、software-only SelfTest、Universal（arm64 + x86_64）App、固定签名、DMG CRC/结构验证和 0.11.7 (34) 原位安装：通过。
- Development DMG SHA-256：`bf31a20a7ab6c4a4ff42a75c07a0196414bfc08009aaf0321186ed0e4db0ec15`。

## 0.11.6 Development Build

- 版本：`0.11.6 (33)`。
- 修复普通任务没有批准卡时偶发误亮橙灯：输入框常驻“请求批准 / Request approval”只表示发送模式，不再当作正在等待批准。
- 可见确认卡改为在同一局部辅助功能子树中匹配真正的肯定与否定操作，防止跨页面把无关按钮拼成确认状态；真实安装/批准卡仍保持橙灯。
- Debug App、software-only SelfTest、Universal（arm64 + x86_64）App、固定签名、DMG CRC/结构验证和 0.11.6 (33) 原位安装：通过。
- Development DMG SHA-256：`f2d392b589d798f51591d58de62166a14307f7e1d4f162b0f6bcf86ef055bee7`。

## 0.11.5 Development Build

- 版本：`0.11.5 (32)`。
- 自定义分配与六个 Agent 槽位改用 Codex app-server `thread/list` 的正式 `Thread.name`；不再把 `preview`（首条输入）、陈旧 SQLite `title` 或不完整的 `thread-descriptions-v1` 当作最终任务名。
- 只读标题观察器每两秒同步一次，主任务、历史任务及用户改名无需重启即可更新；只保留内存中的 thread ID/名称，不保存预览或正文。
- Debug App、software-only SelfTest、真实 app-server 标题验证、Universal（arm64 + x86_64）App、固定签名、DMG CRC/结构验证和 0.11.5 (32) 原位安装：通过。
- Development DMG SHA-256：`ed5405920788f1883d85387eabbaee1312debe7788cf1f4feed4db14c9a944b7`。

## 0.11.4 Development Build

- 版本：`0.11.4 (31)`。
- 自定义分配的任务名改为 Codex 左侧栏使用的 `thread-descriptions-v1`，不再把 SQLite 中空白、陈旧或过长的 `threads.title` 当作最终名称。
- Codex 更新任务名称后，项目菜单、当前选择与六个 Agent 槽位会在下一次状态轮询中同步；SQLite 标题仅作为兼容旧版本的兜底。
- Debug build、新增标题同步测试、Universal（arm64 + x86_64）App、固定签名、DMG CRC/结构验证、六型号资源验证与 0.11.4 (31) 原位安装：通过。
- Development DMG SHA-256：`ceefc1dcdebdbe5f02d4599829ff636b708ff83253b3073768793fe058e3f906`。
- 已知限制：该版本把不完整的 `thread-descriptions-v1` 误认为最终标题来源；主任务可能继续显示旧首条输入，0.11.5 已修复。

## 0.11.3 Development Build

- 版本：`0.11.3 (30)`。
- 修复 Codex 的应用/插件安装卡、MCP 审批卡没有触发橙色“需要确认”状态的问题。
- 确认卡只读取按钮语义，并以 Codex Desktop 活动 `conversationId` 绑定精确任务；不读取或保存聊天正文，处理后自动恢复原任务状态。
- 检测使用轻量焦点快路径和低频完整校验，普通“搜索、插件、新建任务”等按钮不会误触发。
- Debug build、72 项 software-only SelfTest、Universal（arm64 + x86_64）App、固定签名、DMG CRC/结构验证与 0.11.3 (30) 原位安装：通过。
- Development DMG SHA-256：`6970953549389ab1b5b7ca85e7aee5e7f9719aaf4c11788c7a38f96deb9c8402`。

## 0.11.2 Development Build

- 版本：`0.11.2 (29)`。
- 四种 Agent 来源模式与 Codex Micro 官方定义保持一致。
- 自定义分配改为读取 Codex 左侧栏的项目名称、顺序和对话归属，以“项目 → 对话”二级菜单选择稳定对话 ID；长文本不再铺满一个扁平菜单。
- 状态解析继续限制在最近 50 个及精确置顶/自定义 ID，轻量选择目录支持最多 500 个未归档用户对话；历史已删除项目不再污染菜单，无法匹配当前项目的旧对话统一归入“其他对话”。
- Debug build、66 项 software-only SelfTest、当前 Codex 项目菜单目视验收、Universal App、固定本机签名和 DMG 完整性验证：通过。
- Development DMG SHA-256：`ec7fe6b360cf12474705643c8fe50f25fe48f53c112299c801a1bd47c03f35de`。

## 0.11.1 Development Build

- 版本：`0.11.1 (28)`。
- 修复长任务文件增长后 `turn_started` 离开读取窗口，运行任务被误判为空闲白灯的问题。
- 活跃状态加入 90 秒 D8 保活；Mac/键盘休眠唤醒后主动补发六灯状态。
- Debug build、66 项 software-only SelfTest、真实 Codex 长任务状态演练、Universal App、固定本机签名和 DMG 完整性验证：通过。
- Development DMG SHA-256：`78fcb58be4d231c68451e53dc20839894c14786ac5e3a00325bd53baa2964f4b`。

## 0.11.0 Development Build

- 版本：`0.11.0 (27)`。
- Agent 1–6 改为稳定线程 ID，提供最近、Codex 置顶、优先和自定义四种来源模式；完成任务或侧栏重排不再改变自定义绑定的身份。
- Air75 V3 的 Agent 动作可学习到其他受支持实体键，D8 状态灯会跟随绑定后的实际灯位；空槽熄灭，已分配空闲槽为白色。
- 普通侧灯保留独立灯效、亮度与常亮颜色，不再承担 Codex 聚合状态。
- 新增 Air65 V3、Air100 V3、Kick75、Node75、Node100 安全识别与软件按键模式；未完成各型号实机验证前，不开放其 Vendor HID 写入。
- Universal `arm64 + x86_64`、64 项 software-only SelfTest、六型号 App Bundle Resource Test、固定本机签名和 DMG 完整性验证：通过。
- Development DMG SHA-256：`e9d4cfc8bb68e922832331ad0e6933901c1bbf75d03d36fb769b6706e866ad22`。
- 该 DMG 使用本地自签名证书，适合已知来源测试，不是 Apple 公证的正式发行包。

## 0.10.1 Development Build

- 版本：`0.10.1 (26)`。
- 新固件 `0xD8 SetSignalLights` 已完成 F1–F6 六任务独立状态灯适配；实机索引修正为 `1–6`，索引 `0`（Esc）会被清除。
- Codex 不再接管侧灯；schema 8 只恢复一次官方侧灯设置，之后任务灯和侧灯互不影响。
- Universal `arm64 + x86_64`、software-only SelfTest、App Bundle Resource Test、固定本机签名和 DMG 完整性验证：通过。
- GitHub Development DMG SHA-256：`7dbaaa7fdb8de43f61d970c5fde3330a9b1962f112ded49e57f4ee0d12525ed5`。
- 该 DMG 使用本地自签名证书，适合已知来源测试，不是 Apple 公证的正式发行包。

## 0.9.9 Local Development Build

- 版本：`0.9.9 (24)`。
- 修复外发 App 因 SwiftPM `Bundle.module` 只查 App 根目录/开发机绝对 `.build` 路径而启动崩溃；设备 Profile 现在从标准 `Contents/Resources` 加载，资源缺失时安全回退，不再 fatalError。
- Release 验证新增 Profile JSON、绝对构建路径与资源断言检查；最终 DMG 只读挂载后的 App Bundle Resource Test 通过。
- Universal `arm64 + x86_64`、50 项 software-only SelfTest、固定本机签名、DMG CRC/结构校验：通过。
- DMG SHA-256：`9b3587842533a07c69e19faa2083171d40b405cd798d5a186d1f0201de29e5a6`。

## Public Release Pipeline（尚未发布）

- 已实现 Universal（arm64 + x86_64）构建、Developer ID 强制签名、安全时间戳、Hardened Runtime、DMG 签名、Apple Notarization、Stapling、Gatekeeper 与最终散列校验。
- 未使用的音频输入和网络 entitlement 已移除；当前 Universal 本机验证包不再出现无效 entitlement 警告。
- 本机自签验证文件为 `dist/NAgentBridge-0.9.9-Development.dmg`，当前 SHA-256：`9b3587842533a07c69e19faa2083171d40b405cd798d5a186d1f0201de29e5a6`，只用于已知来源的朋友测试。
- 当前未安装 Developer ID Application，也未建立 notarytool profile，因此尚未生成正式 `dist/NAgentBridge.dmg`。

## 0.9.8 Local Development Build

- 版本：`0.9.8 (23)`
- 灯光就绪只依赖 D5/D6；U1 不转发 A1/F3 管理命令时不再误判整个 RGB 通道失败。
- 2.4G 实机已完成推理蓝色侧灯写入、ACK 与回读，诊断为 `twoPointFourGHzReceiver / available=1`。
- 灯光保持时间明确保留为 USB-C 管理设置；新增本机灯光连接、状态和错误诊断。
- software-only SelfTest、严格 codesign、Designated Requirement、`hdiutil verify` 与原位安装：通过。
- DMG SHA-256：`e7cc7170252354cafc92af86331bbd5c5c9421a3375b4202d619182e30512c54`

## 0.9.7 Local Development Build

- 版本：`0.9.7 (22)`
- 修复 USB-C 与 U1 接收器同时枚举时固定有线优先导致 2.4G 侧灯不同步。
- 灯光路由由最近真实 HID 输入接口和成功的 S4 回读共同确认，失败只在两个白名单接口之间回退。
- U1 `19F5:2620` 的 usage `1:0`、64/64 配置接口已在用户实机枚举；最终目视验收待安装后完成。
- software-only SelfTest、严格 codesign、Designated Requirement、`hdiutil verify` 与原位安装：通过。
- DMG SHA-256：`edd761a68f17e6e67e9bf34e83260a964f2bc03b4dbd60f2481233570e3db3e1`

## 0.9.6 Local Development Build

- 版本：`0.9.6 (20)`
- 正式区分 USB-C 与 U1 2.4G 灯光配置通道；2.4G 使用同一套已验证 S4 帧实时同步 Codex 状态侧灯。
- USB-C/2.4G 切换自动重新握手；无线休眠后第一下按键自动重试并补发当前状态色。
- 灯光页显示真实通道。当前蓝牙固件没有 S4/Vendor 配置接口，因此只保留按键控制，侧灯 RGB 不做未知写入。
- software-only SelfTest、严格 codesign、Designated Requirement、`hdiutil verify` 与原位安装：通过；2.4G 实机验收等待接收器插入。
- DMG SHA-256：`9dc3b030fb2962616f85c3749d5ac012590470dcc5deec7bda39a983fe31cedc`

## 0.9.5 Local Development Build

- 版本：`0.9.5 (19)`
- 修复 F1 被误学习为 HID 键盘数组占位值 `P07/UFFFFFFFF` 后，任意普通文字输入都会跳转到 Codex 任务 1 的问题。
- schema 7 启动迁移只修复无效绑定；本机 F1 已恢复为 F13（usage `0x68`），其余绑定保持原样，并保留迁移前配置备份。
- 学习、HID 事件发布、动作映射和事件拦截四层均拒绝无效 Usage；SelfTest 覆盖旧配置迁移与运行时防护。
- software-only SelfTest、严格 codesign、Designated Requirement、`hdiutil verify` 与原位安装：通过。
- DMG SHA-256：`7de4efec9fb75a16efefa51a1b50ee4df68bb995a39add5159b8f8eec6f29335`

## 0.9.4 Local Development Build

- 版本：`0.9.4 (18)`
- 修复背光和普通侧灯滑块偶发只改变界面、不向键盘提交的问题；不再依赖缺失的滑块结束回调。
- 停止拖动 250ms 后防抖提交最后一个值，并沿用写前备份、ACK 与完整回读流程。
- 通过已安装应用真实 UI 完成背光 100% → 20% → 100%，两个 Profile 均回读验证，最终恢复原亮度。
- software-only SelfTest、严格 codesign、Designated Requirement、`hdiutil verify` 与原位安装：通过。
- DMG SHA-256：`d63082a3b11c905b44fbccde04ba99b7dd06f9bf3070df1fa035186a42e5f41d`

## 0.9.3 Local Development Build

- 版本：`0.9.3 (17)`
- “灯光 → 普通背光”新增键盘灯光保持时间，可选 3、6、10、20、30、60 分钟或“始终亮着”。
- 使用官方 S4 `0xF3/0xF5` 自动休眠协议；写前备份、保留深度休眠字段，并校验 ACK 与延时回读，失败自动恢复。
- Air75 V3 实机原值 `01 06 18`；通过已安装 App UI 完成 6 → 10 → 6 分钟端到端验证，最终保持原设置。
- 休眠写入能力纳入型号 Profile 与驱动白名单，未验证型号默认关闭。
- software-only/完整实机 SelfTest、严格 codesign、Designated Requirement、`hdiutil verify` 与原位安装：通过。
- DMG SHA-256：`c9df3d2ea4401619209d35898ebaef7aa77177a5f00244cd7084a752caa0fe7a`

## 0.9.2 Local Development Build

- 版本：`0.9.2 (16)`
- 概览页左右信息卡使用相同列宽和精确 210pt 内容高度，标题、首行、外边距与底边全部对齐。
- 重新校准“Codex 侧灯”卡片内当前状态、六任务状态条与五色图例的垂直节奏。
- 从 0.9.1 原位升级安装；旧版已移入废纸篓，可恢复。
- 37 项 `Air75CoreSelfTest --software-only`、严格 codesign、Designated Requirement 与 `hdiutil verify`：通过。
- DMG SHA-256：`519e9652bf00e22efec2ac94db25002b3cd8077cdd2bbcfb27def15bc6e568be`

## 0.9.1 Local Development Build

- 版本：`0.9.1 (15)`
- F11 卡片与其他 11 个按键完全同级；移除突出的听写测试按钮、蓝色“Codex 原生听写”和设置页重复测试入口。
- 概览、按键、灯光和设置改为轻量 macOS 原生分组风格，删除重复内容、阴影、十六进制颜色和侧栏品牌重复展示。
- 删除应用内未使用的录音/语音识别实现、AVFoundation/Speech 链接及麦克风/语音识别 Info.plist 权限；F11 继续定向调用 Codex 自带听写。
- 从 0.9.0 真实替换升级后：输入监控 `1`、辅助功能 `1`、HID manager open result `0`，权限保持。
- 0.6.1、0.8.0 和被替换的 0.9.0 应用均已移入废纸篓，可恢复；用户配置与硬件原始备份未删除。
- `Air75CoreSelfTest --software-only`、严格 codesign、Designated Requirement 与 `hdiutil verify`：通过。
- DMG SHA-256：`5dcfc4f656b12d7ee6f27520e21ce61cbe39683e6f299254d95f2d46b060ff32`

## 0.9.0 Local Development Build

- 版本：`0.9.0 (14)`
- 产品名与固定 Bundle ID：`N Agent Bridge` / `com.nagentbridge.mac`。
- 固定本机签名身份：`N Agent Bridge Local Signing`，SHA-1 `C6633C857A05DF981A9334F9220E4178866B2368`。
- 不同构建号实测 CDHash 会变化，但 Designated Requirement 均为 `identifier "com.nagentbridge.mac" and certificate root = H"c663…2368"`，因此以后本机更新保持同一个 TCC 权限身份。
- 新增多型号 Profile/驱动注册表与 schema 6 迁移；未注册的硬件写入能力默认关闭，备份/恢复按型号隔离。
- Debug build 与 `Air75CoreSelfTest --software-only`：通过。
- `codesign --verify --deep --strict`：通过。
- 应用：`dist/N Agent Bridge.app`；DMG：`dist/NAgentBridge.dmg`。
- DMG SHA-256：`ffbd2b17096d176d9a1904672c3c1f7f8b5cbb59f9ecde0048a60ffa73d1d46d`；`hdiutil verify`：通过。
- 已安装 `/Applications/N Agent Bridge.app`；0.8.0 已保留为 `/Applications/Air75AgentBridge-0.8.0-before-n-agent.app`。
- 最后一次 TCC 迁移授权完成；重启后输入监控与辅助功能均为 `1`，HID manager open result 为 `0`。
- 本机自签包未经过 Apple 公证，只用于本机安装与持续升级；公开分发仍需 Developer ID 与 Notarization。

## 0.8.0 Development Build

- 版本：`0.8.0 (13)`
- 五种 Codex 侧灯状态颜色可分别自定义并持久保存。
- 12 个 Codex 动作可学习到数字、字母、F 区与导航键；控制开启时消费原字符，停止后恢复普通输入。
- “停止控制”升级为 USB-C 原始键位恢复事务，跳过已经包含 Bridge Profile 的错误历史备份，完整回读成功后才允许拔线。
- 自定义绑定在专用层安装/恢复之间保持；按键学习在 keyUp 后提交，避免卡键。
- `swift build --product Air75AgentBridge`：通过。
- `Air75CoreSelfTest --software-only`：通过；硬件通道测试按设计跳过，避免和运行中的 App 争用。
- `codesign --verify --deep --strict`：通过。
- `hdiutil verify`：通过。
- DMG SHA-256：`bf27c6a96a1b7aefb5ae38acc24b5e82a94c2abd6ea621e58fa76f18ebd39479`
- `/Applications/Air75AgentBridge.app`：已安装并核对为 `0.8.0 (13)`；旧版保存在 `/Applications/Air75AgentBridge-0.6.1-before-0.8.0.app`。
- 当前仍是 ad-hoc Development Build。升级后的 CDHash 已变化，输入监控与辅助功能需要用户在系统设置中重新确认；正式公开发行仍需 Developer ID 与 Apple 公证。

## 0.6.1 Development Build

- 版本：`0.6.1 (11)`
- 移除 Logo 主体外的黑色方形画布，保留金属 N 与深色玻璃圆角主体，四角使用真实透明通道。
- Finder、Dock、应用内品牌区域与 DMG 中的应用包均使用新的透明 `AppIcon.icns`。
- `/Applications/Air75AgentBridge.app`：已安装并核对为 `0.6.1 (11)`。
- 升级前 0.6.0 备份：`/Applications/Air75AgentBridge-0.6.0-before-transparent-logo.app`。
- DMG SHA-256：`735cb7389f965bcb2b3956b739356cfa9a5c33ba7b97bb0217093ec2c3c5bc65`
- `codesign --verify --deep --strict`：通过
- `hdiutil verify`：通过
- 当前仍为 ad-hoc Development Build，权限在二进制更新后需要重新授权；正式公开分发仍需 Developer ID 与 Apple 公证。

## 0.6.0 Development Build

- 版本：`0.6.0 (10)`
- 使用用户提供的新 N 字 Logo，并生成 `AppIcon.icns`；Finder、Dock、应用包与应用内品牌区域使用同一视觉资产。
- 主界面重做为 `概览`、`按键`、`灯光`、`设置` 四页，减少工程化字段和重复状态说明。
- 旋钮与 Codex 原生听写合并到“按键”页；输入监控、辅助功能、Codex 快捷键和登录启动整合到“设置”页。
- “概览”聚合 Air75 连接、Codex 控制、权限和顶部任务侧灯状态，并只在需要时显示修复或重启提示。
- “灯光”保留普通背光、普通侧灯和 Codex 五状态侧灯；状态侧灯仍只写侧灯，不改变背光。
- `/Applications/Air75AgentBridge.app`：已安装并核对为 `0.6.0 (10)`。
- 升级前 0.5.0 备份：`/Applications/Air75AgentBridge-0.5.0-before-redesign.app`。
- DMG SHA-256：`5fe8fe8703482ebbaddfaeebb35732876f2792764f1c3341aaff884cef998631`
- `codesign --verify --deep --strict`：通过
- `hdiutil verify`：通过
- 当前仍为 ad-hoc Development Build，未使用 Developer ID、Hardened Runtime 公证流程和 Stapling，不得宣称为 Apple 已公证的公开发行版。

## 0.5.0 Development Build

- 版本：`0.5.0 (9)`
- F11 改为定向转发 Codex 原生 `Control-Shift-D`，并保留物理按下/松开时长。
- 新增 Codex 顶部任务五状态侧灯；任务内容不被读取，只解析本地 rollout 的事件名与时间。
- 白、蓝、绿、橙、红五色已在连接的 Air75 V3 上逐色写入并回读验证；每次验证均确认背光 0–8 字节完全不变，结束后恢复原灯光。
- 配置 schema 4 会自动启用侧灯状态模式并关闭按键成功浮层。
- DMG SHA-256：`cb17aadc06ff1274bd993a30008b3eb24fb4e1ae3f1bec5b2224f78f1677ab9f`
- `codesign --verify --deep --strict`：通过
- `hdiutil verify`：通过
- `/Applications/Air75AgentBridge.app`：已安装并验证为 `0.5.0 (9)`；0.4.3 保留为可恢复备份。

## 0.4.3 Development Build

运行 `scripts/build-release.sh` 生成 `dist/Air75AgentBridge.app`，运行 `scripts/create-dmg.sh` 生成 DMG。当前制品使用 ad-hoc 签名，适合本机验收，不等同于 Developer ID 签名和 Apple 公证的公开发行版。

当前已验证制品：

- 版本：`0.4.3 (8)`
- DMG SHA-256：`6589b0dfdc0ac45d493b784d775ee9824972cbb7506665840a6c433515bab1af`
- `codesign --verify --deep --strict`：通过
- `hdiutil verify`：通过
- 实机 1568-byte 键位读取、板载 Bridge Profile 与完整回读：通过，当前差异 0 bytes
- 物理 F1–F12 → 内部 F13–F24：通过
- 旋钮左转/按压/右转 → Scroll Lock/Pause/Print Screen：通过
- Bridge → 当前 Codex 进程的合成事件验证：模型选择器和原生听写启动/停止通过
- Codex Desktop 中继快捷键安装、旧版直接 F 键迁移与二次校验：通过
- F13–F24 session event tap 编译、签名与启动诊断：通过；物理亮度不变待授权后最终验收
- F11 明确绑定 `composer.startDictation`、旧 AX 停止按钮误判移除：通过
- 实体控制成功反馈浮层：已取消
- 官方 NuPhyIO 灯光状态读取与侧灯 0–255 亮度换算：通过
- `/Applications` 安装与 LaunchServices 启动：通过
- 新版未启动独立 Codex app-server：通过

首次安装必须由用户允许输入监控和辅助功能，然后重启 Bridge；首次安装或修复快捷键后，还必须完整退出并重新打开 Codex Desktop 一次。物理 Air75 端到端验收需要在这两项权限授权后完成。

## 正式公开 Release

1. 安装完整 Xcode 与匹配的 macOS SDK。
2. 设置 `AIR75_SIGNING_IDENTITY="Developer ID Application: …"`。
3. 运行 `scripts/build-release.sh` 与 `scripts/sign-release.sh`。
4. 使用 `xcrun notarytool store-credentials` 创建 Keychain profile，并设置 `AIR75_NOTARY_PROFILE`。
5. 运行 `scripts/create-dmg.sh`、`scripts/notarize-release.sh`、`scripts/verify-release.sh`。
6. 在干净 Mac 上验证拖拽安装、Codex 重启、USB 首次配置、F-row、旋钮、纯蓝牙运行、休眠恢复与完全退出。

正式发布不得跳过 Hardened Runtime、Notarization、Stapling 和蓝牙强制验收。
