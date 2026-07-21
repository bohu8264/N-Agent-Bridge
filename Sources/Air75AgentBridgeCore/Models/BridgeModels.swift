import Foundation

public enum ConnectionTransport: String, Codable, CaseIterable, Sendable {
    case usb = "USB"
    case bluetooth = "Bluetooth"
    case unknown = "Unknown"
}

public enum MappingMode: String, Codable, CaseIterable, Sendable {
    case hardwareProfile = "已写入键盘"
    case runtime = "软件实时映射"
    case unavailable = "未启用"
}

public enum CapabilityState: String, Codable, Sendable {
    case verified
    case available
    case unavailable
    case blocked
    case unknown
}

public enum BackendKind: String, Codable, CaseIterable, Sendable {
    case codex = "Codex"
    case claudeCode = "Claude Code"
}

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case noAssignment
    case idle
    case thinking
    case running
    case waitingForInput
    case waitingForApproval
    case complete
    case error
    case stopped

    public var displayName: String {
        switch self {
        case .noAssignment: return "未分配"
        case .idle: return "空闲"
        case .thinking: return "思考中"
        case .running: return "运行中"
        case .waitingForInput: return "等待输入"
        case .waitingForApproval: return "等待批准"
        case .complete: return "已完成"
        case .error: return "错误"
        case .stopped: return "已停止"
        }
    }
}

public enum ReasoningLevel: String, Codable, CaseIterable, Sendable {
    case minimal, low, medium, high, xhigh

    public mutating func step(_ delta: Int) {
        let values = Self.allCases
        guard let index = values.firstIndex(of: self) else { return }
        self = values[min(max(index + delta, 0), values.count - 1)]
    }
}

public enum KnobMode: String, Codable, CaseIterable, Sendable {
    case contextAware
    case reasoning
    case agentSwitch
    case composerNavigation
    case custom
}

/// Mirrors the four Agent-key source modes exposed by Codex Micro. Thread
/// identity, rather than sidebar position, is the stable unit in every mode.
public enum CodexAgentSourceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case recent
    case pinned
    case priority
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .recent: return "最近对话"
        case .pinned: return "置顶对话"
        case .priority: return "优先对话"
        case .custom: return "自定义分配"
        }
    }

    public var detail: String {
        switch self {
        case .recent: return "跟随最近更新的六个对话；按键始终打开灯光当前对应的对话。"
        case .pinned: return "跟随 Codex 置顶列表中的前六个对话，不受最近活动重新排序影响。"
        case .priority: return "需要确认、未读和正在工作的对话优先，其余按最近活动排序。"
        case .custom: return "每颗 Agent 键固定绑定一个对话；空键按下后会新建并自动绑定。"
        }
    }
}

public enum BridgeAction: String, Codable, CaseIterable, Sendable {
    case agent1, agent2, agent3, agent4, agent5, agent6
    case quickAction, approve, decline, newChat, pushToTalk, send
    case stop, continueTask, continueInNewChat, reviewChanges
    case openCode, openTerminal, runTests, fastMode, planMode
    case historyForward, historyBack, showHideSidebar
    case workflowUp, workflowRight, workflowDown, workflowLeft
    case confirm, cancel, toggleCodexMode, noAction

    public var displayName: String {
        switch self {
        case .agent1: return "Codex 任务 1"
        case .agent2: return "Codex 任务 2"
        case .agent3: return "Codex 任务 3"
        case .agent4: return "Codex 任务 4"
        case .agent5: return "Codex 任务 5"
        case .agent6: return "Codex 任务 6"
        case .quickAction: return "切换 Fast Mode"
        case .approve: return "批准"
        case .decline: return "拒绝"
        case .newChat: return "新建任务"
        case .pushToTalk: return "按住说话"
        case .send: return "发送"
        case .stop: return "停止"
        case .continueTask: return "继续"
        case .continueInNewChat: return "在新任务中继续"
        case .reviewChanges: return "审查更改"
        case .openCode: return "打开代码"
        case .openTerminal: return "打开终端"
        case .runTests: return "运行测试"
        case .fastMode: return "Fast Mode"
        case .planMode: return "Plan Mode"
        case .historyForward: return "历史前进"
        case .historyBack: return "历史后退"
        case .showHideSidebar: return "显示/隐藏侧栏"
        case .workflowUp: return "工作流向上"
        case .workflowRight: return "工作流向右"
        case .workflowDown: return "工作流向下"
        case .workflowLeft: return "工作流向左"
        case .confirm: return "确认"
        case .cancel: return "返回/取消"
        case .toggleCodexMode: return "切换 Codex 模式"
        case .noAction: return "无动作"
        }
    }
}

public struct AgentSlot: Identifiable, Codable, Equatable, Sendable {
    public var id: Int { slotId }
    public var slotId: Int
    public var backend: BackendKind
    public var sessionId: String?
    public var title: String
    public var projectPath: String
    public var state: AgentState
    public var isSelected: Bool
    public var isUnread: Bool
    public var isWaitingForApproval: Bool
    public var hasError: Bool
    public var updatedAt: Date
    public var colorHex: String
    public var customUsage: Int?

    public init(slotId: Int) {
        self.slotId = slotId
        self.backend = .codex
        self.sessionId = nil
        self.title = "Agent \(slotId)"
        self.projectPath = FileManager.default.homeDirectoryForCurrentUser.path
        self.state = .noAssignment
        self.isSelected = slotId == 1
        self.isUnread = false
        self.isWaitingForApproval = false
        self.hasError = false
        self.updatedAt = Date()
        self.colorHex = ["#7AA2F7", "#BB9AF7", "#7DCFFF", "#9ECE6A", "#E0AF68", "#F7768E"][slotId - 1]
        self.customUsage = nil
    }
}

public struct HIDInterfaceSnapshot: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var vendorID: Int
    public var productID: Int
    public var productName: String
    public var manufacturer: String?
    public var serialNumber: String?
    public var transport: ConnectionTransport
    public var usagePage: Int
    public var usage: Int
    public var locationID: Int?
    public var maxInputReportSize: Int?
    public var maxOutputReportSize: Int?
    public var maxFeatureReportSize: Int?
    public var recognitionConfidence: Int
    public var requiresPairingConfirmation: Bool
    public var profileID: String? = nil
    public var modelName: String? = nil
}

public struct DeviceFingerprint: Codable, Hashable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var normalizedProduct: String
    public var normalizedManufacturer: String?
    public var serialNumber: String?
    public var confirmedBluetoothAlias: String?

    public var stableID: String {
        let seed = [String(vendorID), String(productID), normalizedProduct,
                    normalizedManufacturer ?? "", serialNumber ?? "", confirmedBluetoothAlias ?? ""].joined(separator: "|")
        return FNV1a.hash(seed)
    }
}

public struct DeviceSnapshot: Identifiable, Codable, Hashable, Sendable {
    public var id: String { fingerprint.stableID }
    public var fingerprint: DeviceFingerprint
    public var productName: String
    public var manufacturer: String?
    public var serialNumber: String?
    public var transports: Set<ConnectionTransport>
    public var interfaces: [HIDInterfaceSnapshot]
    public var lastSeenAt: Date
    public var isRecognized: Bool
    public var needsBluetoothAssociation: Bool
    public var profileID: String? = nil
    public var modelName: String? = nil
}

public struct HIDEvent: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var timestamp = Date()
    public var deviceID: String
    public var transport: ConnectionTransport
    public var usagePage: Int
    public var usage: Int
    public var value: Int
    public var reportID: Int?

    public init(
        timestamp: Date = Date(),
        deviceID: String,
        transport: ConnectionTransport,
        usagePage: Int,
        usage: Int,
        value: Int,
        reportID: Int? = nil
    ) {
        self.timestamp = timestamp
        self.deviceID = deviceID
        self.transport = transport
        self.usagePage = usagePage
        self.usage = usage
        self.value = value
        self.reportID = reportID
    }

    public var hexDescription: String {
        String(format: "page 0x%04X · usage 0x%04X · value %d", usagePage, usage, value)
    }
}

public struct KeyBinding: Identifiable, Codable, Hashable, Sendable {
    /// IOHID uses this non-key sentinel for an array element whose *value*
    /// contains the currently pressed usage. It must never be persisted as a
    /// binding: the same element changes for every ordinary key press.
    public static let hidArrayUsageSentinel = Int(UInt32.max)

    public var id: String { "\(usagePage):\(usage)" }
    public var usagePage: Int
    public var usage: Int
    public var action: BridgeAction
    /// Firmware signal-light index for this physical key. It is deliberately
    /// stored with the binding so moving an Agent action also moves its light.
    /// Unknown models/locations remain nil until a verified layout is present.
    public var signalLightIndex: Int?

    public init(usagePage: Int, usage: Int, action: BridgeAction, signalLightIndex: Int? = nil) {
        self.usagePage = usagePage
        self.usage = usage
        self.action = action
        self.signalLightIndex = signalLightIndex
    }

    /// Sources that the app can both recognize and isolate with its macOS
    /// event tap. Consumer/media usages and HID array sentinels are excluded.
    public static func isSupportedInputSource(usagePage: Int, usage: Int) -> Bool {
        guard usagePage == 0x07 else { return false }
        switch usage {
        case 0x04...0x31, 0x33...0x63, 0x68...0x73:
            return true
        default:
            return false
        }
    }

    public var isSupportedInputSource: Bool {
        Self.isSupportedInputSource(usagePage: usagePage, usage: usage)
    }

    /// Normalizes keyboard-array reports while learning. For a regular HID
    /// element `usage` is already the key. For the array sentinel the actual
    /// key may be carried in `value`; non-key values such as 0/1 are rejected
    /// so a later discrete F-key event can be learned instead.
    public static func normalizedLearnableUsage(usagePage: Int, usage: Int, value: Int) -> Int? {
        let candidate = usage == hidArrayUsageSentinel ? value : usage
        return isSupportedInputSource(usagePage: usagePage, usage: candidate) ? candidate : nil
    }

    public var displayName: String {
        if usagePage == 0x07 {
            if (0x04...0x1D).contains(usage) {
                return String(UnicodeScalar(usage - 0x04 + 0x41)!)
            }
            if (0x1E...0x26).contains(usage) { return "\(usage - 0x1D)" }
            if usage == 0x27 { return "0" }
            if (0x3A...0x45).contains(usage) { return "F\(usage - 0x39)" }
            if (0x68...0x73).contains(usage) { return "F\(usage - 0x5B)" }
            switch usage {
            case 0x28: return "Return"
            case 0x29: return "Esc"
            case 0x2A: return "Delete"
            case 0x2B: return "Tab"
            case 0x2C: return "空格"
            case 0x2D: return "-"
            case 0x2E: return "="
            case 0x2F: return "["
            case 0x30: return "]"
            case 0x31: return "\\"
            case 0x33: return ";"
            case 0x34: return "'"
            case 0x35: return "`"
            case 0x36: return ","
            case 0x37: return "."
            case 0x38: return "/"
            case 0x39: return "Caps Lock"
            case 0x49: return "Insert"
            case 0x4A: return "Home"
            case 0x4B: return "Page Up"
            case 0x4C: return "向前删除"
            case 0x4D: return "End"
            case 0x4E: return "Page Down"
            case 0x4F: return "→"
            case 0x50: return "←"
            case 0x51: return "↓"
            case 0x52: return "↑"
            default: break
            }
        }
        if usagePage == 0x0C {
            switch usage {
            case 0xE9: return "音量 +"
            case 0xEA: return "音量 −"
            case 0xCD: return "播放/暂停"
            default: break
            }
        }
        return String(format: "P%02X / U%02X", usagePage, usage)
    }
}

public struct LightingCapabilities: Codable, Sendable {
    public var usbSingleKey: CapabilityState = .unknown
    public var usbDynamic: CapabilityState = .unknown
    public var bluetoothSingleKey: CapabilityState = .unknown
    public var bluetoothDynamic: CapabilityState = .unknown
    public var reason: String = "尚未验证 NuPhyIO 或 Vendor HID 灯光协议"

    public init() {}
}

public struct InstalledHardwareProfileState: Codable, Equatable, Sendable {
    public var installed: Bool
    public var backupName: String?
    public var boundFingerprint: DeviceFingerprint?

    public init(installed: Bool = false, backupName: String? = nil,
                boundFingerprint: DeviceFingerprint? = nil) {
        self.installed = installed
        self.backupName = backupName
        self.boundFingerprint = boundFingerprint
    }
}

public struct BridgeConfiguration: Codable, Sendable {
    public var schemaVersion = 13
    public var hasCompletedOnboarding = false
    public var enabled = false
    public var codexModeEnabled = false
    public var mappingMode: MappingMode = .unavailable
    /// `nil` means the value came from a release that could silently leave mapping disabled.
    /// Only an explicit user pause is persisted as `true`.
    public var mappingPausedByUser: Bool?
    public var hardwareProfileInstalled: Bool?
    /// Identifies which model owns the currently installed hardware profile.
    /// Older schema 1-5 values are migrated to the Air75 V3 profile.
    public var hardwareProfileID: String?
    public var hardwareProfileBackupName: String?
    public var boundFingerprint: DeviceFingerprint?
    /// Hardware profiles live on each physical keyboard independently. Keep
    /// one recovery record per model so configuring a Kick75 never discards
    /// the verified Air75 V3 backup (and vice versa). The scalar fields above
    /// remain decode-only compatibility for schema 1-10.
    public var hardwareProfileStates: [String: InstalledHardwareProfileState]?
    public var confirmedBluetoothFingerprint: DeviceFingerprint?
    public var keyBindings: [KeyBinding] = Self.defaultBindings
    /// Optional per-model overrides. `keyBindings` remains the canonical
    /// legacy set so an existing, verified Air75 V3 hardware profile keeps its
    /// exact mapping while another keyboard can use different physical keys.
    public var modelKeyBindings: [String: [KeyBinding]]?
    public var knobMode: KnobMode = .contextAware
    public var reasoningLevel: ReasoningLevel = .medium
    public var fastMode = false
    public var planMode = false
    public var launchAtLogin = false
    public var overlayEnabled = false
    /// Schema 8 keeps this field name for configuration compatibility, but it
    /// now controls only the six Agent-key task indicator lights.
    public var agentLightingEnabled: Bool? = true
    /// The first successful USB-C setup selects the firmware's verified
    /// indicator backlight mode once. Keep this per model so later launches
    /// never overwrite a user's own lighting choice.
    public var indicatorModeInitializedProfileIDs: [String]?
    /// Schema 7 and older continuously replaced the user's sidelight with an
    /// aggregate Codex color. Upgrades restore the earliest hardware backup
    /// once, then leave the sidelight entirely under normal keyboard control.
    public var sidelightRestoredAfterSignalLights: Bool? = true
    /// Optional so schema 1-4 configuration files continue to decode before
    /// migration. Callers should use `resolvedTaskLightPalette`.
    public var taskLightPalette: CodexTaskLightPalette? = .default
    /// Optional for schema 1-8 decoding. Callers use `resolvedAgentSourceMode`.
    public var agentSourceMode: CodexAgentSourceMode? = .recent
    /// Six exact thread IDs, one for each physical Agent action.
    public var customAgentThreadIDs: [String?]?
    /// Legacy fallback for Codex builds that do not expose the ordered
    /// `pinned-thread-ids` field in local desktop state.
    public var pinnedAgentThreadIDs: [String?]?
    public var lighting = LightingCapabilities()

    public init() {}

    public var resolvedTaskLightPalette: CodexTaskLightPalette {
        taskLightPalette ?? .default
    }

    public var resolvedAgentSourceMode: CodexAgentSourceMode {
        agentSourceMode ?? .recent
    }

    public func hasInitializedIndicatorMode(for profileID: String) -> Bool {
        indicatorModeInitializedProfileIDs?.contains(profileID) == true
    }

    public mutating func markIndicatorModeInitialized(for profileID: String) {
        var values = Set(indicatorModeInitializedProfileIDs ?? [])
        values.insert(profileID)
        indicatorModeInitializedProfileIDs = values.sorted()
    }

    public var resolvedCustomAgentThreadIDs: [String?] {
        Array((customAgentThreadIDs ?? []).prefix(6)) + Array(repeating: nil, count: max(0, 6 - (customAgentThreadIDs ?? []).count))
    }

    public var resolvedPinnedAgentThreadIDs: [String?] {
        Array((pinnedAgentThreadIDs ?? []).prefix(6)) + Array(repeating: nil, count: max(0, 6 - (pinnedAgentThreadIDs ?? []).count))
    }

    public static let defaultBindings: [KeyBinding] = {
        let actions: [BridgeAction] = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6,
                                      .quickAction, .approve, .decline, .newChat, .pushToTalk, .send]
        return zip(0x3A...0x45, actions).enumerated().map {
            KeyBinding(usagePage: 0x07, usage: $0.element.0, action: $0.element.1,
                       signalLightIndex: $0.offset + 1)
        }
    }()

    /// The board profile turns the *physical* F1-F12 row into F13-F24. The app's
    /// dedicated event tap consumes their macOS events while Codex mode is on;
    /// the UI continues to label them as physical F1-F12.
    public static let hardwareProfileBindings: [KeyBinding] = {
        let actions: [BridgeAction] = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6,
                                      .quickAction, .approve, .decline, .newChat, .pushToTalk, .send]
        return zip(0x68...0x73, actions).enumerated().map {
            KeyBinding(usagePage: 0x07, usage: $0.element.0, action: $0.element.1,
                       signalLightIndex: $0.offset + 1)
        }
    }()

    /// Converts only the physical F-row source usages. User-learned number,
    /// letter and navigation keys remain unchanged across install/restore.
    public static func bindingsForInstalledHardwareProfile(_ bindings: [KeyBinding]) -> [KeyBinding] {
        bindings.map { binding in
            guard binding.usagePage == 0x07, (0x3A...0x45).contains(binding.usage) else { return binding }
            return KeyBinding(usagePage: binding.usagePage,
                              usage: binding.usage + (0x68 - 0x3A),
                              action: binding.action,
                              signalLightIndex: binding.signalLightIndex)
        }
    }

    public static func bindingsForOriginalHardwareProfile(_ bindings: [KeyBinding]) -> [KeyBinding] {
        bindings.map { binding in
            guard binding.usagePage == 0x07, (0x68...0x73).contains(binding.usage) else { return binding }
            return KeyBinding(usagePage: binding.usagePage,
                              usage: binding.usage - (0x68 - 0x3A),
                              action: binding.action,
                              signalLightIndex: binding.signalLightIndex)
        }
    }

    /// Repairs the exact 0.13.1 first-run corruption observed on another Mac:
    /// Agent 2 was persisted as F15 and Agent 3 as Tab while every remaining
    /// action kept its default position. Treating those two valid HID usages
    /// as intentional customization made the normal F1-F12 -> F13-F24
    /// conversion preserve the broken pair forever. Match the whole action
    /// and usage sequence so genuine user customizations remain untouched.
    public static func repairingKnownCorruptedDefaultLayout(
        _ bindings: [KeyBinding],
        hardwareProfileInstalled: Bool
    ) -> [KeyBinding] {
        guard bindings.count == defaultBindings.count,
              bindings.map(\.usagePage) == Array(repeating: 0x07, count: defaultBindings.count),
              bindings.map(\.action) == defaultBindings.map(\.action) else {
            return bindings
        }
        let usages = bindings.map(\.usage)
        let corruptedOriginal = [0x3A, 0x6A, 0x2B] + Array(0x3D...0x45)
        let corruptedInstalled = [0x68, 0x6A, 0x2B] + Array(0x6B...0x73)
        guard usages == corruptedOriginal || usages == corruptedInstalled else { return bindings }
        return hardwareProfileInstalled ? hardwareProfileBindings : defaultBindings
    }

    public func hardwareProfileState(for profileID: String?) -> InstalledHardwareProfileState? {
        guard let profileID else { return nil }
        if let state = hardwareProfileStates?[profileID] { return state }
        guard hardwareProfileInstalled == true, hardwareProfileID == profileID else { return nil }
        return InstalledHardwareProfileState(
            installed: true,
            backupName: hardwareProfileBackupName,
            boundFingerprint: boundFingerprint
        )
    }

    public func hasInstalledHardwareProfile(for profileID: String?) -> Bool {
        hardwareProfileState(for: profileID)?.installed == true
    }

    public var hasAnyInstalledHardwareProfile: Bool {
        if hardwareProfileStates?.values.contains(where: { $0.installed }) == true { return true }
        return hardwareProfileInstalled == true
    }

    public mutating func setHardwareProfileState(
        _ state: InstalledHardwareProfileState?,
        for profileID: String
    ) {
        var states = hardwareProfileStates ?? [:]
        if let state, state.installed {
            states[profileID] = state
        } else {
            states.removeValue(forKey: profileID)
        }
        hardwareProfileStates = states

        // Keep the legacy fields as a harmless mirror for old diagnostic
        // tools, but never use them to decide another model's restore path.
        if let state, state.installed {
            hardwareProfileInstalled = true
            hardwareProfileID = profileID
            hardwareProfileBackupName = state.backupName
            boundFingerprint = state.boundFingerprint
        } else if hardwareProfileID == profileID {
            if let replacement = states.first(where: { $0.value.installed }) {
                hardwareProfileInstalled = true
                hardwareProfileID = replacement.key
                hardwareProfileBackupName = replacement.value.backupName
                boundFingerprint = replacement.value.boundFingerprint
            } else {
                hardwareProfileInstalled = false
                hardwareProfileID = nil
                hardwareProfileBackupName = nil
                boundFingerprint = nil
            }
        }
    }

    /// Resolves usages for the keyboard that is actually connected. A
    /// detached Air75 V3 can still own an F13-F24 hardware layer; a Kick75 in
    /// software mode must nevertheless use ordinary F1-F12 events.
    public func bindings(for profileID: String?) -> [KeyBinding] {
        let profileInstalled = hasInstalledHardwareProfile(for: profileID)
        if let profileID, let stored = modelKeyBindings?[profileID], !stored.isEmpty {
            return Self.repairingUnsupportedBindings(
                stored,
                hardwareProfileInstalled: profileInstalled
            )
        }
        if profileInstalled {
            if hardwareProfileID == profileID { return keyBindings }
            return Self.bindingsForInstalledHardwareProfile(keyBindings)
        }
        guard hasAnyInstalledHardwareProfile else { return keyBindings }
        return Self.bindingsForOriginalHardwareProfile(keyBindings)
    }

    public mutating func setBindings(_ bindings: [KeyBinding], for profileID: String?) {
        guard let profileID else {
            keyBindings = bindings
            return
        }
        var stored = modelKeyBindings ?? [:]
        stored[profileID] = bindings
        modelKeyBindings = stored
        if hardwareProfileID == profileID { keyBindings = bindings }
    }

    /// Repairs corrupted/unsupported sources one action at a time without
    /// discarding the user's other valid custom bindings. The F-row default is
    /// selected according to the keyboard's actual board-profile state.
    public static func repairingUnsupportedBindings(
        _ bindings: [KeyBinding],
        hardwareProfileInstalled: Bool
    ) -> [KeyBinding] {
        let defaults = hardwareProfileInstalled ? hardwareProfileBindings : defaultBindings
        let fallbackByAction = Dictionary(uniqueKeysWithValues: defaults.map { ($0.action, $0) })
        return bindings.map { binding in
            guard !binding.isSupportedInputSource,
                  let fallback = fallbackByAction[binding.action] else { return binding }
            return fallback
        }
    }
}

public struct DeviceProfile: Codable, Sendable {
    public struct USBIdentity: Codable, Sendable {
        public var vendorID: Int
        public var productID: Int
        public init(vendorID: Int, productID: Int) { self.vendorID = vendorID; self.productID = productID }
    }
    public var schemaVersion: Int
    /// Stable product-family identity. Unlike the display name, this value is
    /// never changed when the UI is renamed.
    public var id: String?
    public var model: String
    public var usbIdentities: [USBIdentity]
    public var bluetoothVendorIDs: [Int]
    public var productAliases: [String]
    public var manufacturerAliases: [String]
    public var allowedUsagePages: [Int]
    public var specialUsages: [Int]
    public var protocolFamily: KeyboardProtocolFamily?
    public var capabilities: KeyboardHardwareCapabilities?

    public init(schemaVersion: Int, model: String, usbIdentities: [USBIdentity], bluetoothVendorIDs: [Int],
                productAliases: [String], manufacturerAliases: [String], allowedUsagePages: [Int], specialUsages: [Int],
                id: String? = nil, protocolFamily: KeyboardProtocolFamily? = nil,
                capabilities: KeyboardHardwareCapabilities? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.model = model
        self.usbIdentities = usbIdentities
        self.bluetoothVendorIDs = bluetoothVendorIDs
        self.productAliases = productAliases
        self.manufacturerAliases = manufacturerAliases
        self.allowedUsagePages = allowedUsagePages
        self.specialUsages = specialUsages
        self.protocolFamily = protocolFamily
        self.capabilities = capabilities
    }

    public var profileID: String {
        id ?? "legacy.\(DeviceFingerprintMatcher.normalize(model))"
    }
}

public enum KeyboardProtocolFamily: String, Codable, Sendable {
    case nuphyS4
    case nuphyEG
    case softwareOnly
    case unknown
}

/// Declarative hardware capabilities. Adding a new NuPhy model starts with a
/// JSON profile; hardware writes stay unavailable until a verified driver ID
/// is registered for that model.
public struct KeyboardHardwareCapabilities: Codable, Equatable, Sendable {
    public var keymapDriverID: String?
    public var lightingDriverID: String?
    public var sleepDriverID: String?
    public var keymapByteCount: Int?
    public var hasKnob: Bool
    public var hasSidelight: Bool
    public var supportsWirelessConfiguration: Bool
    /// Identifies a verified physical-key to D8 signal-light layout.
    public var signalLightLayoutID: String?

    public init(keymapDriverID: String? = nil, lightingDriverID: String? = nil,
                sleepDriverID: String? = nil,
                keymapByteCount: Int? = nil, hasKnob: Bool = false,
                hasSidelight: Bool = false, supportsWirelessConfiguration: Bool = false,
                signalLightLayoutID: String? = nil) {
        self.keymapDriverID = keymapDriverID
        self.lightingDriverID = lightingDriverID
        self.sleepDriverID = sleepDriverID
        self.keymapByteCount = keymapByteCount
        self.hasKnob = hasKnob
        self.hasSidelight = hasSidelight
        self.supportsWirelessConfiguration = supportsWirelessConfiguration
        self.signalLightLayoutID = signalLightLayoutID
    }
}

public enum RecognitionResult: Sendable {
    case recognized(confidence: Int)
    case bluetoothCandidate(confidence: Int)
    case rejected
}

public enum BackendConnectionState: String, Sendable {
    case unavailable, disconnected, connecting, connected, error
}

public struct ApprovalRequest: Identifiable, Sendable {
    public var id: String
    public var method: String
    public var summary: String
    public var receivedAt = Date()
}
