# Progress

更新时间：2026-07-21 CST

## 0.11.5 已完成（使用 Codex 正式 Thread.name）

- 用户截图复核证明 0.11.4 仍把主任务显示成最初长输入；原因是 `thread-descriptions-v1` 只覆盖部分短描述，并不是所有 Codex 左侧任务名的最终来源。
- 根据当前 Codex app-server schema，`thread/list` 的 `Thread.name` 是“Optional user-facing thread title”，`preview` 则是首条用户消息。真实本机返回已验证：线程 `019f77d0-483a-7450-ab0e-b382c73c8738` 的 `name` 为“构建 Air75 Agent Bridge macOS 应用”，`preview` 是旧长输入。
- 新增只读 `CodexDesktopTitleObserver`：保持独立 app-server 连接，每两秒调用 `thread/list(useStateDbOnly: true)`；只转发 ID 和 `name`，立即丢弃且不记录 `preview`。主任务、历史任务和用户改名都使用相同字段实时同步。
- 标题优先级改为 app-server `Thread.name` → Codex 持久化短描述 → SQLite 兼容标题。项目层级仍由 Codex 全局状态提供，稳定绑定仍使用 thread ID。
- Debug App 编译和 software-only SelfTest 通过，新增 app-server `name`/`preview` 分离与标题优先级测试；安装后的 N Agent Bridge 已确认启动标题同步子进程。
- Universal（arm64 + x86_64）Release、固定签名、DMG CRC/结构验证及 0.11.5 (32) 原位安装通过。Development DMG：`dist/NAgentBridge-0.11.5-Development.dmg`；SHA-256：`ed5405920788f1883d85387eabbaee1312debe7788cf1f4feed4db14c9a944b7`。

## 0.11.4 已完成（任务名与 Codex 左侧栏实时一致）

- 定位项目名正确但任务名不同：项目来自 `.codex-global-state.json`，旧实现的任务名却取自 SQLite `threads.title`；新任务的该字段经常为空，旧任务也可能保留最初长输入，并不是 Codex 左侧栏最终显示名。
- 新增 `CodexSidebarTitleIndex`，只读取 Codex 全局状态的 `thread-descriptions-v1` 短名称；自定义分配、当前选择和六槽标题均以该值为权威来源，SQLite 标题只在缺失时兜底。
- 状态观察器原有的一秒轮询会同时比较标题字段，因此 Codex 自动生成或更新任务名称后，无需重启 N Agent Bridge 即可同步。
- Debug App 编译通过；新增三项软件测试通过：精确解析可见名称、左侧栏名称覆盖旧 SQLite 标题、缺失时安全兜底。
- Universal（arm64 + x86_64）Release、固定签名、DMG CRC/结构验证、六型号 App Bundle 资源验证及 0.11.4 (31) 原位安装均通过；升级后输入监控、辅助功能和 HID manager 仍正常。
- Development DMG：`dist/NAgentBridge-0.11.4-Development.dmg`；SHA-256：`ceefc1dcdebdbe5f02d4599829ff636b708ff83253b3073768793fe058e3f906`。
- 后续用户目视验收发现主任务仍未被 `thread-descriptions-v1` 覆盖；该版本的标题来源结论不完整，已由 0.11.5 的正式 `Thread.name` 链路取代。

## 0.11.3 已完成（Codex 确认卡实时橙灯）

- 定位“是否安装 Google Calendar?”没有橙灯：该界面属于 `mcpServer/elicitation/request` 表单确认，Codex rollout 不写入请求事件；另起 app-server 也看不到 Desktop 私有进程中的实时 `waitingOnUserInput`。
- 新增 `CodexDesktopConfirmationObserver`：只读取 Codex 当前窗口的按钮角色/标签，不读取静态文本、提示词或回答；识别“暂不 + 安装”“拒绝 + 批准/允许”等确认组合。
- 从 Codex Desktop 自身活动日志只解析 `active` 与 `conversationId` 两个结构字段，把可见确认卡精确覆盖到对应线程；卡片处理后自动撤销橙色，状态解析和 D8 实体灯同步不再依赖侧栏位置。
- 采用 750ms 轻量焦点检查、30 秒低频完整校验；进入确认状态后最多 5 秒复核消失，避免持续遍历 Electron 辅助功能树造成高 CPU。
- Debug App 编译通过，72 项 software-only SelfTest 通过；真实当前 Codex 无确认卡时辅助功能诊断为 `waiting=false`，未误判普通界面。
- Universal（arm64 + x86_64）Release、固定签名、DMG CRC/结构验证及 0.11.3 (30) 原位安装均通过；安装后输入监控、辅助功能和 HID manager 复核正常，N Agent Bridge 进程正在运行。
- Development DMG：`dist/NAgentBridge-0.11.3-Development.dmg`；SHA-256：`6970953549389ab1b5b7ca85e7aee5e7f9719aaf4c11788c7a38f96deb9c8402`。真实确认卡出现时的实体橙灯仍需用户下一次卡片弹出时完成最终目视验收。

## 0.11.2 已完成（自定义分配匹配 Codex 左侧栏）

- 复核 Codex Micro 官方说明，确认产品中的最近对话、置顶对话、优先对话、自定义分配正是官方四种 Agent 来源模式，名称与核心排序/空槽行为保持不变。
- 自定义分配不再把最近 50 个长标题放进一个扁平菜单；应用只读 Codex 自己的 `local-projects`、`project-order` 和 `thread-project-assignments`，按左侧栏项目名称与顺序建立原生二级菜单，再显示该项目下的具体对话。
- 每个 Agent 槽位的当前选择同时显示项目名和紧凑对话标题；长标题在菜单中单行截断，悬停当前选择仍可查看完整标题；无项目对话统一放在“其他对话”。
- 轻量候选目录扩大到最近 500 个未归档用户对话，实际 rollout 状态仍只解析最近 50 个以及置顶/自定义精确 ID，避免为了选择旧对话每秒读取大量历史文件。
- Debug build 与 66 项 software-only SelfTest 通过；本机 Codex 状态中 12 个项目均有官方名称，35 个当前用户对话全部进入 500 条候选范围。历史已删除项目不会再单独出现，无法匹配当前项目的旧对话统一进入“其他对话”。
- Universal（arm64 + x86_64）Release、固定签名、DMG CRC/结构验证与 0.11.2 (29) 原位安装通过；实机菜单目视确认项目名与当前 Codex 左侧栏一致，且未执行任何对话绑定。Development DMG：`dist/NAgentBridge-0.11.2-Development.dmg`；SHA-256：`ec7fe6b360cf12474705643c8fe50f25fe48f53c112299c801a1bd47c03f35de`。

## 0.11.1 已完成（长任务蓝灯保持与休眠补发）

- 复现长任务仍运行但 F1 变白：rollout 超过 1.5 MB 后，最早的 `turn_started` 离开尾部读取窗口；旧解析器没有把后续 `agent_reasoning`、reasoning response、工具调用/输出当作独立运行信号，因此从空闲初值开始误判为白灯。
- 后续推理、Agent 消息、工具调用和输出现在都能独立维持蓝灯；显式 `turn_complete/task_complete`、中止和错误事件仍拥有最终状态优先级。
- 状态观察器每 30 秒提供一次无内容心跳；存在蓝/绿/橙/红状态时，应用最多每 90 秒补发一次 D8。Mac 唤醒、应用重新激活或键盘超过 30 秒后的首次活动也会清除写入缓存并重新同步，修复固件休眠后丢失临时颜色。
- 当前真实长任务只读演练已从错误的 `F1 idle` 变为 `F1 reasoning`；Debug build、66 项 software-only SelfTest、Universal（arm64 + x86_64）Release App、签名及 DMG CRC/结构验证通过。
- Development DMG：`dist/NAgentBridge-0.11.1-Development.dmg`；SHA-256：`78fcb58be4d231c68451e53dc20839894c14786ac5e3a00325bd53baa2964f4b`。
- 已从 0.11.0 原位升级 `/Applications/N Agent Bridge.app` 至 0.11.1 (28)：固定签名验证通过、进程正常运行、`LightingAvailable=1`，应用诊断为“六个 Agent 状态已同步到各自实体键；侧灯保持用户灯效”。

## 0.11.0 已完成（稳定 Agent 身份、改键跟灯、多型号安全接入）

- 对照官方 Codex Micro 文档实现最近对话、置顶对话、优先对话、自定义分配四种 Agent 来源模式；置顶模式读取 Codex 自己的有序 `pinned-thread-ids`，六槽使用线程 ID，不再使用侧栏行号作为身份。
- Agent 键改为 `codex://threads/<thread-id>` 精确打开；单击可后台切换，350ms 内双击激活 Codex。自定义空键会新建对话，并在本地索引出现新 ID 后自动绑定。
- 线程索引新增标题、项目目录、recency 与未读 ID 元数据；仍不读取提示词、回答正文或预览。完成且未读保持绿色，优先模式按待确认/报错、未读、运行、最近活动排序。
- `KeyBinding` 新增可选 D8 灯位。Air75 V3 ANSI 根据官方 NuPhyIO 可见键顺序和 skip 规则映射常用键；Agent 1–6 改到数字、字母、F 区或导航键时灯光随实体位置保存和交换，旧 F1–F6 会被清除。
- 普通侧灯已有五种灯效的基础上，新增侧灯常亮颜色选择；Codex 状态继续只写 Agent 实体键，不接管侧灯。
- 新增 Air65 V3、Air100 V3、Kick75、Node75、Node100 官方 USB PID/产品别名 Profile；这些型号可启用安全软件按键模式，硬件写入 driver 仍等待逐型号实机备份、ACK、回读和恢复验证。
- 配置升级到 schema 9；64 项 `Air75CoreSelfTest --software-only`、六型号 App Bundle 资源加载、Universal（arm64 + x86_64）Release App、固定本机签名、DMG CRC/结构验证全部通过。
- Development DMG：`dist/NAgentBridge-0.11.0-Development.dmg`；SHA-256：`e9d4cfc8bb68e922832331ad0e6933901c1bbf75d03d36fb769b6706e866ad22`。Air75 V3 新灯位与四种 Agent 模式仍需要用户在真实 Codex 工作流中完成目视验收；其他五型号的硬件写入按安全策略等待各型号实机验证。

## 0.10.1 已完成（修正 F1–F6 索引，侧灯恢复官方灯效）

- 用户实机照片确认固件 `index 0` 是 Esc，`index 1–6` 才是 F1–F6；0.10.0 的 0–5 映射因此点亮 Esc/F1–F5，并漏掉 F6。
- 任务灯映射改为唯一常量 `[1,2,3,4,5,6]`，运行、Probe 与自测共用；每次 D8 同时把遗留的 `index 0` 写为黑色，保证 0.10.0 点亮的 Esc 立即熄灭。
- F1–F6 已能独立表达六任务后，移除 Codex 侧灯聚合写入。普通侧灯灯效和亮度在任务灯开启时也可独立调整。
- 配置升级至 schema 8：旧版用户只执行一次迁移，从该型号最早的完整灯光备份恢复侧灯 9–16 字节，ACK 与 D5 回读成功后持久标记；以后状态变化只发送 D8，不再发送侧灯 D6。
- 本机 0.10.1 (26) 原位安装完成，固定签名身份不变；诊断为 `LightingAvailable=1`、`sidelightRestoredAfterSignalLights=true`、`F1–F6 已分别同步六个 Codex 任务状态；侧灯保持官方灯效`。Universal（arm64 + x86_64）DMG 验证通过，SHA-256：`7da5802751c7a853ea9ee092a5a506d5c6fadb51ac648586ce39052f48699a73`。

## 0.10.0 已完成（F1–F6 六任务独立状态灯）

- 适配 NuPhy 研发新固件的 `0xD8 SetSignalLights`：一次发送 6 组 `index + RGB`，F1–F6 分别对应 Codex 侧栏任务 1–6，缺少任务的槽位显示空闲白色。
- 真机发送白、蓝、绿、橙、红、白 24-byte 测试，键盘返回完整同 payload ACK，帧头和校验和验证通过；安装应用随后成功同步真实六任务状态。
- 修复新固件 D5 返回 backlight mode `0x15` 被旧范围 0–20 拒绝的问题；这会把 `LightingAvailable` 错误置为 false 并连带停止侧灯。0.10.0 已接受新模式，侧灯恢复聚合状态。
- D6 侧灯与 D8 六灯改为独立事务和独立缓存；单灯失败只报告 F1–F6 错误，不再关闭仍正常工作的侧灯通道。
- UI 更新为“Codex 任务状态灯”；0.10.0 当时仍保留侧灯聚合，已由 0.10.1 取消。
- Debug App、Probe 与 software-only SelfTest 通过；0.10.0 (25) 使用原稳定签名原位安装，Designated Requirement 未变化，应用诊断为 `LightingAvailable=1`、`F1–F6 已分别同步六个 Codex 任务状态`。Universal（arm64 + x86_64）Development DMG CRC/结构验证通过，SHA-256：`3b6d5d38d77e7838a1887ec7ddd1beda766c54d3c2b19a6bc8ea7839ee4c9994`。

## 0.9.9 已完成（外发 App 启动崩溃）

- 朋友 Mac 的完整报告确认：macOS 14.6.1、ARM64 原生启动均正常，崩溃为主线程 `EXC_BREAKPOINT/SIGTRAP`，栈顶是 SwiftPM `static NSBundle.module` 的 `_assertionFailure`，不是 Gatekeeper、权限或 CPU 架构问题。
- 根因是 SwiftPM 生成的资源访问器只查 `Bundle.main.bundleURL/Air75AgentBridge_Air75AgentBridgeCore.bundle` 和开发机 `.build/...` 绝对路径，而打包脚本按标准把资源放在 `Contents/Resources`；开发机因绝对路径存在掩盖了问题，朋友电脑必然失败。
- `DeviceProfileRegistry` 不再调用会 fatalError 的 `Bundle.module`，改为显式查找 App `resourceURL`、SwiftPM 命令行同级目录和标准 `Contents/Resources`；全部缺失时使用内置 Air75 V3 安全 Profile。
- 构建与校验脚本强制要求 Profile JSON 存在，并拒绝可执行文件残留 SwiftPM 绝对 `.build` 路径或资源断言文本；新增 `--verify-app-bundle` 回归检查。
- 0.9.9 (24) Universal App、50 项 software-only SelfTest、App Bundle Resource Test、签名、DMG CRC 全部通过；只读挂载最终 DMG 后再次加载资源通过。
- `NAgentBridge-0.9.9-Development.dmg` SHA-256：`9b3587842533a07c69e19faa2083171d40b405cd798d5a186d1f0201de29e5a6`。

## 正式站外发行流水线已准备（等待 Apple 身份）

- Release 构建改为对 arm64 与 x86_64 分别编译，再用 `lipo` 合并并逐架构验证；当前 0.9.8 本机测试 App 已确认是 Universal Mach-O。
- 移除未使用的麦克风与网络签名权限；F11 仍由 Codex 自己听写。新包 `codesign` 不再报告 invalid entitlements blob，Info.plist 已正确纳入签名资源。
- 新增 `scripts/release-public.sh`：只有 Developer ID Application、TeamIdentifier、Hardened Runtime、安全时间戳、Universal、签名 DMG、Apple Notarization、Stapling、Gatekeeper 与最终 SHA-256 全部通过才成功。
- 本机开发包改名为 `dist/NAgentBridge-Development.dmg`，避免再次误发。当前 Universal 本机包 SHA-256：`7f5afcc7c8ed995c6912601b93891d83d2c00116d063c4488c2337919ea18bd2`。
- 本机钥匙串只存在 `N Agent Bridge Local Signing`，没有 Developer ID Application；正式公证仍等待 Apple Developer Program 的证书和 notarytool Keychain profile，未生成对外 `dist/NAgentBridge.dmg`。

## 0.9.8 已完成（2.4G 状态侧灯实机打通）

- 用户拔除 USB-C 后，系统只保留 U1 `19F5:2620`；2.4G 键盘事件持续到达，usage `1:0` 配置接口的 SetReport/InputReport 计数持续增加。
- 定位“接收器待响应”的第二层根因：刷新流程把 A1 固件信息、D5 灯光状态和 F3 休眠管理绑定为全成功事务；U1 不转发任一管理命令就会让已经可用的 RGB 通道整体失败。
- 0.9.8 改为 D5 灯光回读决定就绪，A1 固件信息和 F3 休眠设置为可选；2.4G 下不再读取/写入休眠管理，灯光保持时间仍要求 USB-C。
- 安装后实机诊断：`LightingConnection=twoPointFourGHzReceiver`、`LightingAvailable=1`；当前 Codex“正在思考/推理”的蓝色侧灯已完成 D6 写入、ACK 和 D5 回读，消息为“键盘已回读确认”。
- Debug、software-only SelfTest、Release 固定签名、DMG CRC/结构校验、原位安装和权限保持全部通过。
- 已安装 `0.9.8 (23)`；0.9.7 移入废纸篓。DMG SHA-256：`e7cc7170252354cafc92af86331bbd5c5c9421a3375b4202d619182e30512c54`。

## 0.9.7 已完成（2.4G 活动通道路由修复）

- 用户实机同时枚举到 Air75 V3 USB `19F5:1028` 与 U1 接收器 `19F5:2620`；两者都保留 usage `1:0`、64-byte 配置接口。旧逻辑只按“接口存在”固定有线优先，因此键盘已经切到 2.4G 时仍可能把状态色发给非活动的有线 Profile。
- `HIDDeviceManager` 新增只含接口身份、不含 Usage/value 的设备活动回调：接收器产生的任意按键活动会把灯光通道切换为 2.4G，有线接口活动会切回 USB-C；切换时清除旧通道缓存并自动重新读取、补发当前状态色，不记录普通文字输入。
- S4 事务层新增线程安全的成功路由记忆。优先通道无响应时只向另一个已验证的 Air75 V3/U1 接口回退；成功后记住实际响应通道，后续事务不再每次盲选有线。
- Probe 新增 `--connection usb` / `--connection 2.4g` 精确指定目标能力，避免两个接口同时存在时测试结果含混。独立 Probe 因没有正式 App 的 TCC 身份被 macOS 拒绝打开 HID；没有绕过系统权限，最终硬件写入验收由固定签名正式 App 完成。
- Debug App、Probe 编译与 software-only SelfTest 全部通过；Release 固定身份签名、DMG CRC/结构校验和原位安装全部通过。
- 已安装 `0.9.7 (22)`，旧 0.9.6 与临时 build 21 均已移入废纸篓；DMG SHA-256：`edd761a68f17e6e67e9bf34e83260a964f2bc03b4dbd60f2481233570e3db3e1`。安装后输入监控、辅助功能和 HID manager 保持授权；剩余一步是用户按下任意 2.4G 按键后目视确认侧灯同步。

## 0.9.6 已完成（2.4G 实时状态侧灯软件链路）

- 新增通用 `KeyboardLightingConnection`，把 USB-C 与 U1 2.4G 接收器从 macOS 都显示为 USB 的底层事实中分离出来；未来型号由各自已验证 driver 报告配置通道。
- U1（VID `0x19F5` / PID `0x2620`）继续使用官方 S4 64-byte 帧，并在连接切换后强制重新读取固件、两个灯光 Profile 与休眠配置，防止残留有线状态阻断无线写入。
- 2.4G 接收器常驻但键盘休眠时，失败的状态色不会被标记为已完成；第一下无线按键证明链路唤醒后，应用延迟 220ms 自动重新握手并补发当前 Codex 聚合状态色。
- 灯光页状态和说明按真实通道显示 USB-C/2.4G；蓝牙连接时明确说明当前固件没有实时灯光输出通道，不再提示笼统的“需要 USB-C”。
- 官方 NuPhyIO 设备目录对 Air75 V3 仍为 `bleConnectionConfig=null`，本机蓝牙 HID 也没有 64-byte S4 输出接口；因此蓝牙侧不能由应用安全发送 17-byte RGB 状态。这个限制需要键盘固件新增 BLE 配置特征，不能靠 macOS 权限绕过。
- Debug build 与 software-only SelfTest 全部通过；新增 U1 选择、USB 优先和未知接收器拒绝三项回归测试。Release、固定身份签名、DMG CRC/结构校验和原位安装均通过。
- 已安装 `0.9.6 (20)`，旧 `0.9.5` 移入废纸篓；DMG SHA-256：`9dc3b030fb2962616f85c3749d5ac012590470dcc5deec7bda39a983fe31cedc`。
- 当前 Mac 只连接了 USB-C Air75 V3，未枚举到 U1 接收器；2.4G 五色、休眠唤醒和持续同步仍需用户插入接收器完成最后实机验收。

## 0.9.5 已完成（普通输入误触发 F1）

- 定位根因：F1 被按键学习错误保存为 `usagePage 0x07 / usage 0xFFFFFFFF`；这是 IOHID 键盘数组元素的占位值，不是真实按键，普通字母输入时该元素的 value 会变化，因而全部被错误匹配到任务 1。
- 配置升级到 schema 7；加载时只修复不受支持的单项绑定，并按当前硬件 Profile 把 F1 恢复为 F13（usage `0x68`），F2–F12 的现有绑定保持不变。迁移前配置已保存到 Application Support 的 Backups。
- 按键学习现在会把数组报告中的真实 Usage 规范化后再保存，拒绝 0/1 等占位值；HID 发布、MappingEngine 与 DedicatedKeyEventSuppressor 也分别校验支持范围，旧无效配置不会再触发动作。
- 新增自测覆盖：拒绝 `UFFFFFFFF` 绑定、提取数组报告中的真实按键、拒绝占位 value、运行时忽略遗留 sentinel、schema 6 配置单项修复且不改变其余绑定。
- software-only SelfTest、Release 构建、严格签名、Designated Requirement、DMG CRC/结构校验和原位安装均通过；已安装 `0.9.5 (19)`，旧 `0.9.4` 移入废纸篓，可恢复。
- 最终 DMG SHA-256：`7de4efec9fb75a16efefa51a1b50ee4df68bb995a39add5159b8f8eec6f29335`。

## 0.9.4 已完成（背光亮度滑块可靠写入）

- 定位根因：SwiftUI macOS `Slider` 的 `onEditingChanged(false)` 在部分点击/拖动路径没有触发，界面数值变化但没有调用硬件写入。
- 背光和普通侧灯滑块均改为防抖提交：停止变化 250ms 后只写最后一个值，避免连续 HID 写入与忙碌状态丢失最终值。
- 官方 NuPhyIO 编解码再次确认背光亮度为状态 byte 1 的 0–100 直接值；独立实机事务把两个 Profile 从 100% 写到 20%、完整回读后恢复 100%。
- 已安装 0.9.4 后，通过真实应用界面的滑块完成 100% → 20% → 100%；两次退出应用后的硬件回读分别为 `0x14` 和 `0x64`，两个 Profile 一致。
- 测试前生成完整灯光备份；最终背光恢复 100%，应用重新打开，原 6 分钟休眠设置未改变。
- software-only SelfTest、Release 构建、严格签名、Designated Requirement、DMG CRC/结构校验和原位安装均通过。
- 旧 0.9.3 已移入废纸篓，可恢复；最终 DMG SHA-256：`d63082a3b11c905b44fbccde04ba99b7dd06f9bf3070df1fa035186a42e5f41d`。

## 0.9.3 已完成（键盘灯光保持时间）

- 从官方 NuPhyIO WebHID 客户端确认 S4 `GetSleepInfo (0xF3)` 与 `SetSleepCfg (0xF5)`，设置载荷严格为 `[是否启用, 空闲分钟数, 深度休眠字段]`。
- 连接的 Air75 V3 实机读取为 `01 06 18`；同值写入收到 `01 06 18` ACK，随后 `0xF3` 回读一致。
- “灯光 → 普通背光”新增“灯光保持时间”，提供 3、6、10、20、30、60 分钟及“始终亮着”；自定义固件分钟数也能正确显示。
- 写入事务会先读取硬件原值并持久备份，只改启用位与分钟数、保留第三字节；要求 ACK 和延时回读完全一致，失败时回滚原值。
- 通过已安装 App 的真实 UI 完成 6 → 10 → 6 分钟写入和回读；最终硬件恢复并保持原来的 6 分钟。
- 新增型号级 `sleepDriverID` 白名单，后续 NuPhy 键盘必须经独立 Profile 明确启用，未知型号不会使用 Air75 V3 协议。
- software-only 与完整实机 SelfTest、Release 构建、严格签名、Designated Requirement、DMG CRC/结构校验和原位安装均通过。
- 旧 0.9.2 已移入废纸篓，可恢复；最终 DMG SHA-256：`c9df3d2ea4401619209d35898ebaef7aa77177a5f00244cd7084a752caa0fe7a`。

## 0.9.2 已完成（概览双栏精细对齐）

- “使用状态”与“Codex 侧灯”保持相同列宽，并统一为 210pt 内容高度；两张卡片的顶部与底部边线严格对齐。
- 校准侧灯卡片内部节奏：标题、当前状态、F1–F6 状态条、状态说明和五色图例采用一致的分组间距，不再因内容量不同造成视觉偏移。
- Debug build 与 37 项 `Air75CoreSelfTest --software-only` 全部通过；Release App 固定身份签名、Designated Requirement、DMG CRC 和结构校验通过。
- 已从 0.9.1 原位升级安装为 0.9.2；旧 0.9.1 移入废纸篓，可恢复。
- 最终 DMG SHA-256：`519e9652bf00e22efec2ac94db25002b3cd8077cdd2bbcfb27def15bc6e568be`。

## 0.9.1 已完成（原生 UI 精简与隐私清理）

- 按键页从 12 张大卡片改为两列紧凑系统分组；F11 与其他按键完全同级，删除所有可见“测试 F11 听写”和蓝色特殊说明。
- 概览去掉深色渐变 Hero 和重复“常用控制”；设置把设备、启动、Codex、权限合并为通用/权限/高级；灯光去掉重复五色图例和 HEX 文本。
- 全局卡片改为 12px 圆角、无阴影，标题恢复系统 SF 大标题；侧栏删除与窗口标题重复的 Logo/品牌头。
- 删除未使用的应用内 SpeechTranscriber、SpeechTranscribing、AVFoundation/Speech framework 和麦克风/语音识别用途声明。F11 只通过 Codex Desktop 原生听写路径，不由 Bridge 录音。
- Debug build、`Air75CoreSelfTest --software-only`、Release 签名和 DMG 完整校验全部通过。
- 从 0.9.0 到 0.9.1 的真实覆盖升级后，输入监控 `1`、辅助功能 `1`、HID manager open result `0`，固定签名权限保持。
- 最终 DMG SHA-256：`5dcfc4f656b12d7ee6f27520e21ce61cbe39683e6f299254d95f2d46b060ff32`。
- 旧 0.6.1、0.8.0、0.9.0 以及隐私清理前 0.9.1 均移入废纸篓；未清空废纸篓，用户仍可恢复。配置与 `Application Support/Air75AgentBridge/Backups` 完全保留。

## 0.9.0 已完成（通用产品架构与稳定权限身份）

- 对外产品统一为 `N Agent Bridge`，固定 Bundle ID `com.nagentbridge.mac`；SwiftPM target 与旧 Application Support 目录保留内部旧名，以确保源码迁移小且用户配置/备份无损延续。
- 新增 `DeviceProfileRegistry`，从资源目录加载多份型号 Profile 并按 VID/PID、产品名、厂商、传输与 Usage 置信度选择；Air75 V3 Profile 固定 ID 为 `nuphy.air75-v3`。
- 新增 `KeyboardDriverRegistry`：声明式 JSON 只能识别设备，只有代码白名单中的已验证 driver ID 才能取得 Vendor HID 写入能力，防止未来适配其他 NuPhy 型号时误写错误协议。
- 配置升级到 schema 6，记录板载专用层所属 Profile；键位/灯光备份升级到 schema 2 并记录 Profile ID、设备指纹与字节长度，恢复路径拒绝跨型号备份。
- 固定本机代码签名身份 `N Agent Bridge Local Signing` 已写入登录钥匙串并仅信任 codeSign；SHA-1 为 `C6633C857A05DF981A9334F9220E4178866B2368`。
- 构建号 14 与临时构建号 999 的 CDHash 分别不同，但 Designated Requirement 完全一致：`identifier "com.nagentbridge.mac" and certificate root = H"c663…2368"`。后续本机升级不再因 ad-hoc CDHash 改变而丢失 TCC 身份。
- Debug build 与 `Air75CoreSelfTest --software-only` 全部通过；本机缺完整 Xcode/XCTest PlatformPath 的限制不变。
- `dist/N Agent Bridge.app` 与 `dist/NAgentBridge.dmg` 已通过严格签名及 `hdiutil verify`；DMG SHA-256 为 `ffbd2b17096d176d9a1904672c3c1f7f8b5cbb59f9ecde0048a60ffa73d1d46d`。
- 已安装 `/Applications/N Agent Bridge.app`：`0.9.0 (14)`；原 0.8.0 保留为 `/Applications/Air75AgentBridge-0.8.0-before-n-agent.app`。由于这是从旧 ad-hoc Bundle ID 向固定身份迁移，macOS 需要最后授权一次；后续使用同一证书与 Bundle ID 的本机构建不会再变化。
- 最后一次迁移授权已完成；完整重启已安装 0.9.0 后，运行诊断为输入监控 `1`、辅助功能 `1`、HID manager open result `0`。

## 0.8.0 已完成（制品与实机验收进行中）

- 侧灯五状态颜色改为配置化：schema 5 新增 `CodexTaskLightPalette`，灯光页提供五个原生颜色选择器与恢复默认；USB 在线立即走既有备份/ACK/完整回读写入，离线先保存并在下次读取灯光后同步。
- 按键页开放 12 个动作的实体键学习，支持数字、字母、F 区与导航键；相同实体键会交换绑定，自定义绑定不会在板载专用层安装/恢复时被覆盖。
- `DedicatedKeyEventSuppressor` 增加 HID Usage → macOS ANSI virtual key 映射；Codex 控制开启时消费用户选择的普通键，避免数字/字母既触发 Codex 又继续输入。媒体键因无法可靠隔离而不开放学习。
- 修复停止后拔线导致 F 区错乱：停止不再只关闭软件，而是要求 USB-C、选择可验证的原始 1568-byte 备份、完整恢复并回读成功后才关闭控制和提示拔线。
- 新增 Bridge Profile 备份识别：当前历史备份中 06:32、05:12、04:00、03:37、03:36、02:48 均已是专用层，安全恢复器会跳过它们并选择 02:31 的真实原始备份，避免“恢复”后仍是 F13–F24。
- 按键学习改为松开按键后提交，避免 keyDown 已进入系统、keyUp 却被新拦截规则吞掉造成卡键。
- 修复菜单栏 Codex 模式开关可留下板载专用层但停止软件监听的问题，统一为“启用控制 / 停止并恢复键盘”。
- Debug/Release App 编译通过；`Air75CoreSelfTest --software-only` 全部通过（硬件 HID 检查按设计跳过，避免与当前运行 App 争用 Vendor 通道）。App/DMG 签名结构与 `hdiutil verify` 通过，DMG SHA-256 为 `bf27c6a96a1b7aefb5ae38acc24b5e82a94c2abd6ea621e58fa76f18ebd39479`。`swift test` 仍因本机缺完整 Xcode/XCTest PlatformPath 不可用。
- 已安装 `/Applications/Air75AgentBridge.app`：`0.8.0 (13)`；旧版保存在 `/Applications/Air75AgentBridge-0.6.1-before-0.8.0.app`。schema 5 与默认五色配置已成功迁移。
- 新 ad-hoc 二进制 CDHash 变化后，当前诊断为输入监控 `0`、辅助功能 `0`、HID open `kIOReturnNotPermitted`；需用户在系统设置中对 Air75AgentBridge 开关关闭再开启并重启 App，这是 macOS TCC 外部授权，应用无法代替用户完成。

## 0.7.0 已完成（开发中，制品待安装验收）

- 六任务状态跟踪：新增 `CodexThreadIndexReader` 只读打开 `~/.codex/state_<N>.sqlite`（自动发现最高版本号），只查 id/rollout_path/recency 等结构列，过滤 `thread_source='user' AND archived=0`、按 recency 降序取前 6，已对实机 153 行 threads 表验证；索引不可用时回退旧目录扫描。
- `CodexDesktopStatusObserver` 重写为六任务轮询：每任务独立解析 rollout 尾部 1.5MB，mtime 缓存避免重复解析；`CodexRolloutStatusParser` 拆分 parseRaw/applyDecay 使完成 60s/报错 120s 衰减在缓存下仍然正确。
- `turn_aborted` 从报错改判为空闲：用户主动停止任务不再亮红灯 120 秒。
- 侧灯改为六任务聚合策略（红 > 橙 > 蓝 > 绿 > 白），`CodexTaskLightAggregator` 有自测覆盖；概览与灯光页新增 F1–F6 六格软件状态行（不宣称键帽变色）。
- 单键颜色协议定案：反混淆官方 NuPhyIO bundle 提取完整 S4 命令表——Air75 V3 无任何单键写入命令（详见 BLOCKERS.md #2）；`GetLightCount (0xD1)` 与 `GetKeyLightColor (0xD2)` 只读探测实机打通：104 LED = 84 键（LED 0–83）+ 20 侧灯（LED 84–103），312 字节回读与官方参数一致。
- 无线路径定案：官方 U1 2.4G 接收器（VID 0x19F5 / PID 0x2620）暴露同一 S4 配置通道，灯光/键位控制器与 Probe 已支持该身份（有线优先），待接收器插入验收；蓝牙侧官方确认无配置通道（bleConnectionConfig=null），新增 `--wireless-enumerate` 只读枚举工具供蓝牙验收。
- 会话密钥防护：发现并定位"灯光状态稳定乱码"根因为其他配置器遗留的 `SetSecretKey (0xEE)` XOR 会话；两个控制器新增四元 XOR 一致性检测，报 `sessionKeyConflict` 并引导重新插拔，不再把乱码当作状态解析。
- SelfTest 新增 14 项（六任务过滤/排序/limit、路径解析、聚合优先级、衰减、turn_aborted），共 34 项全绿；新增 `--codex-six-task-dry-run` 实机验收命令，六个真实用户任务全部正确解析。
- 使用临时 ModuleCache 并关闭 SwiftPM 二次沙箱后 `swift build` 全部通过。

## 0.6.1 已完成

- 使用图像编辑保留金属 N 与深色玻璃圆角主体，去掉外围黑色方形画布，并生成带真实透明通道的 PNG/ICNS。
- 新图标已通过四角 alpha、macOS Quick Look、应用包资源与安装后资源一致性检查。
- 已安装 `/Applications/Air75AgentBridge.app`：`0.6.1 (11)`；0.6.0 备份为 `/Applications/Air75AgentBridge-0.6.0-before-transparent-logo.app`。
- 0.6.1 DMG 已完成签名结构与磁盘映像校验；SHA-256 为 `735cb7389f965bcb2b3956b739356cfa9a5c33ba7b97bb0217093ec2c3c5bc65`。
- 旧 TCC 记录清除并重新授权后，当前运行诊断为输入监控 `1`、辅助功能 `1`、HID manager open result `0`；实体 F11 的 usage `0x72` 已被识别为 `pushToTalk / longPress`。
- 再次核对 NuPhyIO 当前官方命令表：有 `GetKeyLightColor (0xD2)`，没有 `SetKeyLightColor`；F1–F6 独立实时颜色仍属于固件协议阻塞，不能猜测未知写命令。

## 0.6.0 已完成

- 使用新的深色立体 N 字 Logo，生成并打包 `AppIcon.icns`，Finder、Dock、应用包和应用内品牌区域保持一致。
- SwiftUI 主界面从多页面工程面板精简为四页：`概览`、`按键`、`灯光`、`设置`。
- 概览聚合 Air75 连接、Codex 控制、系统权限和顶部任务侧灯状态，只在需要时提供启用、修复或重启提示。
- F1–F12、F11 Codex 原生听写测试和旋钮推理控制合并到“按键”页，不再为旋钮和语音分别设置导航项。
- 输入监控、辅助功能、Codex 快捷键、登录启动与恢复操作整合到“设置”页；原 HID Usage、指纹、接口数、VID/PID、协议字节和独立诊断表不再暴露在日常界面。
- “灯光”页保留普通背光、普通侧灯和 Codex 五状态侧灯，并继续明确实时状态灯需要 USB-C、按键控制可通过蓝牙使用。
- 首次设置精简为连接 USB-C、允许两项系统权限、启用 Codex 控制三个步骤。
- 0.6.0 App/DMG 已完成严格签名结构校验和磁盘映像校验；DMG SHA-256 为 `5fe8fe8703482ebbaddfaeebb35732876f2792764f1c3341aaff884cef998631`。
- 已安装 `/Applications/Air75AgentBridge.app`：`0.6.0 (10)`；升级前版本保存在 `/Applications/Air75AgentBridge-0.5.0-before-redesign.app`。
- 当前仍使用 ad-hoc 签名，仅适合本机验收；Developer ID、公证和 Stapling 仍未完成。

## 0.5.0 已完成

- F11 中继从普通 F11 改为 Codex 界面公开提示的 `Control-Shift-D`，物理键按下时发送 keyDown、松开时发送 keyUp，短按和长按均保留真实生命周期。
- 新增 Codex Desktop 本地 rollout 状态观察器；只读取事件类型、线程来源和时间戳，不读取用户任务或回答内容。
- 状态固定映射为五色侧灯：白色空闲、蓝色推理、绿色完成、橙色待确认、红色报错；完成/报错分别保留 60/120 秒后回到白色。
- 状态来源固定为 Codex 最近更新的用户任务，即顶部第一个任务（Agent 1）；子 Agent rollout 不会抢占状态灯。
- 状态写入只修改侧灯 9–16 字节，背光 0–8 字节保持不变；退出状态模式只恢复侧灯，不覆盖用户当前背光。
- 已在连接的 Air75 V3 上依次写入白、蓝、绿、橙、红并逐次回读；五次背光字节均完全不变，最后成功恢复原灯光。
- 配置升级至 schema 4，新版首次启动自动启用侧灯状态模式并关闭按键成功浮层。
- `Air75CoreSelfTest` 全部通过；五色侧灯实机测试全部通过；0.5.0 App/DMG 签名结构和 DMG 校验通过。
- 已安装 `/Applications/Air75AgentBridge.app`：`0.5.0 (9)`；0.4.3 已保留为 `/Applications/Air75AgentBridge-0.4.3-before-sidelight-status.app`。
- DMG SHA-256：`cb17aadc06ff1274bd993a30008b3eb24fb4e1ae3f1bec5b2224f78f1677ab9f`。

## 0.4.3 已完成

- 定位 0.4.0 实机失败根因：Codex 已加载快捷键，但 Air75 的专用 HID 事件没有获得 macOS 输入监控许可，因此事件没有到达 Codex。
- 用当前 Codex Desktop 做端到端验证：合成 F2 能打开模型选择器，`Control-Shift-D` 能启动原生听写，AX“停止”按钮能结束听写。
- 改为正式中继链路：`Air75 专用 HID → Bridge → 当前 Codex Desktop 进程`；不再要求 Codex 自己接收 F13–F24。
- 输入监控和辅助功能均改为必需权限：前者读取 Air75，后者只把映射动作发送给 `com.openai.codex`。
- 物理 F1–F6 切换 Codex 任务 1–6；F7 Fast Mode；F8/F9 批准/拒绝；F10 新建任务；F11 原生听写开关；F12 发送。
- 旋钮左转/按下/右转降低推理深度、打开模型/推理选择器、提高推理深度。
- Codex 快捷键安装器迁移到普通组合键中继，并清除旧版受管的 F1–F3、F13–F24 与 `Command-O` 绑定，避免双重触发。
- Air75 旋钮从系统音量/F1–F3 迁移为 `Scroll Lock / Pause / Print Screen` 唯一事件；1568-byte 键位表写后完整回读通过，二次 dry-run 差异为 0。
- 新版不启动第二个 Codex app-server，不记录普通键盘输入，也不把事件广播给其他应用。
- 修复侧灯亮度协议：线路使用 0–255 原始值，界面换算为 0–100%。
- 修复 0.4.1 的重复触发：Print Screen/Scroll Lock/Pause 在 macOS 会转换成 F13/F14/F15，其中 F14/F15 默认控制屏幕亮度。
- 新增非 root 的 CGEvent session tap；Codex 模式启用时消费 F13–F24 的 keyDown/keyUp，暂停或退出 Bridge 时自动解除。
- 拦截器支持 F13–F20 公共虚拟键码及 F13–F24 AppKit 功能键字符，并自动从超时/用户输入禁用状态恢复。
- Bridge 发往 Codex 的事件带独立 source tag，避免与原始 Air75 专用事件混淆。
- 修复 F11：删除会把 Codex“停止任务”按钮误判为“停止听写”的 AX 搜索；该误判会在任务运行时吞掉 F11。
- Codex 快捷键明确增加 `F11 → composer.startDictation`，同时保留官方 `Ctrl+Shift+D`；Bridge 将实体 F11 定向转换成普通 F11。
- 取消所有实体按键成功后的屏幕浮层，现有配置的 `overlayEnabled` 已关闭；动作只在 Bridge 状态页留下结果。

## 实机与构建验证

- Air75 V3 USB：VID `0x19F5`、PID `0x1028`，实机身份与序列号读取已验证（公开文档不记录具体序列号）。
- Air75 板载 Profile：完整读取 1568 bytes，当前 Profile 差异 `0 bytes`。
- 顶排物理 F1–F12：板载发送 F13–F24；旋钮发送 Scroll Lock/Pause/Print Screen。
- Codex 中继快捷键：旧版直接 F 键已移除，新组合键安装和验证通过。
- `Air75CoreSelfTest`：21 项全部通过，包括 Codex 状态解析、中继键位、旧绑定迁移、硬件旋钮 Profile 和官方 NuPhyIO 灯光状态读取。
- `swift build --product Air75AgentBridge`：通过。
- Release App：ad-hoc 严格签名校验通过。
- DMG：`hdiutil verify` 通过。
- 0.4.3、0.5.0 和 0.6.0 均曾安装并完成对应阶段验收；现已升级为 0.6.1。
- `swift test`：本机只有 Command Line Tools，XCTest PlatformPath 不可用；核心测试由独立 SelfTest 执行。

## 已生成制品

- `dist/N Agent Bridge.app`
- `dist/NAgentBridge.dmg`
- 版本：`0.9.8 (23)`
- DMG SHA-256：`e7cc7170252354cafc92af86331bbd5c5c9421a3375b4202d619182e30512c54`
- 0.6.1 应用备份：`/Applications/Air75AgentBridge-0.6.1-before-0.8.0.app`
- 旋钮迁移前键盘备份：`2026-07-19T04-00-24Z-hardware-keymap.json`
- Codex 快捷键迁移前备份：`2026-07-19T04-00-03Z-codex-keybindings.json`

## 仍需用户完成的真实验收

1. 在系统设置的“输入监控”和“辅助功能”中，把 Air75AgentBridge 的开关关闭后重新开启，再退出并重开 App；确认设置页两项均为“已允许”。
2. 在“按键”页把一个动作改到数字键，确认只触发 Codex、不输入数字；再恢复 F1–F12。
3. 保持 USB-C，点“停止并恢复键盘”，等待“现在可以拔掉数据线”，拔线后确认 F 区与旋钮恢复键盘原生功能。
4. 到“灯光”页自定义一种状态颜色，确认对应侧灯写入并回读。
5. 切换 Bluetooth 并连接 `Air75 V3-2`，完成蓝牙按键事件、休眠重连和板载 Profile 保留验收；侧灯实时状态本身仍需要 USB 数据连接。
