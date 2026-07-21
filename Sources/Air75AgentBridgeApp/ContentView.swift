import Air75AgentBridgeCore
import AppKit
import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview = "概览"
    case controls = "按键"
    case lighting = "灯光"
    case settings = "设置"

    var id: String { rawValue }

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
                .help("显示快速设置")
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
    @Binding var selection: SidebarPage?

    var body: some View {
        VStack(spacing: 0) {
            List(SidebarPage.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.icon)
                    .padding(.vertical, 4)
                    .tag(page)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.currentDevice == nil ? Color.secondary.opacity(0.5) : Color.green)
                        .frame(width: 8, height: 8)
                    Text(store.currentDevice == nil ? "等待 NuPhy 键盘" : "\(store.currentModelName) 已连接")
                        .font(.caption.weight(.semibold))
                }
                Text(store.configuration.enabled ? "Codex 控制已开启" : "Codex 控制已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("版本 \(appVersion)")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProductLogo(size: 64, cornerRadius: 17)
            VStack(alignment: .leading, spacing: 8) {
                Text("连接这台 \(store.bluetoothAssociationCandidate?.modelName ?? "NuPhy 键盘")？")
                    .font(.title.bold())
                Text("确认后，USB 配置会继续在这台蓝牙键盘上使用。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("稍后") { store.bluetoothAssociationCandidate = nil }
                Button("连接") { store.confirmBluetoothAssociation() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 460)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: BridgeStore

    private var usbConnected: Bool {
        store.devices.contains { $0.isRecognized && $0.transports.contains(.usb) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ProductLogo(size: 92, cornerRadius: 24)
                Text("让 NuPhy 键盘直接控制 Codex")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("首次用 USB-C 完成一次设置，之后即可通过蓝牙日常使用。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 34)
            .padding(.bottom, 26)

            VStack(spacing: 0) {
                SetupRow(
                    number: "1",
                    title: "连接受支持的 NuPhy 键盘",
                    detail: usbConnected ? "已通过 USB-C 识别" : "请使用可传输数据的 USB-C 线",
                    complete: usbConnected || store.configuration.hardwareProfileInstalled == true
                )
                Divider().padding(.leading, 58)
                SetupRow(
                    number: "2",
                    title: "允许系统权限",
                    detail: store.inputMonitoringGranted && store.accessibilityGranted ? "两项权限均已完成" : "允许读取专用按键并控制 Codex",
                    complete: store.inputMonitoringGranted && store.accessibilityGranted,
                    buttonTitle: store.inputMonitoringGranted && store.accessibilityGranted ? nil : "打开设置",
                    action: {
                        if !store.inputMonitoringGranted { store.requestInputMonitoring() }
                        else if !store.accessibilityGranted { store.requestAccessibility() }
                    }
                )
                Divider().padding(.leading, 58)
                SetupRow(
                    number: "3",
                    title: "启用 Codex 控制",
                    detail: store.configuration.enabled ? "专用按键与旋钮已经可以使用" : "自动备份并写入当前型号的专用控制层",
                    complete: store.configuration.enabled,
                    buttonTitle: store.configuration.enabled ? nil : "启用",
                    buttonEnabled: usbConnected || store.configuration.hardwareProfileInstalled == true,
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
                    Text("正在安全配置键盘…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 22)
            Divider()
            HStack {
                Text("所有设置都可以稍后在“设置”中完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("进入应用") { store.completeOnboarding() }
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
    let openSettings: () -> Void

    private var controlsReady: Bool {
        store.configuration.mappingMode != .unavailable && store.codexDesktopKeybindingsInstalled
    }

    private var permissionsReady: Bool {
        store.inputMonitoringGranted && store.accessibilityGranted
    }

    private var isReady: Bool {
        store.currentDevice != nil && controlsReady && permissionsReady && store.configuration.enabled
    }

    private var heroTitle: String {
        if store.hardwareProfileBusy { return "正在配置 \(store.currentModelName)" }
        if isReady { return "一切就绪" }
        if store.currentDevice == nil { return "连接键盘，开始使用" }
        return "还差一步即可使用"
    }

    private var heroSubtitle: String {
        if isReady, store.configuration.hardwareProfileInstalled == true {
            return "自定义按键、旋钮与 Agent 状态灯正在与 Codex 协同工作。"
        }
        if isReady { return "自定义按键正在安全的软件模式下控制 Codex；未写入未经验证的键盘固件。" }
        if store.currentDevice == nil { return "打开键盘并连接蓝牙，首次设置请使用 USB-C。" }
        if !permissionsReady { return "完成系统权限后，按键只会控制 Codex。" }
        return "启用控制后，你的工作流会立即生效。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: "概览", subtitle: "键盘与 Codex 的连接状态")

            PremiumCard {
                HStack(spacing: 18) {
                ProductLogo(size: 64, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 9) {
                    StatusPill(
                        text: isReady ? "已连接" : (store.configuration.enabled ? "需要完成设置" : "控制已暂停"),
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
                        if store.configuration.enabled { store.disable() }
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
                        CardHeading(icon: "checkmark.shield", title: "使用状态", subtitle: readinessSummary)
                        ReadinessRow(
                            icon: "keyboard",
                            title: store.currentModelName,
                            value: store.currentDevice == nil ? "未连接" : deviceConnectionText(store.currentDevice),
                            ready: store.currentDevice != nil
                        )
                        Divider().padding(.leading, 44)
                        ReadinessRow(
                            icon: "command",
                            title: "Codex 控制",
                            value: controlsReady ? "已配置" : "需要配置",
                            ready: controlsReady,
                            actionTitle: controlsReady ? nil : "修复",
                            action: { store.installCodexDesktopBindings() }
                        )
                        Divider().padding(.leading, 44)
                        ReadinessRow(
                            icon: "lock.shield",
                            title: "系统权限",
                            value: permissionsReady ? "已允许" : "需要允许",
                            ready: permissionsReady,
                            actionTitle: permissionsReady ? nil : "前往设置",
                            action: openSettings
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .topLeading)
                }

                PremiumCard {
                    VStack(alignment: .leading, spacing: 0) {
                        CardHeading(icon: "lightbulb.led", title: "Codex 状态灯", subtitle: "六个 Agent 实体键分别显示任务状态")
                        HStack(spacing: 15) {
                            Circle()
                                .fill(Color(hex: store.taskLightColorHex(for: store.codexTopTaskLightState)))
                                .frame(width: 42, height: 42)
                                .overlay(Circle().stroke(Color.primary.opacity(0.12)))
                                .shadow(color: Color(hex: store.taskLightColorHex(for: store.codexTopTaskLightState)).opacity(0.45), radius: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.codexTopTaskLightState.displayName)
                                    .font(.title3.bold())
                        Text(!store.signalLightingSupported ? "当前型号等待灯光驱动验证" : (store.configuration.agentLightingEnabled == true ? "状态灯已开启" : "状态灯已关闭"))
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
                            Text("5 种实时状态")
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
                    title: "请重新打开一次 Codex",
                    text: "新的控制快捷键已经安装，重启 Codex 后即可生效。",
                    color: .orange
                )
            }
        }
    }

    private var primaryActionTitle: String {
        if store.configuration.enabled {
            return store.configuration.hardwareProfileInstalled == true ? "停止并恢复键盘" : "停止控制"
        }
        if store.configuration.hardwareProfileInstalled == true { return "启用控制" }
        return "连接并启用"
    }

    private var readinessSummary: String {
        if isReady { return "所有核心功能都已就绪" }
        if !permissionsReady { return "完成权限即可开始" }
        return "正在等待连接或启用"
    }
}

struct ControlsView: View {
    @EnvironmentObject private var store: BridgeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                PageTitle(title: "按键", subtitle: "把 12 个 Codex 动作分配到你顺手的实体键")
                Spacer()
                Button("恢复默认") { store.resetBindingsToPhysicalFunctionKeys() }
                    .buttonStyle(.bordered)
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardHeading(icon: "rectangle.stack", title: "Agent 对话来源", subtitle: "按对话 ID 绑定，不再依赖侧栏位置")
                        Spacer()
                        Picker("对话来源", selection: Binding(
                            get: { store.configuration.resolvedAgentSourceMode },
                            set: { store.setAgentSourceMode($0) }
                        )) {
                            ForEach(CodexAgentSourceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Text(store.configuration.resolvedAgentSourceMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.configuration.resolvedAgentSourceMode == .custom {
                        Divider()
                        Label("按 Codex 左侧栏的项目分组；每颗键绑定其中一个具体对话。",
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
                    ForEach(Array(store.configuration.keyBindings.enumerated()), id: \.offset) { index, binding in
                        KeyActionRow(
                            functionKey: "\(index + 1)",
                            key: binding.displayName,
                            action: binding.action.displayName,
                            learning: store.learningBindingIndex == index,
                            onLearn: { store.beginLearningBinding(index) }
                        )
                    }
                }
            }

            if let learningIndex = store.learningBindingIndex,
               store.configuration.keyBindings.indices.contains(learningIndex) {
                InlineNotice(
                    icon: "keyboard.badge.ellipsis",
                    title: "请按新的实体键",
                    text: "正在设置 \(store.configuration.keyBindings[learningIndex].action.displayName)。支持数字、字母、F 区和导航键；重复键会自动交换。",
                    color: .accentColor,
                    buttonTitle: "取消",
                    action: store.cancelLearningBinding
                )
            } else {
                Text("Codex 控制开启时，自定义键会成为专用控制键，不再同时输入原字符；停止控制后会恢复原本行为。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 14) {
                    CardHeading(icon: "dial.medium", title: "旋钮", subtitle: "调整当前 Codex 的推理深度")
                    HStack(spacing: 12) {
                        KnobAction(icon: "rotate.left", title: "向左旋转", detail: "降低推理深度")
                        KnobAction(icon: "button.programmable", title: "按下旋钮", detail: "打开模型与推理")
                        KnobAction(icon: "rotate.right", title: "向右旋转", detail: "提高推理深度")
                    }
                }
            }

            if !store.codexDesktopKeybindingsInstalled || store.codexRestartRequired {
                InlineNotice(
                    icon: "wrench.and.screwdriver",
                    title: store.codexRestartRequired ? "需要重新打开 Codex" : "Codex 控制需要修复",
                    text: store.codexRestartRequired ? "重启后，F11 与旋钮就会使用新快捷键。" : "重新安装本机控制快捷键，不会改变你的 Codex 数据。",
                    color: .orange,
                    buttonTitle: store.codexRestartRequired ? nil : "立即修复",
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
                    ?? "未命名项目"
            } else {
                key = "projectless"
                name = "其他对话"
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
        return thread.threadID.map { "对话 …\($0.suffix(8))" } ?? "未命名对话"
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
        return "其他对话"
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
        return "对话 …\(id.suffix(8))"
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
                    Label("不分配", systemImage: "checkmark")
                } else {
                    Text("不分配")
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
                    Text(selection.map(projectName) ?? (assignedID == nil ? "未分配" : "原对话"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(selection.map { compactThreadTitle($0, limit: 34) }
                         ?? assignedThreadFallbackTitle(index)
                         ?? "选择对话")
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
        .help(selection.map(normalizedThreadTitle) ?? assignedThreadFallbackTitle(index) ?? "选择一个 Codex 对话")
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
            Button(learning ? "等待…" : "更改", action: onLearn)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                PageTitle(title: "灯光", subtitle: "普通背光与 Codex 实时任务状态灯")
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
                    .help("重新读取灯光")
                }
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        CardHeading(icon: "lightbulb", title: "普通背光", subtitle: "选择你喜欢的键盘灯效")
                        Spacer()
                        Picker("背光灯效", selection: Binding(
                            get: { Air75BacklightMode(rawValue: store.lightingStates.first?.backlight.mode ?? 6) ?? .wave },
                            set: { store.setBacklightMode($0) }
                        )) {
                            ForEach(Air75BacklightMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        Text("常亮颜色")
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
                            .help(item.name)
                        }
                    }

                    Divider()

                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("灯光保持时间")
                                .font(.subheadline.weight(.medium))
                            Text("键盘无操作达到该时间后会熄灯并休眠")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("灯光保持时间", selection: Binding(
                            get: { store.sleepConfiguration?.autoSleepAfterMinutes ?? 0 },
                            set: { store.setKeyboardLightStayOnMinutes($0 == 0 ? nil : $0) }
                        )) {
                            ForEach(sleepDurationOptions, id: \.self) { minutes in
                                Text(minutes == 0 ? "始终亮着" : "\(minutes) 分钟")
                                    .tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .disabled(store.sleepConfiguration == nil)
                    }

                    if store.sleepConfiguration?.autoSleepEnabled == false {
                        Text("始终亮着会明显增加蓝牙和 2.4G 模式下的耗电。")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(!store.lightingAvailable || store.lightingBusy)
            }

            PremiumCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        CardHeading(icon: "bolt.horizontal.circle", title: "Codex 任务状态灯", subtitle: "六个 Agent 实体键分别显示任务，不改变普通侧灯")
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
                                Text("任务汇总 · \(store.codexTopTaskLightState.displayName)")
                                    .font(.headline)
                            }
                            Spacer()
                        }

                        SixTaskStatusRow(tasks: store.codexTasks, palette: store.configuration.resolvedTaskLightPalette,
                                         keyLabels: store.agentKeyLabels)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("状态颜色")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button("恢复默认") { store.resetTaskLightColors() }
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
                            Text("颜色会保存在本机；已验证型号通过 USB-C 或 2.4G 把状态写到 Agent 当前所在实体键。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if store.configuration.agentLightingEnabled == true { Divider() }

                    VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("普通侧灯灯效").font(.subheadline.weight(.medium))
                                Spacer()
                                Picker("侧灯灯效", selection: Binding(
                                    get: { Air75SidelightMode(rawValue: store.lightingStates.first?.sidelight.mode ?? 4) ?? .rhythm },
                                    set: { store.setSidelightMode($0) }
                                )) {
                                    ForEach(Air75SidelightMode.allCases) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)
                            }
                            HStack(spacing: 12) {
                                Text("常亮颜色")
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
                                    .help("侧灯 · \(item.name)")
                                }
                            }
                    }
                    .disabled(!store.lightingAvailable || store.lightingBusy)
                }
            }

            HStack(spacing: 8) {
                if store.lightingBusy { ProgressView().controlSize(.small) }
                Image(systemName: store.lightingConnection?.isWireless == true ? "antenna.radiowaves.left.and.right" : "cable.connector")
                Text(store.lightingBusy ? "正在应用灯光…" : lightingConnectionHint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var lightingStatusText: String {
        guard let connection = store.lightingConnection else { return "需要灯光通道" }
        return store.lightingAvailable
            ? "\(connection.displayName) 已连接"
            : "\(connection.displayName) 待响应"
    }

    private var lightingConnectionHint: String {
        if !store.lightingAvailable { return store.lightingMessage }
        switch store.lightingConnection {
        case .twoPointFourGHzReceiver:
            return "Agent 实体键状态正通过 2.4G 接收器同步；普通侧灯保持用户灯效。"
        case .usbCable:
            return "Agent 实体键状态正通过 USB-C 同步；普通侧灯保持用户灯效。"
        case nil:
            if store.devices.contains(where: { $0.isRecognized && $0.transports.contains(.bluetooth) }) {
                return "蓝牙按键可用，但当前固件没有实时状态灯通道；请使用 USB-C 或 2.4G。"
            }
            return "实时状态灯需要 USB-C，或支持新协议的 2.4G 接收器。"
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
                    .help(snapshot.map { "任务 \(index + 1)：\($0.state.displayName)" } ?? "任务 \(index + 1)：未分配")
                }
            }
            Text("六个 Agent 键按当前来源模式绑定；改键后状态灯会跟随实体位置")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TaskLightColorEditor: View {
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
            Text(shortLightName(state))
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
    @State private var showRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: "设置", subtitle: "只保留运行所需的关键设置")

            PremiumCard {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeading(icon: "gearshape", title: "通用", subtitle: store.currentModelName)
                    SettingsValueRow(
                        title: "连接状态",
                        value: store.currentDevice == nil ? "未连接" : deviceConnectionText(store.currentDevice),
                        good: store.currentDevice != nil,
                        buttonTitle: "刷新",
                        action: { store.deviceManager.refresh() }
                    )
                    Divider()
                    SettingsValueRow(
                        title: "型号能力",
                        value: store.currentCapabilitySummary,
                        good: store.currentDevice != nil,
                        buttonTitle: nil,
                        action: nil
                    )
                    Divider()
                    SettingsValueRow(
                        title: "Codex 控制",
                        value: store.configuration.enabled ? "已开启" : "已暂停",
                        good: store.configuration.enabled,
                        buttonTitle: store.configuration.enabled
                            ? (store.configuration.hardwareProfileInstalled == true ? "停止并恢复" : "停止")
                            : "启用",
                        action: { store.configuration.enabled ? store.disable() : store.oneClickEnable() }
                    )
                    Divider()
                    HStack {
                        Text("登录时自动启动").font(.subheadline.weight(.medium))
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
                    CardHeading(icon: "lock.shield", title: "系统权限", subtitle: "两项权限缺一不可")
                    PermissionSettingRow(
                        icon: "keyboard",
                        title: "输入监控",
                        detail: "读取键盘专用控制键，不记录普通文字输入",
                        granted: store.inputMonitoringGranted,
                        action: store.requestInputMonitoring
                    )
                    Divider().padding(.leading, 46)
                    PermissionSettingRow(
                        icon: "hand.point.up.left",
                        title: "辅助功能",
                        detail: "把控制动作发送到当前 Codex 窗口",
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
                            title: "Codex 控制快捷键",
                            value: store.codexDesktopKeybindingsInstalled ? (store.codexRestartRequired ? "需要重启 Codex" : "已就绪") : "需要修复",
                            good: store.codexDesktopKeybindingsInstalled && !store.codexRestartRequired,
                            buttonTitle: store.codexDesktopKeybindingsInstalled && !store.codexRestartRequired ? "重新安装" : "修复",
                            action: store.installCodexDesktopBindings
                        )
                        Divider()
                        HStack {
                            Button("重新显示快速设置") { store.showOnboarding = true }
                            Button("恢复首次灯光") { store.restoreUserLighting() }
                            Spacer()
                            Button("恢复键盘原始设置", role: .destructive) {
                                showRestoreConfirmation = true
                            }
                            .disabled(store.hardwareProfileBusy)
                        }
                        Text("恢复原始设置需要使用 USB-C 连接键盘。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                    .padding(.top, 12)
                } label: {
                    Text("高级操作").font(.headline)
                }
            }

            HStack(spacing: 12) {
                ProductLogo(size: 40, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text("N Agent Bridge \(appVersion)")
                        .font(.caption.weight(.semibold))
                    Text("独立第三方工具，与 OpenAI、NuPhy 无隶属关系。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .alert("恢复键盘原始设置？", isPresented: $showRestoreConfirmation) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { store.restoreOriginalConfiguration() }
        } message: {
            Text("这会关闭 Codex 控制，逐字节恢复首次配置前的键位，并在完整回读成功后提示你可以拔线。")
        }
    }
}

private struct PermissionSettingRow: View {
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
            Text(granted ? "已允许" : "需要允许")
                .font(.caption.weight(.semibold))
                .foregroundStyle(granted ? .green : .orange)
            Button(granted ? "刷新" : "打开设置", action: action)
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
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.11.7"
}

private func deviceConnectionText(_ device: DeviceSnapshot?) -> String {
    guard let transports = device?.transports else { return "未连接" }
    if transports.contains(.usb) && transports.contains(.bluetooth) { return "USB-C + 蓝牙" }
    if transports.contains(.usb) { return "USB-C" }
    if transports.contains(.bluetooth) { return "蓝牙" }
    return "已连接"
}

private func shortLightName(_ state: CodexTaskLightState) -> String {
    switch state {
    case .idle: return "空闲"
    case .reasoning: return "思考"
    case .complete: return "完成"
    case .waitingForConfirmation: return "确认"
    case .error: return "报错"
    }
}
