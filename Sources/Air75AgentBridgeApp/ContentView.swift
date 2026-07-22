import Air75AgentBridgeCore
import AppKit
import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview
    case controls
    case lighting
    case settings

    var id: String { rawValue }

    func title(_ language: InterfaceLanguage) -> String {
        switch self {
        case .overview: return language.text("概览", "Overview")
        case .controls: return language.text("按键", "Keys")
        case .lighting: return language.text("灯光", "Lighting")
        case .settings: return language.text("设置", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .controls: return "keyboard"
        case .lighting: return "lightbulb.led"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language
    @State private var selection: SidebarPage? = .overview

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: $selection)
        } detail: {
            ScrollView {
                Group {
                    switch selection ?? .overview {
                    case .overview:
                        OverviewView(openSettings: { selection = .settings })
                    case .controls:
                        ControlsView()
                    case .lighting:
                        LightingView()
                    case .settings:
                        SettingsView()
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .frame(maxWidth: 1040, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppPalette.pageBackground)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.showOnboarding = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help(language.text("显示快速设置", "Show quick setup"))
            }
        }
        .sheet(item: Binding(
            get: { store.bluetoothAssociationCandidate },
            set: { store.bluetoothAssociationCandidate = $0 }
        )) { _ in
            BluetoothAssociationSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showOnboarding) {
            OnboardingView()
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
    }
}

private struct AppSidebar: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language
    @Binding var selection: SidebarPage?

    var body: some View {
        VStack(spacing: 0) {
            List(SidebarPage.allCases, selection: $selection) { page in
                Label(page.title(language), systemImage: page.icon)
                    .padding(.vertical, 4)
                    .tag(page)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.currentDevice == nil ? Color.secondary.opacity(0.5) : Color.green)
                        .frame(width: 8, height: 8)
                    Text(store.currentDevice == nil
                         ? language.text("等待 NuPhy 键盘", "Waiting for NuPhy keyboard")
                         : language.text("\(store.currentModelName) 已连接", "\(localizedModelName(store.currentModelName, language)) connected"))
                        .font(.caption.weight(.semibold))
                }
                Text(store.configuration.enabled
                     ? language.text("Codex 控制已开启", "Codex control is on")
                     : language.text("Codex 控制已暂停", "Codex control is paused"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(language.text("版本 \(appVersion)", "Version \(appVersion)"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
    }
}

private struct BluetoothAssociationSheet: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProductLogo(size: 64, cornerRadius: 17)
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text(
                    "连接这台 \(store.bluetoothAssociationCandidate?.modelName ?? "NuPhy 键盘")？",
                    "Connect this \(store.bluetoothAssociationCandidate?.modelName ?? "NuPhy keyboard")?"
                ))
                    .font(.title.bold())
                Text(language.text("确认后，USB 配置会继续在这台蓝牙键盘上使用。", "Your USB configuration will continue to work with this keyboard over Bluetooth."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(language.text("稍后", "Later")) { store.bluetoothAssociationCandidate = nil }
                Button(language.text("连接", "Connect")) { store.confirmBluetoothAssociation() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 460)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language

    private var usbConnected: Bool {
        store.devices.contains { $0.isRecognized && $0.transports.contains(.usb) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ProductLogo(size: 92, cornerRadius: 24)
                Text(language.text("让 NuPhy 键盘直接控制 Codex", "Control Codex directly from your NuPhy keyboard"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(language.text("首次用 USB-C 完成一次设置，之后即可通过蓝牙日常使用。", "Complete setup once over USB-C, then use Bluetooth day to day."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 34)
            .padding(.bottom, 26)

            VStack(spacing: 0) {
                SetupRow(
                    number: "1",
                    title: language.text("连接受支持的 NuPhy 键盘", "Connect a supported NuPhy keyboard"),
                    detail: usbConnected ? language.text("已通过 USB-C 识别", "Recognized over USB-C") : language.text("请使用可传输数据的 USB-C 线", "Use a USB-C data cable"),
                    complete: usbConnected || store.configuration.hasAnyInstalledHardwareProfile
                )
                Divider().padding(.leading, 58)
                SetupRow(
                    number: "2",
                    title: language.text("允许系统权限", "Allow system permissions"),
                    detail: store.inputMonitoringGranted && store.accessibilityGranted ? language.text("两项权限均已完成", "Both permissions are ready") : language.text("允许读取专用按键并控制 Codex", "Allow dedicated keys to control Codex"),
                    complete: store.inputMonitoringGranted && store.accessibilityGranted,
                    buttonTitle: store.inputMonitoringGranted && store.accessibilityGranted ? nil : language.text("打开设置", "Open Settings"),
                    action: {
                        if !store.inputMonitoringGranted { store.requestInputMonitoring() }
                        else if !store.accessibilityGranted { store.requestAccessibility() }
                    }
                )
                Divider().padding(.leading, 58)
                SetupRow(
                    number: "3",
                    title: language.text("启用 Codex 控制", "Enable Codex control"),
                    detail: store.configuration.enabled && !store.currentHardwareProfileNeedsInstallation
                        ? language.text("专用按键与\(store.reasoningControlName)已经可以使用", "Dedicated keys and \(localizedReasoningControlName(store.reasoningControlName, language)) are ready")
                        : language.text("自动备份并写入当前型号的专用控制层", "Back up and configure the dedicated control layer automatically"),
                    complete: store.configuration.enabled && !store.currentHardwareProfileNeedsInstallation,
                    buttonTitle: store.configuration.enabled && !store.currentHardwareProfileNeedsInstallation
                        ? nil : language.text("启用", "Enable"),
                    buttonEnabled: usbConnected || store.configuration.hasAnyInstalledHardwareProfile,
                    action: { store.oneClickEnable() }
                )
            }
            .padding(.horizontal, 24)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppPalette.hairline)
            )
            .padding(.horizontal, 38)

            if store.hardwareProfileBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(language.text("正在安全配置键盘…", "Configuring keyboard safely…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 22)
            Divider()
            HStack {
                Text(language.text("所有设置都可以稍后在“设置”中完成。", "You can finish any remaining steps later in Settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(language.text("进入应用", "Enter App")) { store.completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(24)
        }
        .frame(width: 680, height: 620)
        .background(AppPalette.pageBackground)
    }
}

private struct SetupRow: View {
    let number: String
    let title: String
    let detail: String
    let complete: Bool
    var buttonTitle: String?
    var buttonEnabled = true
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(complete ? Color.green.opacity(0.14) : Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                if complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                } else {
                    Text(number)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .disabled(!buttonEnabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language
    let openSettings: () -> Void

    private var controlsReady: Bool {
        !store.currentHardwareProfileNeedsInstallation
            && store.configuration.mappingMode != .unavailable
            && store.codexDesktopKeybindingsInstalled
            && store.dedicatedEventSuppressionActive
    }

    private var permissionsReady: Bool {
        store.inputMonitoringGranted && store.accessibilityGranted
    }

    private var isReady: Bool {
        store.currentDevice != nil && controlsReady && permissionsReady && store.configuration.enabled
    }

    private var heroTitle: String {
        if store.hardwareProfileBusy { return language.text("正在配置 \(store.currentModelName)", "Configuring \(localizedModelName(store.currentModelName, language))") }
        if isReady { return language.text("一切就绪", "Everything is ready") }
        if store.currentDevice == nil { return language.text("连接键盘，开始使用", "Connect your keyboard to begin") }
        return language.text("还差一步即可使用", "One more step to get started")
    }

    private var heroSubtitle: String {
        if isReady, store.installedHardwareProfileIsCurrent {
            return store.signalLightingSupported
                ? language.text("自定义按键、\(store.reasoningControlName)与 Agent 状态灯正在与 Codex 协同工作。", "Custom keys, \(localizedReasoningControlName(store.reasoningControlName, language)), and Agent status lights are working with Codex.")
                : language.text("\(store.currentModelName) 的 F1–F12 与\(store.reasoningControlName)正在控制 Codex；当前型号灯光仍保持键盘原生效果。", "F1–F12 and \(localizedReasoningControlName(store.reasoningControlName, language)) on \(localizedModelName(store.currentModelName, language)) are controlling Codex; lighting remains in its native keyboard mode.")
        }
        if isReady { return language.text("自定义按键正在安全的软件模式下控制 Codex；未写入未经验证的键盘固件。", "Custom keys are controlling Codex in safe software mode; no unverified firmware is written.") }
        if store.currentDevice == nil { return language.text("打开键盘并连接蓝牙，首次设置请使用 USB-C。", "Turn on the keyboard and connect over Bluetooth. Use USB-C for first-time setup.") }
        if !permissionsReady { return language.text("完成系统权限后，按键只会控制 Codex。", "Allow system permissions so the keys control Codex only.") }
        return language.text("启用控制后，你的工作流会立即生效。", "Enable control to activate your workflow immediately.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: language.text("概览", "Overview"), subtitle: language.text("键盘与 Codex 的连接状态", "Keyboard and Codex connection status"))

            PremiumCard {
                HStack(spacing: 18) {
                ProductLogo(size: 64, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 9) {
                    StatusPill(
                        text: isReady ? language.text("已连接", "Connected") : (store.configuration.enabled ? language.text("需要完成设置", "Setup required") : language.text("控制已暂停", "Control paused")),
                        color: isReady ? .green : .orange
                    )
                    Text(heroTitle)
                        .font(.title2.bold())
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                if store.hardwareProfileBusy {
                    ProgressView().tint(.white).controlSize(.large)
                } else {
                    Button(primaryActionTitle) {
                        if store.configuration.enabled && !store.currentHardwareProfileNeedsInstallation {
                            store.disable()
                        }
                        else { store.oneClickEnable() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                PremiumCard {
                    VStack(alignment: .leading, spacing: 0) {
                        CardHeading(icon: "checkmark.shield", title: language.text("使用状态", "Status"), subtitle: readinessSummary)
                        ReadinessRow(
                            icon: "keyboard",
                            title: localizedModelName(store.currentModelName, language),
                            value: store.currentDevice == nil ? language.text("未连接", "Not connected") : deviceConnectionText(store.currentDevice, language),
                            ready: store.currentDevice != nil
                        )
                        Divider().padding(.leading, 44)
                        ReadinessRow(
                            icon: "command",
                            title: language.text("Codex 控制", "Codex control"),
                            value: store.hardwareProfileBusy
                                ? language.text("正在配置", "Configuring")
                                : (controlsReady
                                    ? language.text("已配置", "Configured")
                                    : (store.currentHardwareProfileNeedsInstallation ? language.text("需要配置当前键盘", "Keyboard setup required") : language.text("需要配置", "Setup required"))),
                            ready: controlsReady,
                            actionTitle: store.hardwareProfileBusy || controlsReady
                                ? nil : (store.currentHardwareProfileNeedsInstallation ? language.text("配置", "Configure") : language.text("修复", "Repair")),
                            action: {
                                if store.currentHardwareProfileNeedsInstallation { store.oneClickEnable() }
                                else { store.installCodexDesktopBindings() }
                            }
                        )
                        Divider().padding(.leading, 44)
                        ReadinessRow(
                            icon: "lock.shield",
                            title: language.text("系统权限", "System permissions"),
                            value: permissionsReady ? language.text("已允许", "Allowed") : language.text("需要允许", "Permission required"),
                            ready: permissionsReady,
                            actionTitle: permissionsReady ? nil : language.text("前往设置", "Open Settings"),
                            action: openSettings
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .topLeading)
                }

                PremiumCard {
                    VStack(alignment: .leading, spacing: 0) {
                        CardHeading(icon: "lightbulb.led", title: language.text("Codex 状态灯", "Codex status lights"), subtitle: language.text("六个 Agent 实体键分别显示任务状态", "Six Agent keys show individual task status"))
                        HStack(spacing: 15) {
                            Circle()
                                .fill(Color(hex: store.taskLightColorHex(for: store.codexTopTaskLightState)))
                                .frame(width: 42, height: 42)
                                .overlay(Circle().stroke(Color.primary.opacity(0.12)))
                                .shadow(color: Color(hex: store.taskLightColorHex(for: store.codexTopTaskLightState)).opacity(0.45), radius: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localizedTaskLightState(store.codexTopTaskLightState, language))
                                    .font(.title3.bold())
                        Text(!store.signalLightingSupported ? language.text("当前型号等待灯光驱动验证", "Lighting driver validation pending") : (store.configuration.agentLightingEnabled == true ? language.text("状态灯已开启", "Status lights are on") : language.text("状态灯已关闭", "Status lights are off")))
                                    .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        SixTaskStatusRow(tasks: store.codexTasks, palette: store.configuration.resolvedTaskLightPalette,
                                         keyLabels: store.agentKeyLabels)
                            .padding(.top, 12)
                        HStack(spacing: 7) {
                            ForEach(CodexTaskLightState.allCases, id: \.self) { state in
                                Circle()
                                    .fill(Color(hex: store.taskLightColorHex(for: state)))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.14)))
                            }
                            Text(language.text("5 种实时状态", "5 live states"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 14)
                    }
                    .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .topLeading)
                }
            }

            if store.codexRestartRequired {
                InlineNotice(
                    icon: "arrow.clockwise",
                    title: language.text("请重新打开一次 Codex", "Restart Codex once"),
                    text: language.text("新的控制快捷键已经安装，重启 Codex 后即可生效。", "New control shortcuts are installed and will work after Codex restarts."),
                    color: .orange
                )
            }
        }
    }

    private var primaryActionTitle: String {
        if store.currentHardwareProfileNeedsInstallation { return language.text("配置 \(store.currentModelName)", "Configure \(localizedModelName(store.currentModelName, language))") }
        if store.configuration.enabled {
            return store.installedHardwareProfileIsCurrent ? language.text("停止并恢复键盘", "Stop and restore keyboard") : language.text("停止控制", "Stop control")
        }
        if store.installedHardwareProfileIsCurrent { return language.text("启用控制", "Enable control") }
        return language.text("连接并启用", "Connect and enable")
    }

    private var readinessSummary: String {
        if isReady { return language.text("所有核心功能都已就绪", "All core features are ready") }
        if !permissionsReady { return language.text("完成权限即可开始", "Allow permissions to begin") }
        return language.text("正在等待连接或启用", "Waiting for connection or activation")
    }
}

struct ControlsView: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                PageTitle(title: language.text("按键", "Keys"), subtitle: language.text("把 12 个 Codex 动作分配到你顺手的实体键", "Assign 12 Codex actions to the physical keys you prefer"))
                Spacer()
                Button(language.text("恢复默认", "Restore Defaults")) { store.resetBindingsToPhysicalFunctionKeys() }
                    .buttonStyle(.bordered)
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardHeading(icon: "rectangle.stack", title: language.text("Agent 对话来源", "Agent conversation source"), subtitle: language.text("按对话 ID 绑定，不再依赖侧栏位置", "Bind by conversation ID instead of sidebar position"))
                        Spacer()
                        Picker(language.text("对话来源", "Conversation source"), selection: Binding(
                            get: { store.configuration.resolvedAgentSourceMode },
                            set: { store.setAgentSourceMode($0) }
                        )) {
                            ForEach(CodexAgentSourceMode.allCases) { mode in
                                Text(localizedAgentSourceMode(mode, language)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Text(localizedAgentSourceDetail(store.configuration.resolvedAgentSourceMode, language))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.configuration.resolvedAgentSourceMode == .custom {
                        Divider()
                        Label(language.text("按 Codex 左侧栏的项目分组；每颗键绑定其中一个具体对话。", "Grouped like the Codex sidebar; each key binds to one conversation."),
                              systemImage: "sidebar.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(0..<CodexAgentSlotResolver.slotCount, id: \.self) { index in
                            HStack(spacing: 12) {
                                Text(store.agentKeyLabels[index])
                                    .font(.caption.monospaced())
                                    .frame(width: 54, alignment: .leading)
                                Text("Agent \(index + 1)")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                customAssignmentMenu(for: index)
                            }
                        }
                    }
                }
            }

            PremiumCard {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(store.activeKeyBindings.enumerated()), id: \.offset) { index, binding in
                        KeyActionRow(
                            functionKey: "\(index + 1)",
                            key: binding.displayName,
                            action: localizedBridgeAction(binding.action, language),
                            changeTitle: language.text("更改", "Change"),
                            waitingTitle: language.text("等待…", "Waiting…"),
                            learning: store.learningBindingIndex == index,
                            onLearn: { store.beginLearningBinding(index) }
                        )
                    }
                }
            }

            if let learningIndex = store.learningBindingIndex,
               store.activeKeyBindings.indices.contains(learningIndex) {
                InlineNotice(
                    icon: "keyboard.badge.ellipsis",
                    title: language.text("请按新的实体键", "Press a new physical key"),
                    text: language.text("正在设置 \(store.activeKeyBindings[learningIndex].action.displayName)。支持数字、字母、F 区和导航键；重复键会自动交换。", "Assigning \(localizedBridgeAction(store.activeKeyBindings[learningIndex].action, language)). Numbers, letters, function keys, and navigation keys are supported; duplicate keys are swapped automatically."),
                    color: .accentColor,
                    buttonTitle: language.text("取消", "Cancel"),
                    action: store.cancelLearningBinding
                )
            } else {
                Text(language.text("Codex 控制开启时，自定义键会成为专用控制键，不再同时输入原字符；停止控制后会恢复原本行为。", "While Codex control is on, custom keys become dedicated controls and no longer type their original characters. Their normal behavior returns when control stops."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 14) {
                    CardHeading(
                        icon: store.reasoningControlName == "触控条" ? "hand.draw" : "dial.medium",
                        title: localizedReasoningControlName(store.reasoningControlName, language),
                        subtitle: language.text("调整当前 Codex 的推理深度", "Adjust reasoning depth in the current Codex task")
                    )
                    HStack(spacing: 12) {
                        KnobAction(icon: store.reasoningControlName == "触控条" ? "arrow.left" : "rotate.left", title: localizedKnobText(store.reasoningControlGestures[0].title, language), detail: localizedKnobText(store.reasoningControlGestures[0].detail, language))
                        KnobAction(icon: "button.programmable", title: localizedKnobText(store.reasoningControlGestures[1].title, language), detail: localizedKnobText(store.reasoningControlGestures[1].detail, language))
                        KnobAction(icon: store.reasoningControlName == "触控条" ? "arrow.right" : "rotate.right", title: localizedKnobText(store.reasoningControlGestures[2].title, language), detail: localizedKnobText(store.reasoningControlGestures[2].detail, language))
                    }
                }
            }

            if !store.codexDesktopKeybindingsInstalled || store.codexRestartRequired {
                InlineNotice(
                    icon: "wrench.and.screwdriver",
                    title: store.codexRestartRequired ? language.text("需要重新打开 Codex", "Codex needs to restart") : language.text("Codex 控制需要修复", "Codex control needs repair"),
                    text: store.codexRestartRequired ? language.text("重启后，F11 与\(store.reasoningControlName)就会使用新快捷键。", "After restart, F11 and \(localizedReasoningControlName(store.reasoningControlName, language)) will use the new shortcuts.") : language.text("重新安装本机控制快捷键，不会改变你的 Codex 数据。", "Reinstall local control shortcuts without changing your Codex data."),
                    color: .orange,
                    buttonTitle: store.codexRestartRequired ? nil : language.text("立即修复", "Repair Now"),
                    action: store.installCodexDesktopBindings
                )
            }
        }
    }

    private var assignableThreads: [CodexTaskLightSnapshot] {
        store.codexThreadCandidates.filter { $0.threadID != nil }
    }

    private var assignableThreadGroups: [CodexThreadProjectGroup] {
        var groups: [String: CodexThreadProjectGroup] = [:]
        for thread in assignableThreads {
            let key: String
            let name: String
            if let projectID = thread.projectID, !projectID.isEmpty {
                key = projectID
                name = thread.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? language.text("未命名项目", "Untitled Project")
            } else {
                key = "projectless"
                name = language.text("其他对话", "Other Conversations")
            }
            if var group = groups[key] {
                group.threads.append(thread)
                group.order = min(group.order, thread.projectOrder ?? Int.max)
                groups[key] = group
            } else {
                groups[key] = CodexThreadProjectGroup(
                    id: key,
                    name: name,
                    order: thread.projectOrder ?? Int.max,
                    threads: [thread]
                )
            }
        }
        return groups.values.map { group in
            var sorted = group
            sorted.threads.sort {
                if $0.recencyAtMS != $1.recencyAtMS { return $0.recencyAtMS > $1.recencyAtMS }
                return normalizedThreadTitle($0) < normalizedThreadTitle($1)
            }
            return sorted
        }.sorted {
            if $0.id == "projectless" { return false }
            if $1.id == "projectless" { return true }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func normalizedThreadTitle(_ thread: CodexTaskLightSnapshot) -> String {
        if let title = thread.title {
            let normalized = title.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !normalized.isEmpty { return normalized }
        }
        return thread.threadID.map { language.text("对话 …\($0.suffix(8))", "Conversation …\($0.suffix(8))") } ?? language.text("未命名对话", "Untitled Conversation")
    }

    private func compactThreadTitle(_ thread: CodexTaskLightSnapshot, limit: Int = 46) -> String {
        let title = normalizedThreadTitle(thread)
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)) + "…"
    }

    private func projectName(for thread: CodexTaskLightSnapshot) -> String {
        if let name = thread.projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let path = thread.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return language.text("其他对话", "Other Conversations")
    }

    private func assignedThread(_ index: Int) -> CodexTaskLightSnapshot? {
        guard let id = store.assignedThreadID(
            for: index,
            mode: store.configuration.resolvedAgentSourceMode
        ) else { return nil }
        return store.codexThreadCandidates.first(where: { $0.threadID == id })
    }

    private func assignedThreadFallbackTitle(_ index: Int) -> String? {
        guard let id = store.assignedThreadID(
            for: index,
            mode: store.configuration.resolvedAgentSourceMode
        ) else { return nil }
        return language.text("对话 …\(id.suffix(8))", "Conversation …\(id.suffix(8))")
    }

    private func customAssignmentMenu(for index: Int) -> some View {
        let selection = assignedThread(index)
        let assignedID = store.assignedThreadID(
            for: index,
            mode: store.configuration.resolvedAgentSourceMode
        )
        return Menu {
            Button {
                store.assignThread(nil, to: index, for: store.configuration.resolvedAgentSourceMode)
            } label: {
                if assignedID == nil {
                    Label(language.text("不分配", "Unassigned"), systemImage: "checkmark")
                } else {
                    Text(language.text("不分配", "Unassigned"))
                }
            }
            Divider()
            ForEach(assignableThreadGroups) { group in
                Menu(group.name) {
                    ForEach(group.threads, id: \.threadID) { thread in
                        Button {
                            store.assignThread(thread.threadID, to: index,
                                               for: store.configuration.resolvedAgentSourceMode)
                        } label: {
                            if assignedID == thread.threadID {
                                Label(compactThreadTitle(thread), systemImage: "checkmark")
                            } else {
                                Text(compactThreadTitle(thread))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(selection.map(projectName) ?? (assignedID == nil ? language.text("未分配", "Unassigned") : language.text("原对话", "Original conversation")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(selection.map { compactThreadTitle($0, limit: 34) }
                         ?? assignedThreadFallbackTitle(index)
                         ?? language.text("选择对话", "Choose Conversation"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 300, alignment: .trailing)
        .help(selection.map(normalizedThreadTitle) ?? assignedThreadFallbackTitle(index) ?? language.text("选择一个 Codex 对话", "Choose a Codex conversation"))
    }
}

private struct CodexThreadProjectGroup: Identifiable {
    let id: String
    let name: String
    var order: Int
    var threads: [CodexTaskLightSnapshot]
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct KeyActionRow: View {
    let functionKey: String
    let key: String
    let action: String
    let changeTitle: String
    let waitingTitle: String
    let learning: Bool
    let onLearn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(functionKey)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(action)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(learning ? waitingTitle : changeTitle, action: onLearn)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(learning)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(learning ? Color.accentColor.opacity(0.08) : AppPalette.softFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(learning ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}

private struct KnobAction: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(icon: icon, color: .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.softFill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct LightingView: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                PageTitle(title: language.text("灯光", "Lighting"), subtitle: language.text("普通背光与 Codex 实时任务状态灯", "Standard backlight and live Codex task status lights"))
                Spacer()
                HStack(spacing: 10) {
                    StatusPill(
                        text: lightingStatusText,
                        color: store.lightingAvailable ? .green : .orange
                    )
                    Button {
                        store.refreshLighting()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.lightingBusy)
                    .help(language.text("重新读取灯光", "Refresh lighting"))
                }
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        CardHeading(icon: "lightbulb", title: language.text("普通背光", "Standard backlight"), subtitle: language.text("选择你喜欢的键盘灯效", "Choose your preferred keyboard lighting effect"))
                        Spacer()
                        Picker(language.text("背光灯效", "Backlight effect"), selection: Binding(
                            get: { Air75BacklightMode(rawValue: store.lightingStates.first?.backlight.mode ?? 6) ?? .wave },
                            set: { store.setBacklightMode($0) }
                        )) {
                            ForEach(store.supportedBacklightModes) { mode in
                                Text(localizedBacklightMode(mode, language)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        Text(language.text("常亮颜色", "Static color"))
                            .font(.subheadline.weight(.medium))
                        ForEach(backlightColors, id: \.hex) { item in
                            Button {
                                store.setBacklightStaticColor(hex: item.hex)
                            } label: {
                                Circle()
                                    .fill(Color(hex: item.hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.16)))
                            }
                            .buttonStyle(.plain)
                            .help(localizedColorName(item.name, language))
                        }
                    }

                    Divider()

                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text("灯光保持时间", "Light timeout"))
                                .font(.subheadline.weight(.medium))
                            Text(language.text("键盘无操作达到该时间后会熄灯并休眠", "Lights turn off and the keyboard sleeps after this period of inactivity"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(language.text("灯光保持时间", "Light timeout"), selection: Binding(
                            get: { store.sleepConfiguration?.autoSleepAfterMinutes ?? 0 },
                            set: { store.setKeyboardLightStayOnMinutes($0 == 0 ? nil : $0) }
                        )) {
                            ForEach(sleepDurationOptions, id: \.self) { minutes in
                                Text(minutes == 0 ? language.text("始终亮着", "Always On") : language.text("\(minutes) 分钟", "\(minutes) min"))
                                    .tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .disabled(store.sleepConfiguration == nil)
                    }

                    if store.sleepConfiguration?.autoSleepEnabled == false {
                        Text(language.text("始终亮着会明显增加蓝牙和 2.4G 模式下的耗电。", "Always On significantly increases power use over Bluetooth and 2.4G."))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(!store.lightingAvailable || store.lightingBusy || !store.fullLightingControlSupported)
                .overlay(alignment: .bottomLeading) {
                    if store.lightingAvailable && !store.fullLightingControlSupported {
                        Text(language.text("当前型号仅开放已验证的 Agent 单键状态灯；普通背光保持键盘原设置。", "This model only exposes verified per-key Agent status lighting; the standard backlight keeps its keyboard settings."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }
                }
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        CardHeading(icon: "bolt.horizontal.circle", title: language.text("Codex 任务状态灯", "Codex task status lights"), subtitle: language.text("六个 Agent 实体键分别显示任务，不改变普通侧灯", "Six Agent keys show individual tasks without changing standard side lights"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.configuration.agentLightingEnabled == true },
                            set: { store.setAgentLightingEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!store.lightingAvailable || store.lightingBusy)
                    }

                    if store.configuration.agentLightingEnabled == true {
                        HStack(spacing: 18) {
                            Circle()
                                .fill(Color(hex: store.taskLightColorHex(for: store.codexTopTaskLightState)))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.primary.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.text("任务汇总 · \(localizedTaskLightState(store.codexTopTaskLightState, language))", "Task summary · \(localizedTaskLightState(store.codexTopTaskLightState, language))"))
                                    .font(.headline)
                            }
                            Spacer()
                        }

                        SixTaskStatusRow(tasks: store.codexTasks, palette: store.configuration.resolvedTaskLightPalette,
                                         keyLabels: store.agentKeyLabels)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(language.text("状态颜色", "Status colors"))
                                    .font(.subheadline.bold())
                                Spacer()
                                Button(language.text("恢复默认", "Restore Defaults")) { store.resetTaskLightColors() }
                                    .buttonStyle(.borderless)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                                ForEach(CodexTaskLightState.allCases, id: \.self) { state in
                                    TaskLightColorEditor(
                                        state: state,
                                        hex: store.taskLightColorHex(for: state),
                                        onChange: { store.setTaskLightColor(state, hex: $0) }
                                    )
                                }
                            }
                            Text(language.text("颜色会保存在本机；已验证型号通过 USB-C 或 2.4G 把状态写到 Agent 当前所在实体键。", "Colors are stored on this Mac. Verified models write status to each Agent's current physical key over USB-C or 2.4G."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if store.configuration.agentLightingEnabled == true { Divider() }

                    VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(localizedSecondaryLightingZoneName(store.secondaryLightingZoneName, language)).font(.subheadline.weight(.medium))
                                Spacer()
                                Picker(language.text("侧灯灯效", "Side-light effect"), selection: Binding(
                                    get: {
                                        store.lightingStates.first?.sidelight.mode
                                            ?? store.supportedSidelightModes.first?.rawValue
                                            ?? 0
                                    },
                                    set: { rawValue in
                                        if let mode = Air75SidelightMode(rawValue: rawValue),
                                           store.supportedSidelightModes.contains(mode) {
                                            store.setSidelightMode(mode)
                                        }
                                    }
                                )) {
                                    if store.sidelightModeNeedsHardwareRecovery,
                                       let current = store.lightingStates.first?.sidelight.mode {
                                        Text(language.text("需要恢复", "Restore required")).tag(current)
                                    }
                                    ForEach(store.supportedSidelightModes) { mode in
                                        Text(localizedSidelightMode(mode, language)).tag(mode.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)
                            }
                            HStack(spacing: 12) {
                                Text(language.text("常亮颜色", "Static color"))
                                    .font(.subheadline.weight(.medium))
                                ForEach(backlightColors, id: \.hex) { item in
                                    Button {
                                        store.setSidelightStaticColor(hex: item.hex)
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: item.hex))
                                            .frame(width: 24, height: 24)
                                            .overlay(Circle().stroke(Color.primary.opacity(0.16)))
                                    }
                                    .buttonStyle(.plain)
                                    .help(language.text("侧灯 · \(item.name)", "Side light · \(localizedColorName(item.name, language))"))
                                }
                            }
                    }
                    .disabled(!store.lightingAvailable || store.lightingBusy || !store.fullLightingControlSupported)
                }
            }

            HStack(spacing: 8) {
                if store.lightingBusy { ProgressView().controlSize(.small) }
                Image(systemName: store.lightingConnection?.isWireless == true ? "antenna.radiowaves.left.and.right" : "cable.connector")
                Text(store.lightingBusy ? language.text("正在应用灯光…", "Applying lighting…") : lightingConnectionHint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var lightingStatusText: String {
        guard let connection = store.lightingConnection else { return language.text("需要灯光通道", "Lighting channel required") }
        return store.lightingAvailable
            ? language.text("\(connection.displayName) 已连接", "\(localizedLightingConnection(connection, language)) connected")
            : language.text("\(connection.displayName) 待响应", "\(localizedLightingConnection(connection, language)) waiting for response")
    }

    private var lightingConnectionHint: String {
        if !store.lightingAvailable { return language.runtimeText(store.lightingMessage) }
        switch store.lightingConnection {
        case .twoPointFourGHzReceiver:
            return language.text("Agent 实体键状态正通过 2.4G 接收器同步；\(store.secondaryLightingZoneName)保持用户设置。", "Agent key status is syncing over the 2.4G receiver; \(localizedSecondaryLightingZoneName(store.secondaryLightingZoneName, language)) keeps your settings.")
        case .usbCable:
            return language.text("Agent 实体键状态正通过 USB-C 同步；\(store.secondaryLightingZoneName)保持用户设置。", "Agent key status is syncing over USB-C; \(localizedSecondaryLightingZoneName(store.secondaryLightingZoneName, language)) keeps your settings.")
        case nil:
            if store.devices.contains(where: { $0.isRecognized && $0.transports.contains(.bluetooth) }) {
                return language.text("蓝牙按键可用，但当前固件没有实时状态灯通道；请使用 USB-C 或 2.4G。", "Bluetooth keys are available, but this firmware has no live status-light channel. Use USB-C or 2.4G.")
            }
            return language.text("实时状态灯需要 USB-C，或支持新协议的 2.4G 接收器。", "Live status lights require USB-C or a 2.4G receiver that supports the new protocol.")
        }
    }

    private var sleepDurationOptions: [Int] {
        var values = [3, 6, 10, 20, 30, 60]
        if let current = store.sleepConfiguration?.autoSleepAfterMinutes,
           !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values + [0]
    }
}

/// Six stable Agent slots; labels and firmware D8 positions follow the user's
/// current physical key bindings.
struct SixTaskStatusRow: View {
    @Environment(\.interfaceLanguage) private var language
    let tasks: [CodexTaskLightSnapshot]
    let palette: CodexTaskLightPalette
    let keyLabels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<CodexDesktopStatusObserver.maximumTaskCount, id: \.self) { index in
                    let snapshot = index < tasks.count && tasks[index].threadID != nil ? tasks[index] : nil
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(snapshot.map { Color(hex: palette.colorHex(for: $0.state)) } ?? Color.primary.opacity(0.08))
                            .frame(height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12))
                            )
                            .shadow(
                                color: snapshot.map { Color(hex: palette.colorHex(for: $0.state)).opacity(0.35) } ?? .clear,
                                radius: 5
                            )
                        Text(index < keyLabels.count ? keyLabels[index] : "—")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .help(snapshot.map { language.text("任务 \(index + 1)：\(localizedTaskLightState($0.state, language))", "Task \(index + 1): \(localizedTaskLightState($0.state, language))") } ?? language.text("任务 \(index + 1)：未分配", "Task \(index + 1): Unassigned"))
                }
            }
            Text(language.text("六个 Agent 键按当前来源模式绑定；改键后状态灯会跟随实体位置", "Six Agent keys follow the selected source mode; status lights follow their physical locations after remapping."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TaskLightColorEditor: View {
    @Environment(\.interfaceLanguage) private var language
    let state: CodexTaskLightState
    let hex: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: hex) },
                    set: { color in
                        if let value = color.rgbHex { onChange(value) }
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            Text(shortLightName(state, language))
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: BridgeStore
    @Environment(\.interfaceLanguage) private var language
    @Environment(\.interfaceLanguageSelection) private var languageSelection
    @State private var showRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: language.text("设置", "Settings"), subtitle: language.text("只保留运行所需的关键设置", "Essential settings for everyday use"))

            PremiumCard {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeading(icon: "gearshape", title: language.text("通用", "General"), subtitle: localizedModelName(store.currentModelName, language))
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text("界面语言", "Interface Language"))
                                .font(.subheadline.weight(.medium))
                            Text(language.text("切换后立即应用并自动保存", "Applies immediately and is saved automatically"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(language.text("界面语言", "Interface Language"), selection: languageSelection) {
                            ForEach(InterfaceLanguage.allCases) { option in
                                Text(option.nativeName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding(.vertical, 13)
                    Divider()
                    SettingsValueRow(
                        title: language.text("连接状态", "Connection"),
                        value: store.currentDevice == nil ? language.text("未连接", "Not connected") : deviceConnectionText(store.currentDevice, language),
                        good: store.currentDevice != nil,
                        buttonTitle: language.text("刷新", "Refresh"),
                        action: { store.deviceManager.refresh() }
                    )
                    Divider()
                    SettingsValueRow(
                        title: language.text("型号能力", "Model capabilities"),
                        value: localizedCapabilitySummary(store.currentCapabilitySummary, language),
                        good: store.currentDevice != nil,
                        buttonTitle: nil,
                        action: nil
                    )
                    Divider()
                    SettingsValueRow(
                        title: language.text("Codex 控制", "Codex control"),
                        value: store.configuration.enabled ? language.text("已开启", "On") : language.text("已暂停", "Paused"),
                        good: store.configuration.enabled,
                        buttonTitle: store.configuration.enabled
                            ? (store.currentHardwareProfileNeedsInstallation
                                ? language.text("配置", "Configure")
                                : (store.installedHardwareProfileIsCurrent ? language.text("停止并恢复", "Stop and Restore") : language.text("停止", "Stop")))
                            : language.text("启用", "Enable"),
                        action: {
                            if store.configuration.enabled && !store.currentHardwareProfileNeedsInstallation {
                                store.disable()
                            } else {
                                store.oneClickEnable()
                            }
                        }
                    )
                    Divider()
                    HStack {
                        Text(language.text("登录时自动启动", "Launch at Login")).font(.subheadline.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.configuration.launchAtLogin },
                            set: { store.setLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 13)
                }
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeading(icon: "lock.shield", title: language.text("系统权限", "System permissions"), subtitle: language.text("两项权限缺一不可", "Both permissions are required"))
                    PermissionSettingRow(
                        icon: "keyboard",
                        title: language.text("输入监控", "Input Monitoring"),
                        detail: language.text("读取键盘专用控制键，不记录普通文字输入", "Reads dedicated keyboard controls and never records normal text input"),
                        granted: store.inputMonitoringGranted,
                        action: store.requestInputMonitoring
                    )
                    Divider().padding(.leading, 46)
                    PermissionSettingRow(
                        icon: "hand.point.up.left",
                        title: language.text("辅助功能", "Accessibility"),
                        detail: language.text("把控制动作发送到当前 Codex 窗口", "Sends control actions to the current Codex window"),
                        granted: store.accessibilityGranted,
                        action: store.requestAccessibility
                    )
                }
            }

            PremiumCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider()
                        SettingsValueRow(
                            title: language.text("Codex 控制快捷键", "Codex control shortcuts"),
                            value: store.codexDesktopKeybindingsInstalled ? (store.codexRestartRequired ? language.text("需要重启 Codex", "Restart Codex") : language.text("已就绪", "Ready")) : language.text("需要修复", "Repair required"),
                            good: store.codexDesktopKeybindingsInstalled && !store.codexRestartRequired,
                            buttonTitle: store.codexDesktopKeybindingsInstalled && !store.codexRestartRequired ? language.text("重新安装", "Reinstall") : language.text("修复", "Repair"),
                            action: store.installCodexDesktopBindings
                        )
                        Divider()
                        HStack {
                            Button(language.text("重新显示快速设置", "Show Quick Setup")) { store.showOnboarding = true }
                            Button(language.text("恢复首次灯光", "Restore Initial Lighting")) { store.restoreUserLighting() }
                            Spacer()
                            Button(language.text("恢复键盘原始设置", "Restore Original Keyboard Settings"), role: .destructive) {
                                showRestoreConfirmation = true
                            }
                            .disabled(store.hardwareProfileBusy)
                        }
                        Text(language.text("恢复原始设置需要使用 USB-C 连接键盘。", "Restoring original settings requires a USB-C connection."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                    .padding(.top, 12)
                } label: {
                    Text(language.text("高级操作", "Advanced")).font(.headline)
                }
            }

            HStack(spacing: 12) {
                ProductLogo(size: 40, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text("N Agent Bridge \(appVersion)")
                        .font(.caption.weight(.semibold))
                    Text(language.text("独立第三方工具，与 OpenAI、NuPhy 无隶属关系。", "Independent third-party tool; not affiliated with OpenAI or NuPhy."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .alert(language.text("恢复键盘原始设置？", "Restore original keyboard settings?"), isPresented: $showRestoreConfirmation) {
            Button(language.text("取消", "Cancel"), role: .cancel) {}
            Button(language.text("恢复", "Restore"), role: .destructive) { store.restoreOriginalConfiguration() }
        } message: {
            Text(language.text("这会关闭 Codex 控制，逐字节恢复首次配置前的键位，并在完整回读成功后提示你可以拔线。", "This turns off Codex control, restores the original keymap byte for byte, and confirms when verification is complete."))
        }
    }
}

private struct PermissionSettingRow: View {
    @Environment(\.interfaceLanguage) private var language
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            IconSquare(icon: icon, color: granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? language.text("已允许", "Allowed") : language.text("需要允许", "Required"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(granted ? .green : .orange)
            Button(granted ? language.text("刷新", "Refresh") : language.text("打开设置", "Open Settings"), action: action)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 13)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    let good: Bool
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(good ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(value).font(.caption).foregroundStyle(.secondary)
            }
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 13)
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProductLogo: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct PremiumCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.hairline)
            )
    }
}

private struct CardHeading: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(icon: icon, color: .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 12)
    }
}

private struct IconSquare: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ReadinessRow: View {
    let icon: String
    let title: String
    let value: String
    let ready: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ready ? Color.green : Color.secondary)
                .frame(width: 32)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(ready ? Color.secondary : Color.orange)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 15)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color
    var dark = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(dark ? Color.white.opacity(0.88) : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            dark ? Color.white.opacity(0.1) : AppPalette.softFill,
            in: Capsule()
        )
    }
}

private struct InlineNotice: View {
    let icon: String
    let title: String
    let text: String
    let color: Color
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 13) {
            IconSquare(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(color.opacity(0.16))
        )
    }
}

private enum AppPalette {
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let softFill = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.075)
}

private let backlightColors: [(hex: String, name: String)] = [
    ("#168BFF", "蓝色"),
    ("#30D158", "绿色"),
    ("#FF9F0A", "橙色"),
    ("#FF453A", "红色"),
    ("#BF5AF2", "紫色"),
    ("#FFFFFF", "白色")
]

private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.14.0"
}

private func deviceConnectionText(_ device: DeviceSnapshot?, _ language: InterfaceLanguage) -> String {
    guard let transports = device?.transports else { return language.text("未连接", "Not connected") }
    if transports.contains(.usb) && transports.contains(.bluetooth) { return language.text("USB-C + 蓝牙", "USB-C + Bluetooth") }
    if transports.contains(.usb) { return "USB-C" }
    if transports.contains(.bluetooth) { return language.text("蓝牙", "Bluetooth") }
    return language.text("已连接", "Connected")
}

private func shortLightName(_ state: CodexTaskLightState, _ language: InterfaceLanguage) -> String {
    switch state {
    case .idle: return language.text("空闲", "Idle")
    case .reasoning: return language.text("思考", "Thinking")
    case .complete: return language.text("完成", "Complete")
    case .waitingForConfirmation: return language.text("确认", "Confirmation")
    case .error: return language.text("报错", "Error")
    }
}

private func localizedTaskLightState(_ state: CodexTaskLightState, _ language: InterfaceLanguage) -> String {
    switch state {
    case .idle: return language.text("空闲", "Idle")
    case .reasoning: return language.text("正在思考 / 推理", "Thinking / Reasoning")
    case .complete: return language.text("任务完成", "Task Complete")
    case .waitingForConfirmation: return language.text("需要确认", "Confirmation Required")
    case .error: return language.text("报错", "Error")
    }
}

private func localizedAgentSourceMode(_ mode: CodexAgentSourceMode, _ language: InterfaceLanguage) -> String {
    switch mode {
    case .recent: return language.text("最近对话", "Recent Conversations")
    case .pinned: return language.text("置顶对话", "Pinned Conversations")
    case .priority: return language.text("优先对话", "Priority Conversations")
    case .custom: return language.text("自定义分配", "Custom Assignments")
    }
}

private func localizedAgentSourceDetail(_ mode: CodexAgentSourceMode, _ language: InterfaceLanguage) -> String {
    switch mode {
    case .recent: return language.text("跟随最近更新的六个对话；按键始终打开灯光当前对应的对话。", "Follows the six most recently updated conversations; each key opens the conversation shown by its light.")
    case .pinned: return language.text("跟随 Codex 置顶列表中的前六个对话，不受最近活动重新排序影响。", "Follows the first six pinned Codex conversations without reordering by recent activity.")
    case .priority: return language.text("需要确认、未读和正在工作的对话优先，其余按最近活动排序。", "Prioritizes conversations needing confirmation, unread conversations, and active work; the rest follow recent activity.")
    case .custom: return language.text("每颗 Agent 键固定绑定一个对话；空键按下后会新建并自动绑定。", "Each Agent key is permanently bound to one conversation; pressing an empty key creates and binds a new one.")
    }
}

private func localizedBridgeAction(_ action: BridgeAction, _ language: InterfaceLanguage) -> String {
    let english: String
    switch action {
    case .agent1: english = "Codex Task 1"
    case .agent2: english = "Codex Task 2"
    case .agent3: english = "Codex Task 3"
    case .agent4: english = "Codex Task 4"
    case .agent5: english = "Codex Task 5"
    case .agent6: english = "Codex Task 6"
    case .quickAction: english = "Toggle Fast Mode"
    case .approve: english = "Approve"
    case .decline: english = "Decline"
    case .newChat: english = "New Task"
    case .pushToTalk: english = "Push to Talk"
    case .send: english = "Send"
    case .stop: english = "Stop"
    case .continueTask: english = "Continue"
    case .continueInNewChat: english = "Continue in New Task"
    case .reviewChanges: english = "Review Changes"
    case .openCode: english = "Open Code"
    case .openTerminal: english = "Open Terminal"
    case .runTests: english = "Run Tests"
    case .fastMode: english = "Fast Mode"
    case .planMode: english = "Plan Mode"
    case .historyForward: english = "History Forward"
    case .historyBack: english = "History Back"
    case .showHideSidebar: english = "Show/Hide Sidebar"
    case .workflowUp: english = "Workflow Up"
    case .workflowRight: english = "Workflow Right"
    case .workflowDown: english = "Workflow Down"
    case .workflowLeft: english = "Workflow Left"
    case .confirm: english = "Confirm"
    case .cancel: english = "Back/Cancel"
    case .toggleCodexMode: english = "Toggle Codex Mode"
    case .noAction: english = "No Action"
    }
    return language.text(action.displayName, english)
}

private func localizedReasoningControlName(_ name: String, _ language: InterfaceLanguage) -> String {
    if name == "触控条" { return language.text(name, "Touch Bar") }
    return language.text(name, "Knob")
}

private func localizedKnobText(_ text: String, _ language: InterfaceLanguage) -> String {
    let values = [
        "向左旋转": "Turn Left", "降低推理深度": "Reduce reasoning depth",
        "按下旋钮": "Press Knob", "打开模型与推理": "Open model and reasoning",
        "向右旋转": "Turn Right", "提高推理深度": "Increase reasoning depth"
    ]
    return language.text(text, values[text] ?? text)
}

private func localizedBacklightMode(_ mode: Air75BacklightMode, _ language: InterfaceLanguage) -> String {
    let values: [Air75BacklightMode: String] = [
        .spectrum: "Spectrum", .gradient: "Gradient", .staticColor: "Static",
        .breathing: "Breathing", .flowers: "Blossom", .wave: "Wave",
        .verticalWave: "Vertical Wave", .fountain: "Fountain", .galaxy: "Galaxy",
        .rotation: "Rotation", .ripple: "Ripple", .singlePoint: "Single-Key Trigger",
        .grid: "Grid", .flowing: "Flow", .rain: "Rain", .waveBand: "Light Band",
        .gaming: "Gaming", .identify: "Identify", .windmill: "Windmill",
        .diagonal: "Diagonal", .signalIndicator: "Indicator"
    ]
    return language.text(mode.displayName, values[mode] ?? mode.displayName)
}

private func localizedSidelightMode(_ mode: Air75SidelightMode, _ language: InterfaceLanguage) -> String {
    let values: [Air75SidelightMode: String] = [
        .flowing: "Flow", .neon: "Neon", .staticColor: "Static",
        .breathing: "Breathing", .rhythm: "Rhythm"
    ]
    return language.text(mode.displayName, values[mode] ?? mode.displayName)
}

private func localizedColorName(_ name: String, _ language: InterfaceLanguage) -> String {
    let values = ["蓝色": "Blue", "绿色": "Green", "橙色": "Orange", "红色": "Red", "紫色": "Purple", "白色": "White"]
    return language.text(name, values[name] ?? name)
}

private func localizedLightingConnection(_ connection: KeyboardLightingConnection, _ language: InterfaceLanguage) -> String {
    switch connection {
    case .usbCable: return "USB-C"
    case .twoPointFourGHzReceiver: return language.text("2.4G 接收器", "2.4G Receiver")
    }
}

private func localizedSecondaryLightingZoneName(_ name: String, _ language: InterfaceLanguage) -> String {
    language.text(name, "Standard side-light effect")
}

private func localizedCapabilitySummary(_ summary: String, _ language: InterfaceLanguage) -> String {
    guard language == .english else { return summary }
    if summary == "等待识别型号" { return "Waiting to identify model" }
    if summary == "完整硬件控制" { return "Full hardware control" }
    if summary.contains("状态灯已验证") { return "Keys, knob, and Agent status lights verified" }
    if summary.contains("硬件控制已配置") { return "Function keys and knob configured · lighting pending validation" }
    if summary.contains("可配置 F 区") { return "Function keys and knob can be configured · lighting pending validation" }
    return "Safe software mode · lighting pending hardware validation"
}

private func localizedModelName(_ name: String, _ language: InterfaceLanguage) -> String {
    name == "支持的 NuPhy 键盘" ? language.text(name, "Supported NuPhy Keyboard") : name
}
