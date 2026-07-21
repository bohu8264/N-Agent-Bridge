import Air75AgentBridgeCore
import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class BridgeStore: ObservableObject {
    @Published var configuration: BridgeConfiguration
    @Published var devices: [DeviceSnapshot] = []
    @Published private(set) var activeDeviceID: String?
    @Published var slots: [AgentSlot] = (1...6).map(AgentSlot.init)
    @Published var selectedSlot = 1
    @Published var composer = ""
    @Published var output = ""
    @Published var codexConnection: BackendConnectionState = .disconnected
    @Published var claudeConnection: BackendConnectionState = .disconnected
    @Published var lastMessage = "正在检查受支持的 NuPhy 键盘…"
    @Published var activeApproval: ApprovalRequest?
    @Published var lastBackupURL: URL?
    @Published var bluetoothAssociationCandidate: DeviceSnapshot?
    @Published var inputMonitoringGranted = HIDDeviceManager.checkListenAccess()
    @Published var accessibilityGranted = CodexDesktopRelay.accessibilityGranted
    @Published var dedicatedEventSuppressionActive = false
    @Published var showOnboarding = true
    @Published var learningBindingIndex: Int?
    @Published var lightingStates: [Air75LightingState] = []
    @Published var lightingFirmware = "未读取"
    @Published var lightingMessage = "请用 USB-C 连接后检测" {
        didSet { UserDefaults.standard.set(lightingMessage, forKey: "LightingMessage") }
    }
    @Published var lightingBusy = false
    @Published var lightingAvailable = false {
        didSet { UserDefaults.standard.set(lightingAvailable, forKey: "LightingAvailable") }
    }
    @Published var lightingConnection: KeyboardLightingConnection? {
        didSet {
            UserDefaults.standard.set(
                lightingConnection?.rawValue ?? "none",
                forKey: "LightingConnection"
            )
        }
    }
    @Published var sleepConfiguration: KeyboardSleepConfiguration?
    @Published var hardwareProfileBusy = false
    @Published var hardwareProfileMessage = "尚未写入键盘专用层"
    @Published var lastHIDEvent = "尚未收到实体功能键事件"
    @Published var codexDesktopKeybindingsInstalled = false
    @Published var codexRestartRequired = false
    @Published var codexTopTaskLightState: CodexTaskLightState = .idle
    @Published var codexTopTaskID: String?
    @Published var codexTasks: [CodexTaskLightSnapshot] = []
    @Published var codexThreadCandidates: [CodexTaskLightSnapshot] = []

    let configurationStore = ConfigurationStore()
    let profileRegistry: DeviceProfileRegistry
    let deviceManager: HIDDeviceManager
    let mappingEngine: MappingEngine
    let codex = CodexAppServerBackend()
    let claude = ClaudeCodeBackend()
    let overlay = OverlayPresenter()
    let codexKeybindingInstaller = CodexKeybindingInstaller()
    let codexDesktopRelay = CodexDesktopRelay()
    let codexDesktopStatusObserver = CodexDesktopStatusObserver()
    let codexDesktopTitleObserver = CodexDesktopTitleObserver()
    let codexDesktopConfirmationObserver = CodexDesktopConfirmationObserver()
    let dedicatedKeyEventSuppressor = DedicatedKeyEventSuppressor()

    private var cancellables = Set<AnyCancellable>()
    private var originalLightingStates: [Air75LightingState]?
    private var userSignalLightsByIndex: [UInt8: Air75SignalLight] = [:]
    private var managedSignalLightIndices = Set(Air75V3LightingController.taskSignalLightIndices)
    private var lastAgentSignalLights: [Air75SignalLight]?
    private var failedAgentSignalLights: [Air75SignalLight]?
    private var lastAgentSignalWriteAt: Date?
    private var lastAgentSignalAttemptAt: Date?
    private var lastKeyboardActivityAt = Date()
    private var pendingLearningEvent: HIDEvent?
    private var wirelessLightingRetryTask: Task<Void, Never>?
    private var lightingRefreshRetryTask: Task<Void, Never>?
    private var lightingRefreshFailureCount = 0
    private var agentSignalRetryTask: Task<Void, Never>?
    private var agentSignalRetryCount = 0
    private var hardwareProfileVerificationRetryTask: Task<Void, Never>?
    private var hardwareProfileVerificationAttempts: [String: Int] = [:]
    private var lastAgentPress: (slot: Int, threadID: String?, date: Date)?
    private var pendingCustomSlot: (index: Int, knownThreadIDs: Set<String>, expiresAt: Date)?
    private var verifiedHardwareProfileDeviceIDs = Set<String>()
    private var hardwareProfileVerificationFailures = Set<String>()

    init() {
        let loaded = configurationStore.load()
        configuration = loaded
        hardwareProfileMessage = loaded.hasAnyInstalledHardwareProfile
            ? "已配置键盘的专用层均已在实机完整回读确认；物理 F1–F12 与推理控制可随蓝牙使用"
            : "尚未写入键盘专用层"
        showOnboarding = !loaded.hasCompletedOnboarding
        let registry = DeviceProfileRegistry.loadBundled()
        profileRegistry = registry
        deviceManager = HIDDeviceManager(configuration: loaded, registry: registry)
        mappingEngine = MappingEngine(configuration: loaded)
        if loaded.launchAtLogin {
            // Re-register after a product/bundle migration so the login item
            // follows the currently installed, stably signed application.
            try? LaunchAtLoginManager.setEnabled(true)
        }
        if loaded.hasAnyInstalledHardwareProfile,
           let result = try? codexKeybindingInstaller.install() {
            codexDesktopKeybindingsInstalled = true
            codexRestartRequired = result.changed || codexNeedsRestartForKeybindings()
        } else {
            codexDesktopKeybindingsInstalled = codexKeybindingInstaller.isInstalled()
            codexRestartRequired = codexDesktopKeybindingsInstalled && codexNeedsRestartForKeybindings()
        }

        deviceManager.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.devices = devices
                if let activeDeviceID = self.activeDeviceID,
                   !devices.contains(where: { $0.id == activeDeviceID }) {
                    self.activeDeviceID = nil
                }
                self.syncActiveInputConfiguration()
                self.bluetoothAssociationCandidate = devices.first(where: { $0.needsBluetoothAssociation })
                if let first = devices.first {
                    let model = first.modelName ?? first.productName
                    if first.interfaces.contains(where: {
                        $0.vendorID == Air75V3LightingController.vendorID
                            && $0.productID == Air75V3LightingController.dongleProductID
                    }) {
                        self.lastMessage = "\(model) 已通过 2.4G 接收器连接"
                    } else {
                        self.lastMessage = first.transports.contains(.bluetooth)
                            ? "\(model) 已通过蓝牙连接"
                            : "\(model) 已通过 USB-C 连接"
                    }
                } else {
                    self.lastMessage = "等待受支持的 NuPhy 键盘连接"
                }
                self.publishDeviceDiagnostics()
                self.verifyRecordedHardwareProfileIfNeeded()

                // The U1 receiver is physically USB, but it is a distinct
                // 2.4G lighting path. Re-probe whenever the active path
                // changes so stale wired state cannot keep wireless writes
                // disabled after the cable is removed.
                let detectedConnection = self.currentLightingDriver?.detectedConnection()
                let connectionChanged = detectedConnection != self.lightingConnection
                if connectionChanged {
                    self.lightingRefreshRetryTask?.cancel()
                    self.lightingRefreshFailureCount = 0
                    self.lightingConnection = detectedConnection
                    self.lightingAvailable = false
                    self.sleepConfiguration = nil
                    self.lastAgentSignalLights = nil
                }
                if detectedConnection != nil,
                   (connectionChanged || self.lightingStates.isEmpty || !self.lightingAvailable),
                   !self.lightingBusy,
                   !self.hardwareProfileBusy {
                    self.refreshLighting()
                } else if detectedConnection == nil, connectionChanged {
                    self.lightingMessage = devices.contains(where: {
                        $0.isRecognized && $0.transports.contains(.bluetooth)
                    })
                        ? "蓝牙已连接，但当前固件没有实时灯光写入通道；请使用随附的 2.4G 接收器"
                        : "请连接 USB-C，或插入 Air75 V3 的 2.4G 接收器"
                }
            }.store(in: &cancellables)

        deviceManager.eventHandler = { [self] event in
            Task { @MainActor in
                lastHIDEvent = event.hexDescription
                UserDefaults.standard.set(event.hexDescription, forKey: "LastHIDEvent")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "LastHIDEventAt")
                scheduleWirelessLightingRetryIfNeeded()
                if consumeLearningEvent(event) { return }
                mappingEngine.handle(event)
            }
        }
        deviceManager.deviceActivityHandler = { [self] interface in
            Task { @MainActor in
                noteActiveDevice(for: interface)
                noteActiveLightingConnection(for: interface)
                scheduleWirelessLightingRetryIfNeeded()
            }
        }
        mappingEngine.actionHandler = { [self] action, event, phase in
            Task { @MainActor in
                UserDefaults.standard.set(action.rawValue, forKey: "LastBridgeAction")
                UserDefaults.standard.set(phase.rawValue, forKey: "LastBridgeActionPhase")
                perform(action, event: event, phase: phase)
            }
        }
        codex.eventHandler = { [self] event in Task { @MainActor in handle(event, backend: .codex) } }
        claude.eventHandler = { [self] event in Task { @MainActor in handle(event, backend: .claudeCode) } }
        codexDesktopStatusObserver.handler = { [weak self] snapshots in
            Task { @MainActor in self?.applyDesktopTaskSnapshots(snapshots) }
        }
        codexDesktopTitleObserver.handler = { [weak self] titles in
            self?.codexDesktopStatusObserver.setAppServerTitles(titles)
        }
        codexDesktopConfirmationObserver.handler = { [weak self] snapshot in
            self?.codexDesktopStatusObserver.setVisibleConfirmationThreadID(
                snapshot.isWaitingForConfirmation ? snapshot.threadID : nil
            )
            UserDefaults.standard.set(
                snapshot.isWaitingForConfirmation,
                forKey: "CodexVisibleConfirmationWaiting"
            )
            UserDefaults.standard.set(
                snapshot.threadID,
                forKey: "CodexVisibleConfirmationThreadID"
            )
        }
        updateTrackedCodexThreadIDs()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPermissions()
                self?.scheduleAgentLightingResyncAfterWake()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleAgentLightingResyncAfterWake(force: true) }
            .store(in: &cancellables)

        deviceManager.start()
        codexDesktopTitleObserver.start()
        codexDesktopStatusObserver.start()
        codexDesktopConfirmationObserver.start()
        syncDedicatedEventSuppression()
        publishPermissionDiagnostics()
    }

    var currentDevice: DeviceSnapshot? {
        activeDeviceID.flatMap { id in devices.first(where: { $0.id == id && $0.isRecognized }) }
            ?? devices.first(where: { device in
                device.isRecognized && device.interfaces.contains(where: {
                    $0.transport == .usb && $0.productID != Air75V3LightingController.dongleProductID
                })
            })
            ?? devices.first(where: { $0.isRecognized && $0.transports.contains(.bluetooth) })
            ?? devices.first(where: { $0.isRecognized })
    }

    var currentSlot: AgentSlot? { slots.first(where: { $0.slotId == selectedSlot }) }

    var agentKeyLabels: [String] {
        let actions: [BridgeAction] = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6]
        return actions.map { action in
            activeKeyBindings.first(where: { $0.action == action })?.displayName ?? "未设置"
        }
    }

    var activeKeyBindings: [KeyBinding] {
        let bindings = configuration.bindings(for: currentDevice?.profileID)
        let layoutID = currentSignalLightLayoutID
        return bindings.map { binding in
            var resolved = binding
            resolved.signalLightIndex = SignalLightLayout.index(
                layoutID: layoutID,
                usagePage: binding.usagePage,
                usage: binding.usage
            )
            return resolved
        }
    }

    var installedHardwareProfileIsCurrent: Bool {
        configuration.hasInstalledHardwareProfile(for: currentDevice?.profileID)
    }

    var currentHardwareProfileNeedsInstallation: Bool {
        guard let currentProfile = profile(for: currentDevice) else { return false }
        return KeyboardDriverRegistry.keymapDriver(for: currentProfile) != nil
            && (!configuration.hasInstalledHardwareProfile(for: currentProfile.profileID)
                || hardwareProfileVerificationFailures.contains(currentProfile.profileID))
    }

    var currentModelName: String {
        currentDevice?.modelName ?? "支持的 NuPhy 键盘"
    }

    var reasoningControlName: String {
        "旋钮"
    }

    var reasoningControlGestures: [(title: String, detail: String)] {
        return [
            ("向左旋转", "降低推理深度"),
            ("按下旋钮", "打开模型与推理"),
            ("向右旋转", "提高推理深度"),
        ]
    }

    var currentCapabilitySummary: String {
        guard let profile = profile(for: currentDevice) else { return "等待识别型号" }
        if KeyboardDriverRegistry.keymapDriver(for: profile) != nil,
           KeyboardDriverRegistry.lightingDriver(for: profile) != nil {
            return KeyboardDriverRegistry.lightingDriver(for: profile)?.supportsFullLightingControl == true
                ? "完整硬件控制"
                : "按键、\(reasoningControlName)与 Agent 状态灯已验证"
        }
        if KeyboardDriverRegistry.keymapDriver(for: profile) != nil {
            return installedHardwareProfileIsCurrent
                ? "F 区与\(reasoningControlName)硬件控制已配置 · 灯光待验证"
                : "可配置 F 区与\(reasoningControlName)硬件控制 · 灯光待验证"
        }
        return "安全软件模式 · 灯光待实机验证"
    }

    private func profile(for device: DeviceSnapshot?) -> DeviceProfile? {
        profileRegistry.profile(id: device?.profileID)
    }

    /// The U1 receiver also reports USB transport, but it is not the direct
    /// cable path required for first-time keymap backup/install/restore.
    private func hasDirectUSBConfigurationInterface(_ device: DeviceSnapshot) -> Bool {
        device.interfaces.contains {
            $0.transport == .usb
                && $0.productID != Air75V3LightingController.dongleProductID
        }
    }

    private var currentLightingProfile: DeviceProfile? {
        guard let connected = profile(for: currentDevice),
              connected.capabilities?.lightingDriverID != nil else { return nil }
        return connected
    }

    private var currentLightingDriver: (any KeyboardLightingDriver)? {
        KeyboardDriverRegistry.lightingDriver(for: currentLightingProfile)
    }

    var fullLightingControlSupported: Bool {
        currentLightingDriver?.supportsFullLightingControl == true
    }

    var supportedSidelightModes: [Air75SidelightMode] {
        currentLightingDriver?.supportedSidelightModes ?? Air75SidelightMode.allCases
    }

    var supportedBacklightModes: [Air75BacklightMode] {
        currentLightingDriver?.supportedBacklightModes ?? Air75BacklightMode.allCases
    }

    var secondaryLightingZoneName: String {
        "普通侧灯灯效"
    }

    var sidelightModeNeedsHardwareRecovery: Bool {
        guard let rawMode = lightingStates.first?.sidelight.mode else { return false }
        return !supportedSidelightModes.contains(where: { $0.rawValue == rawMode })
    }

    private var currentSleepDriver: (any KeyboardSleepDriver)? {
        KeyboardDriverRegistry.sleepDriver(for: currentLightingProfile)
    }

    private var currentSignalLightLayoutID: String? {
        if currentDevice != nil {
            return profile(for: currentDevice)?.capabilities?.signalLightLayoutID
        }
        return nil
    }

    var signalLightingSupported: Bool {
        currentSignalLightLayoutID != nil && currentLightingDriver != nil
    }

    func oneClickEnable() {
        guard !hardwareProfileBusy else { return }
        // D5/D6 and the keymap controller share the same vendor HID channel.
        // If a connection refresh was already in flight, wait for it instead
        // of allowing first-run keymap and indicator writes to race it.
        if lightingBusy {
            hardwareProfileBusy = true
            hardwareProfileMessage = "正在等待灯光通道完成检测…"
            lastMessage = hardwareProfileMessage
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A full D5 read can make several bounded firmware retries.
                // Wait longer than that read window so clicking Configure
                // during discovery reliably continues instead of timing out
                // just before the lighting transaction releases the channel.
                for _ in 0..<240 where self.lightingBusy {
                    try? await Task.sleep(for: .milliseconds(75))
                }
                self.hardwareProfileBusy = false
                guard !self.lightingBusy else {
                    self.hardwareProfileMessage = "灯光通道仍在忙，请稍后重试"
                    self.lastMessage = self.hardwareProfileMessage
                    return
                }
                self.oneClickEnable()
            }
            return
        }
        guard let device = currentDevice else {
            lastMessage = "请先连接受支持的 NuPhy 键盘"
            return
        }
        let recordedProfileInstalled = configuration.hasInstalledHardwareProfile(for: device.profileID)
        let matchingUSBDevice = (hasDirectUSBConfigurationInterface(device) ? device : nil)
            ?? devices.first(where: {
                $0.isRecognized && hasDirectUSBConfigurationInterface($0)
                    && $0.profileID == device.profileID
            })
        // Wireless use is allowed after a verified board profile was installed.
        // When USB-C is present we deliberately do not trust this saved flag:
        // read and verify the actual keyboard every time, repairing firmware
        // updates or configuration copied from another Mac automatically.
        if recordedProfileInstalled, matchingUSBDevice == nil {
            configuration.enabled = true
            configuration.codexModeEnabled = true
            configuration.mappingPausedByUser = false
            persistConfiguration()
            if !codexDesktopKeybindingsInstalled { installCodexDesktopBindings() }
            lastMessage = inputMonitoringGranted && accessibilityGranted
                ? "\(device.modelName ?? device.productName) 专用层控制已启用"
                : "控制已启用，还需要完成两项系统权限"
            showOverlay("键盘控制已启用", detail: "专用按键现在只控制 Codex")
            return
        }
        guard let usbDevice = matchingUSBDevice else {
            lastMessage = "请先用 USB-C 数据线连接受支持的 NuPhy 键盘"
            showOverlay("需要 USB-C", detail: "首次写入键盘专用层时请连接数据线")
            return
        }
        let targetProfile = profile(for: usbDevice)
        guard let controller = KeyboardDriverRegistry.keymapDriver(for: targetProfile) else {
            configuration.mappingMode = .runtime
            configuration.enabled = true
            configuration.codexModeEnabled = true
            configuration.mappingPausedByUser = false
            let softwareBindings = BridgeConfiguration.bindingsForOriginalHardwareProfile(
                configuration.bindings(for: targetProfile?.profileID)
            )
            configuration.setBindings(softwareBindings, for: targetProfile?.profileID)
            persistConfiguration()
            if !codexDesktopKeybindingsInstalled { installCodexDesktopBindings() }
            lastMessage = "\(usbDevice.modelName ?? usbDevice.productName) 已启用安全的软件按键模式；未向未经实机验证的固件写入配置"
            return
        }
        hardwareProfileBusy = true
        hardwareProfileMessage = "正在读取并备份完整键位表…"
        lastMessage = hardwareProfileMessage
        let configStore = configurationStore
        let currentConfiguration = configuration
        let targetProfileID = controller.profileID
        let currentProfileState = currentConfiguration.hardwareProfileState(for: targetProfileID)
        let targetModelName = usbDevice.modelName ?? usbDevice.productName
        let defaultIndicatorProfiles: Set<String> = ["nuphy.air75-v3"]
        let lightingDriver = KeyboardDriverRegistry.lightingDriver(for: targetProfile)
        let shouldInitializeIndicatorMode = defaultIndicatorProfiles.contains(targetProfileID)
            && !currentConfiguration.hasInitializedIndicatorMode(for: targetProfileID)
            && lightingDriver?.supportsFullLightingControl == true
            && lightingDriver?.supportedBacklightModes.contains(.signalIndicator) == true
        Task {
            var shouldRefreshLightingAfterSetup = false
            do {
                let keybindingInstaller = codexKeybindingInstaller
                let result = try await Task.detached(priority: .userInitiated) { () -> (KeyboardKeymapInstallResult, URL, URL, CodexKeybindingInstallResult, [KeyboardLightingState]?, String?) in
                    let original = try controller.readKeymap()
                    // Validate before creating a backup. Firmware updaters can
                    // leave a NuPhyIO encryption session active, in which case
                    // a correctly sized read contains ciphertext rather than a
                    // restorable key matrix.
                    guard controller.isPlausibleKeymap(original) else {
                        throw Air75KeymapError.encryptedSessionData
                    }
                    let keymapBackup: URL
                    if controller.containsBridgeProfile(original) {
                        guard let recovered = configStore.loadOriginalKeymapBackup(
                            profileID: targetProfileID,
                            expectedByteCount: controller.keymapSize,
                            preferredName: currentProfileState?.backupName,
                            isPlausibleKeymap: controller.isPlausibleKeymap,
                            isBridgeProfile: { controller.containsBridgeProfile($0) }
                        ) else { throw Air75KeymapError.originalBackupNotFound }
                        keymapBackup = recovered.url
                    } else {
                        keymapBackup = try configStore.createKeymapBackup(
                            data: original,
                            note: "N Agent Bridge 写入前逐字节读取的完整原始键位表。",
                            profileID: targetProfileID,
                            deviceFingerprint: usbDevice.fingerprint
                        )
                    }
                    let runtimeBackup = try configStore.createRuntimeBackup(
                        device: usbDevice,
                        configuration: currentConfiguration,
                        note: "写入 \(targetModelName) 专用层前的应用配置与完整 HID 身份。"
                    )
                    let installed = try controller.installBridgeProfile(expectedOriginal: original)
                    let keybindings = try keybindingInstaller.install()
                    var indicatorStates: [KeyboardLightingState]?
                    var indicatorError: String?
                    if shouldInitializeIndicatorMode, let lightingDriver {
                        do {
                            indicatorStates = try lightingDriver.setBacklight(
                                mode: .signalIndicator,
                                brightness: nil,
                                color: nil
                            )
                        } catch {
                            // The board profile is already safely installed.
                            // Report the independent lighting failure without
                            // pretending that the whole setup rolled back.
                            indicatorError = error.localizedDescription
                        }
                    }
                    return (installed, keymapBackup, runtimeBackup, keybindings, indicatorStates, indicatorError)
                }.value
                lastBackupURL = result.1
                configuration.mappingMode = .hardwareProfile
                configuration.enabled = true
                configuration.codexModeEnabled = true
                configuration.mappingPausedByUser = false
                let normalizedBindings = BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
                    self.configuration.bindings(for: targetProfileID),
                    hardwareProfileInstalled: false
                )
                let installedBindings = BridgeConfiguration.bindingsForInstalledHardwareProfile(
                    normalizedBindings
                )
                configuration.setHardwareProfileState(
                    InstalledHardwareProfileState(
                        installed: true,
                        backupName: result.1.lastPathComponent,
                        boundFingerprint: usbDevice.fingerprint
                    ),
                    for: targetProfileID
                )
                hardwareProfileVerificationFailures.remove(targetProfileID)
                configuration.setBindings(installedBindings, for: targetProfileID)
                if let indicatorStates = result.4 {
                    configuration.markIndicatorModeInitialized(for: targetProfileID)
                    lightingStates = indicatorStates
                    lightingConnection = lightingDriver?.detectedConnection()
                    lightingAvailable = true
                } else {
                    shouldRefreshLightingAfterSetup = lightingDriver?.detectedConnection() != nil
                }
                persistConfiguration()
                codexDesktopKeybindingsInstalled = true
                codexRestartRequired = result.3.changed || codexNeedsRestartForKeybindings()
                if let indicatorError = result.5 {
                    hardwareProfileMessage = "F13–F24 已回读确认；指示灯模式设置失败：\(indicatorError)"
                } else if result.4 != nil {
                    hardwareProfileMessage = "F13–F24 已回读确认，背光已进入指示灯模式"
                } else {
                    hardwareProfileMessage = result.0.changedChunkAddresses.isEmpty
                        ? "键盘专用事件与 Codex 命令中继均已验证"
                        : "键盘专用事件已写入，Codex 命令中继已安装"
                }
                lastAgentSignalLights = nil
                failedAgentSignalLights = nil
                if lightingAvailable { syncAgentLighting() }
                if !inputMonitoringGranted || !accessibilityGranted {
                    lastMessage = "硬件已配置；还需在权限页允许输入监控和辅助功能"
                    showOverlay("还差系统权限", detail: "请分别允许输入监控和辅助功能")
                } else {
                    lastMessage = result.3.changed ? "中继已安装：请退出并重新打开一次 Codex" : "已启用：实体键会定向控制当前 Codex"
                    showOverlay("N Agent Bridge 已启用", detail: result.3.changed ? "请重启一次 Codex 后使用" : "专用按键 · 蓝牙可用")
                }
            } catch {
                hardwareProfileMessage = "写入失败：\(error.localizedDescription)"
                lastMessage = hardwareProfileMessage
                showOverlay("启用失败", detail: error.localizedDescription)
            }
            hardwareProfileBusy = false
            if shouldRefreshLightingAfterSetup, !lightingBusy { refreshLighting() }
        }
    }

    func completeOnboarding() {
        configuration.hasCompletedOnboarding = true
        showOnboarding = false
        persistConfiguration()
    }

    func disable() {
        guard !hardwareProfileBusy else { return }
        guard installedHardwareProfileIsCurrent else {
            finishSoftwareDisable(message: "Codex 控制已停止；键盘保持普通行为")
            return
        }
        guard devices.contains(where: {
            $0.isRecognized && hasDirectUSBConfigurationInterface($0)
        }) else {
            lastMessage = "请保持 USB-C 连接并再次点停止；恢复完成后再拔线"
            showOverlay("暂未停止", detail: "需要先恢复键盘原生 F 区，完成后才能安全拔线")
            return
        }
        restoreOriginalConfiguration()
    }

    func restoreOriginalConfiguration() {
        guard !hardwareProfileBusy else { return }
        guard let currentProfileID = currentDevice?.profileID,
              let installedState = configuration.hardwareProfileState(for: currentProfileID),
              installedState.installed,
              let installedProfile = profileRegistry.profile(id: currentProfileID),
              let controller = KeyboardDriverRegistry.keymapDriver(for: installedProfile) else {
            lastMessage = "找不到已安装专用层对应的安全恢复驱动，未执行任何硬件写入"
            return
        }
        guard let usbDevice = devices.first(where: {
            $0.isRecognized && hasDirectUSBConfigurationInterface($0)
                && $0.profileID == controller.profileID
        }) else {
            lastMessage = "恢复原始键位需要先用 USB-C 连接 \(installedProfile.model)"
            return
        }
        guard let selected = configurationStore.loadOriginalKeymapBackup(
            profileID: controller.profileID,
            expectedByteCount: controller.keymapSize,
            preferredName: installedState.backupName,
            isPlausibleKeymap: controller.isPlausibleKeymap,
            isBridgeProfile: { controller.containsBridgeProfile($0) }
        ), let bytes = selected.backup.bytes else {
            lastMessage = "没有找到可验证的原始键位备份；为避免把专用键位当成原始键位，未执行恢复"
            return
        }
        hardwareProfileBusy = true
        hardwareProfileMessage = "正在恢复原始键位并回读校验…"
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) { try controller.restore(bytes) }.value
                configuration.enabled = false
                configuration.codexModeEnabled = false
                configuration.mappingPausedByUser = true
                configuration.mappingMode = .unavailable
                let originalBindings = BridgeConfiguration.bindingsForOriginalHardwareProfile(
                    configuration.bindings(for: controller.profileID)
                )
                configuration.setHardwareProfileState(nil, for: controller.profileID)
                configuration.setBindings(originalBindings, for: controller.profileID)
                persistConfiguration()
                hardwareProfileMessage = "\(usbDevice.modelName ?? usbDevice.productName) 原始键位表已恢复并回读确认"
                lastMessage = "\(hardwareProfileMessage)；现在可以拔掉数据线"
                showOverlay("原始键位已恢复", detail: "键盘系统功能键与音量旋钮已还原")
            } catch {
                hardwareProfileMessage = "恢复失败：\(error.localizedDescription)"
                lastMessage = hardwareProfileMessage
            }
            hardwareProfileBusy = false
        }
    }

    private func finishSoftwareDisable(message: String) {
        configuration.enabled = false
        configuration.codexModeEnabled = false
        configuration.mappingPausedByUser = true
        persistConfiguration()
        overlay.hide()
        lastMessage = message
    }

    func confirmBluetoothAssociation() {
        guard let candidate = bluetoothAssociationCandidate,
              let fingerprint = deviceManager.confirmBluetoothAssociation(candidate) else { return }
        configuration.confirmedBluetoothFingerprint = fingerprint
        deviceManager.configuration = configuration
        persistConfiguration()
        bluetoothAssociationCandidate = nil
        lastMessage = "蓝牙设备已与 USB 配置永久关联"
    }

    func toggleCodexMode() {
        configuration.codexModeEnabled.toggle()
        persistConfiguration()
        showOverlay(configuration.codexModeEnabled ? "Codex 模式已开启" : "Codex 模式已关闭",
                    detail: configuration.mappingMode.rawValue)
    }

    func sendComposer() {
        let prompt = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            showOverlay("Composer 为空", detail: "先在 N Agent Bridge 输入任务或使用按住说话")
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let index = slots.firstIndex(where: { $0.slotId == selectedSlot }) else { return }
        if slots[index].sessionId == nil { slots[index].state = .thinking }
        let backend: AgentBackend = slots[index].backend == .codex ? codex : claude
        backend.send(prompt: prompt, sessionID: slots[index].sessionId,
                     projectPath: slots[index].projectPath,
                     reasoning: configuration.reasoningLevel,
                     fastMode: configuration.fastMode,
                     planMode: configuration.planMode)
        composer = ""
    }

    func createTask(in slotID: Int) {
        guard let index = slots.firstIndex(where: { $0.slotId == slotID }) else { return }
        selectedSlot = slotID
        slots.indices.forEach { slots[$0].isSelected = slots[$0].slotId == slotID }
        let backend: AgentBackend = slots[index].backend == .codex ? codex : claude
        backend.createSession(projectPath: slots[index].projectPath, title: slots[index].title)
        slots[index].state = .thinking
        showOverlay("Agent \(slotID)", detail: "正在创建新任务")
    }

    func selectSlot(_ id: Int, bringForward: Bool = false) {
        selectedSlot = id
        for index in slots.indices {
            slots[index].isSelected = slots[index].slotId == id
            if slots[index].slotId == id { slots[index].isUnread = false }
        }
        if bringForward, let slot = currentSlot {
            NSWorkspace.shared.open(URL(fileURLWithPath: slot.projectPath))
        }
        showOverlay("Agent \(id)", detail: currentSlot?.state.displayName ?? "未分配")
        syncAgentLighting()
    }

    func requestInputMonitoring() {
        _ = deviceManager.requestListenAccess()
        refreshPermissions()
        if !inputMonitoringGranted { openInputMonitoringSettings() }
    }

    func requestAccessibility() {
        _ = CodexDesktopRelay.requestAccessibility()
        refreshPermissions()
        if !accessibilityGranted { openAccessibilitySettings() }
    }

    func refreshPermissions() {
        inputMonitoringGranted = HIDDeviceManager.checkListenAccess()
        accessibilityGranted = CodexDesktopRelay.accessibilityGranted
        deviceManager.restart()
        syncDedicatedEventSuppression()
        publishPermissionDiagnostics()
        if inputMonitoringGranted && accessibilityGranted {
            lastMessage = "键盘监听与 Codex 控制权限均已授权"
        }
    }

    private func publishPermissionDiagnostics() {
        UserDefaults.standard.set(inputMonitoringGranted, forKey: "HIDListenAccessGranted")
        UserDefaults.standard.set(accessibilityGranted, forKey: "AccessibilityGranted")
        UserDefaults.standard.set(Int(deviceManager.managerOpenResult), forKey: "HIDManagerOpenResult")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "HIDPermissionCheckedAt")
    }

    private func openInputMonitoringSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        ]
        let opened = candidates.compactMap(URL.init(string:)).contains { NSWorkspace.shared.open($0) }
        lastMessage = opened
            ? "已打开“输入监控”：请开启 N Agent Bridge，返回后状态会自动刷新"
            : "请打开 系统设置 → 隐私与安全性 → 输入监控，开启 N Agent Bridge"
    }

    private func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        let opened = candidates.compactMap(URL.init(string:)).contains { NSWorkspace.shared.open($0) }
        lastMessage = opened
            ? "已打开“辅助功能”：请开启 N Agent Bridge，返回后状态会自动刷新"
            : "请打开 系统设置 → 隐私与安全性 → 辅助功能，开启 N Agent Bridge"
    }

    func beginLearningBinding(_ index: Int) {
        guard activeKeyBindings.indices.contains(index) else { return }
        learningBindingIndex = index
        pendingLearningEvent = nil
        deviceManager.calibrationMode = true
        lastMessage = "正在学习“\(activeKeyBindings[index].action.displayName)”：请按一下要使用的实体键"
    }

    func cancelLearningBinding() {
        learningBindingIndex = nil
        pendingLearningEvent = nil
        deviceManager.calibrationMode = false
        lastMessage = "已取消按键学习"
    }

    func resetBindingsToPhysicalFunctionKeys() {
        let defaults = installedHardwareProfileIsCurrent
            ? BridgeConfiguration.hardwareProfileBindings : BridgeConfiguration.defaultBindings
        configuration.setBindings(defaults, for: currentDevice?.profileID)
        learningBindingIndex = nil
        pendingLearningEvent = nil
        deviceManager.calibrationMode = false
        persistConfiguration()
        lastMessage = "\(currentModelName) 已恢复为实体 F1–F12 默认映射"
        lastAgentSignalLights = nil
        if lightingAvailable { syncAgentLighting() }
    }

    private func consumeLearningEvent(_ event: HIDEvent) -> Bool {
        guard let index = learningBindingIndex,
              activeKeyBindings.indices.contains(index) else { return false }
        guard event.usagePage == 0x07 else {
            if event.value != 0 {
                lastMessage = "媒体键无法可靠隔离系统功能；请选择数字、字母、F 区或导航键"
            }
            return true
        }
        if event.value != 0 {
            guard let normalizedUsage = KeyBinding.normalizedLearnableUsage(
                usagePage: event.usagePage,
                usage: event.usage,
                value: event.value
            ) else {
                // Some keyboard interfaces publish an array placeholder with
                // usage 0xFFFFFFFF and value 1 before the real discrete key
                // event. Ignore it instead of turning every future key into
                // one Codex action.
                return true
            }
            var normalizedEvent = event
            normalizedEvent.usage = normalizedUsage
            normalizedEvent.value = 1
            pendingLearningEvent = normalizedEvent
            lastMessage = "已识别 \(KeyBinding(usagePage: event.usagePage, usage: normalizedUsage, action: activeKeyBindings[index].action).displayName)，松开按键即可保存"
            return true
        }
        guard let learnedEvent = pendingLearningEvent else { return true }
        let isArrayRelease = event.usagePage == 0x07
            && event.usage == KeyBinding.hidArrayUsageSentinel
        guard isArrayRelease || (
            learnedEvent.usagePage == event.usagePage
                && learnedEvent.usage == event.usage
        ) else { return true }

        var bindings = activeKeyBindings
        let previous = bindings[index]
        if let duplicate = bindings.indices.first(where: {
            $0 != index && bindings[$0].usagePage == learnedEvent.usagePage
                && bindings[$0].usage == learnedEvent.usage
        }) {
            bindings[duplicate].usagePage = previous.usagePage
            bindings[duplicate].usage = previous.usage
            bindings[duplicate].signalLightIndex = previous.signalLightIndex
        }
        bindings[index].usagePage = learnedEvent.usagePage
        bindings[index].usage = learnedEvent.usage
        bindings[index].signalLightIndex = SignalLightLayout.index(
            layoutID: currentSignalLightLayoutID,
            usagePage: learnedEvent.usagePage,
            usage: learnedEvent.usage
        )
        let learnedName = bindings[index].displayName
        let actionName = bindings[index].action.displayName
        configuration.setBindings(bindings, for: currentDevice?.profileID)
        learningBindingIndex = nil
        pendingLearningEvent = nil
        deviceManager.calibrationMode = false
        persistConfiguration()
        lastAgentSignalLights = nil
        failedAgentSignalLights = nil
        if lightingAvailable { syncAgentLighting() }
        lastMessage = "已学习 \(learnedName) → \(actionName)"
        showOverlay("按键已学习", detail: "\(learnedName) → \(actionName)")
        return true
    }

    func refreshLighting() {
        refreshLighting(isAutomaticRetry: false)
    }

    private func refreshLighting(isAutomaticRetry: Bool) {
        guard !lightingBusy, !hardwareProfileBusy else { return }
        if !isAutomaticRetry {
            lightingRefreshRetryTask?.cancel()
            lightingRefreshFailureCount = 0
        }
        guard let controller = currentLightingDriver else {
            lightingAvailable = false
            lightingMessage = "当前键盘尚无经过实机验证的灯光驱动"
            return
        }
        guard let connection = controller.detectedConnection() else {
            lightingConnection = nil
            lightingAvailable = false
            sleepConfiguration = nil
            lightingMessage = devices.contains(where: {
                $0.isRecognized && $0.transports.contains(.bluetooth)
            })
                ? "蓝牙按键已连接，但当前固件没有实时灯光写入通道；请切换到 2.4G 并插入接收器"
                : "请连接 USB-C，或插入 Air75 V3 的 2.4G 接收器"
            return
        }
        lightingConnection = connection
        let sleepController = currentSleepDriver
        lightingBusy = true
        lightingMessage = "正在通过 \(connection.displayName) 读取键盘灯光状态…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    // D5 is the capability required to discover a usable
                    // lighting channel. Some U1
                    // firmware versions do not forward management commands
                    // such as A1 firmware info or F3 sleep configuration;
                    // those optional reads must not disable working D5/D6 RGB.
                    let states = try controller.readStates()
                    let firmware = (try? controller.firmwareDescription()) ?? "未读取（灯光通道正常）"
                    let sleep: KeyboardSleepConfiguration?
                    if connection == .usbCable, let sleepController {
                        sleep = try? sleepController.readSleepConfiguration()
                    } else {
                        sleep = nil
                    }
                    return (firmware, states, sleep)
                }.value
                lightingFirmware = result.0
                lightingStates = result.1
                sleepConfiguration = result.2
                lightingAvailable = true
                lightingRefreshFailureCount = 0
                lightingRefreshRetryTask?.cancel()
                lightingMessage = controller.supportsFullLightingControl
                    ? "\(connection.displayName) 灯光通道已就绪"
                    : "\(connection.displayName) Agent 单键状态灯通道已就绪"
                configuration.lighting.usbDynamic = .verified
                configuration.lighting.usbSingleKey = .unavailable
                configuration.lighting.bluetoothDynamic = .blocked
                configuration.lighting.bluetoothSingleKey = .blocked
                configuration.lighting.reason = "USB-C 与 U1 2.4G 接收器支持整键背光和侧灯；当前固件未提供蓝牙实时配置通道"
                failedAgentSignalLights = nil
            } catch {
                lightingAvailable = false
                lightingRefreshFailureCount += 1
                lightingMessage = connection == .twoPointFourGHzReceiver
                    ? "2.4G 接收器已插入，但键盘没有响应灯光指令；请确认已切到 2.4G，并按任意键唤醒。\(error.localizedDescription)"
                    : error.localizedDescription
            }
            lightingBusy = false
            if lightingAvailable {
                if configuration.agentLightingEnabled == true { syncAgentLighting() }
            } else {
                scheduleLightingRefreshRetry(for: connection)
            }
        }
    }

    /// Freshly enumerated S4 interfaces can accept input before their vendor
    /// management endpoint is ready. Retry the read-only D5 handshake a small,
    /// bounded number of times so users do not need to discover that a manual
    /// refresh works several seconds later.
    private func scheduleLightingRefreshRetry(for connection: KeyboardLightingConnection) {
        guard lightingRefreshFailureCount < 3 else { return }
        lightingRefreshRetryTask?.cancel()
        let nextAttempt = lightingRefreshFailureCount + 1
        lightingMessage += "；正在自动重试（\(nextAttempt)/3）"
        lightingRefreshRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self,
                  !self.lightingBusy, !self.hardwareProfileBusy,
                  self.currentLightingDriver?.detectedConnection() == connection else { return }
            self.refreshLighting(isAutomaticRetry: true)
        }
    }

    /// A sleeping wireless keyboard leaves the USB receiver enumerated while
    /// the radio link itself is unavailable. Its first key event proves the
    /// link is awake, so retry the pending status color once after a short
    /// delay instead of requiring the user to reopen the lighting page.
    private func scheduleWirelessLightingRetryIfNeeded() {
        guard configuration.agentLightingEnabled == true,
              lightingConnection == .twoPointFourGHzReceiver,
              !lightingBusy else { return }
        let targetLights = desiredAgentSignalLights()
        guard !lightingAvailable || lastAgentSignalLights != targetLights else { return }
        wirelessLightingRetryTask?.cancel()
        wirelessLightingRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            if self.lightingAvailable { self.syncAgentLighting() }
            else { self.refreshLighting() }
        }
    }

    /// A user may keep an Air keyboard paired over Bluetooth while plugging in
    /// a different NuPhy model. The interface that actually produced activity
    /// is therefore more authoritative than a fixed transport preference.
    private func noteActiveDevice(for interface: HIDInterfaceSnapshot) {
        guard let device = devices.first(where: { snapshot in
            snapshot.isRecognized && snapshot.interfaces.contains(where: { $0.id == interface.id })
        }) else { return }
        guard activeDeviceID != device.id else { return }
        activeDeviceID = device.id
        syncActiveInputConfiguration()
        publishDeviceDiagnostics()
        verifyRecordedHardwareProfileIfNeeded()
    }

    private func publishDeviceDiagnostics() {
        let defaults = UserDefaults.standard
        guard let device = currentDevice else {
            ["ConnectedModelName", "ConnectedProfileID", "ConnectedProductName",
             "ConnectedUSBIdentity", "ActiveKeyBindings"].forEach(defaults.removeObject(forKey:))
            return
        }
        defaults.set(device.modelName ?? device.productName, forKey: "ConnectedModelName")
        defaults.set(device.profileID, forKey: "ConnectedProfileID")
        defaults.set(device.productName, forKey: "ConnectedProductName")
        if let interface = device.interfaces.first(where: { $0.transport == .usb })
            ?? device.interfaces.first {
            defaults.set(
                String(format: "0x%04X:0x%04X", interface.vendorID, interface.productID),
                forKey: "ConnectedUSBIdentity"
            )
        }
        defaults.set(
            activeKeyBindings.map { "\($0.action.rawValue)=\($0.displayName)" }.joined(separator: ", "),
            forKey: "ActiveKeyBindings"
        )
    }

    /// The saved profile flag lives on this Mac, while the F13-F24 layer lives
    /// on the keyboard and can be reset by a firmware update. Verify the board
    /// itself whenever a previously configured model is attached over USB.
    /// This path never writes hardware: a mismatch returns the app to the
    /// explicit Configure flow instead of silently using ordinary F1-F12.
    private func verifyRecordedHardwareProfileIfNeeded() {
        guard !hardwareProfileBusy, !lightingBusy,
              let device = currentDevice,
              hasDirectUSBConfigurationInterface(device),
              let profile = profile(for: device),
              configuration.hasInstalledHardwareProfile(for: profile.profileID),
              let controller = KeyboardDriverRegistry.keymapDriver(for: profile) else { return }
        let verificationID = "\(device.id)|\(profile.profileID)"
        guard !verifiedHardwareProfileDeviceIDs.contains(verificationID) else { return }
        verifiedHardwareProfileDeviceIDs.insert(verificationID)
        hardwareProfileBusy = true
        hardwareProfileMessage = "正在核对键盘里的 F13–F24 专用层…"

        let deviceID = device.id
        let fingerprint = device.fingerprint
        let profileID = profile.profileID
        Task { [weak self] in
            guard let self else { return }
            var shouldRefreshLighting = true
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try controller.readKeymap()
                }.value
                guard self.currentDevice?.id == deviceID else {
                    self.verifiedHardwareProfileDeviceIDs.remove(verificationID)
                    self.hardwareProfileVerificationAttempts.removeValue(forKey: verificationID)
                    self.hardwareProfileBusy = false
                    return
                }
                guard controller.isPlausibleKeymap(bytes) else {
                    throw Air75KeymapError.encryptedSessionData
                }
                if controller.containsBridgeProfile(bytes) {
                    self.hardwareProfileVerificationRetryTask?.cancel()
                    self.hardwareProfileVerificationRetryTask = nil
                    self.hardwareProfileVerificationAttempts.removeValue(forKey: verificationID)
                    self.hardwareProfileVerificationFailures.remove(profileID)
                    let normalized = BridgeConfiguration.bindingsForInstalledHardwareProfile(
                        BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
                            self.configuration.bindings(for: profileID),
                            hardwareProfileInstalled: true
                        )
                    )
                    var state = self.configuration.hardwareProfileState(for: profileID)
                        ?? InstalledHardwareProfileState(installed: true)
                    state.installed = true
                    state.boundFingerprint = fingerprint
                    self.configuration.setHardwareProfileState(state, for: profileID)
                    self.configuration.setBindings(normalized, for: profileID)
                    self.hardwareProfileMessage = "F13–F24 专用层已从键盘逐字节核对"
                } else {
                    self.hardwareProfileVerificationRetryTask?.cancel()
                    self.hardwareProfileVerificationRetryTask = nil
                    self.hardwareProfileVerificationAttempts.removeValue(forKey: verificationID)
                    self.hardwareProfileVerificationFailures.insert(profileID)
                    let originalBindings = BridgeConfiguration.bindingsForOriginalHardwareProfile(
                        self.configuration.bindings(for: profileID)
                    )
                    self.configuration.setHardwareProfileState(nil, for: profileID)
                    self.configuration.setBindings(originalBindings, for: profileID)
                    self.configuration.mappingMode = .unavailable
                    self.configuration.enabled = false
                    self.configuration.codexModeEnabled = false
                    self.hardwareProfileMessage = "键盘固件已恢复原生 F1–F12，请点击配置重新启用"
                    self.lastMessage = self.hardwareProfileMessage
                }
                self.persistConfiguration()
            } catch {
                self.verifiedHardwareProfileDeviceIDs.remove(verificationID)
                let attempts = (self.hardwareProfileVerificationAttempts[verificationID] ?? 0) + 1
                if attempts < 3 {
                    shouldRefreshLighting = false
                    self.hardwareProfileVerificationAttempts[verificationID] = attempts
                    self.hardwareProfileMessage = "键盘专用层暂未响应，正在自动重试（\(attempts + 1)/3）…"
                    self.hardwareProfileVerificationRetryTask?.cancel()
                    self.hardwareProfileVerificationRetryTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled, let self else { return }
                        guard self.currentDevice?.id == deviceID else {
                            self.hardwareProfileVerificationAttempts.removeValue(forKey: verificationID)
                            self.hardwareProfileVerificationRetryTask = nil
                            return
                        }
                        guard !self.hardwareProfileBusy else { return }
                        self.hardwareProfileVerificationRetryTask = nil
                        self.verifyRecordedHardwareProfileIfNeeded()
                    }
                } else {
                    self.hardwareProfileVerificationAttempts.removeValue(forKey: verificationID)
                    self.hardwareProfileVerificationFailures.insert(profileID)
                    self.hardwareProfileMessage = "暂时无法核对键盘专用层：\(error.localizedDescription)"
                }
            }
            self.hardwareProfileBusy = false
            if shouldRefreshLighting,
               self.currentLightingDriver?.detectedConnection() != nil,
               !self.lightingBusy {
                self.refreshLighting()
            }
        }
    }

    /// USB-C and the U1 receiver share the same serial number and can both be
    /// present while the keyboard is in 2.4G mode. The input interface that
    /// emitted this event is the reliable indication of the active path.
    private func noteActiveLightingConnection(for interface: HIDInterfaceSnapshot) {
        let connection: KeyboardLightingConnection
        switch interface.productID {
        case Air75V3LightingController.productID:
            connection = .usbCable
        case Air75V3LightingController.dongleProductID:
            connection = .twoPointFourGHzReceiver
        default:
            return
        }
        let now = Date()
        let likelyWake = now.timeIntervalSince(lastKeyboardActivityAt) > 30
        lastKeyboardActivityAt = now
        currentLightingDriver?.preferConnection(connection)
        if lightingConnection != connection {
            lightingConnection = connection
            lightingAvailable = false
            sleepConfiguration = nil
            lastAgentSignalLights = nil
            failedAgentSignalLights = nil
        }
        if likelyWake {
            scheduleAgentLightingResyncAfterWake(force: true)
        }
    }

    /// Firmware D8 colors are transient on some sleep/wake paths. Reassert the
    /// current six logical states after a likely keyboard or Mac wake instead
    /// of trusting the last successful write cache forever.
    private func scheduleAgentLightingResyncAfterWake(force: Bool = false) {
        guard configuration.agentLightingEnabled == true else { return }
        if force || lastAgentSignalWriteAt.map({ Date().timeIntervalSince($0) > 15 }) != false {
            lastAgentSignalLights = nil
            failedAgentSignalLights = nil
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            if self.lightingAvailable { self.syncAgentLighting() }
            else if self.currentLightingDriver?.detectedConnection() != nil { self.refreshLighting() }
        }
    }

    func setKeyboardLightStayOnMinutes(_ minutes: Int?) {
        guard !lightingBusy else { return }
        guard lightingConnection == .usbCable else {
            lightingMessage = "灯光保持时间属于键盘管理设置，请连接 USB-C 后修改；Agent 状态灯不受影响"
            return
        }
        guard let controller = currentSleepDriver else {
            lightingMessage = "当前键盘尚无经过实机验证的休眠设置驱动"
            return
        }
        let fingerprint = devices.first(where: {
            $0.isRecognized && hasDirectUSBConfigurationInterface($0)
                && $0.profileID == controller.profileID
        })?.fingerprint
        let label = minutes.map { "无操作 \($0) 分钟后熄灯" } ?? "灯光始终保持开启"
        lightingBusy = true
        lightingMessage = "正在写入休眠时间并读回验证…"
        Task {
            do {
                let before = try await Task.detached(priority: .userInitiated) {
                    try controller.readSleepConfiguration()
                }.value
                let backupURL = try configurationStore.createSleepBackup(
                    configuration: before,
                    note: "N Agent Bridge 修改键盘长亮时间前读取的原始 3-byte 休眠配置。",
                    profileID: controller.profileID,
                    deviceFingerprint: fingerprint
                )
                let after = try await Task.detached(priority: .userInitiated) {
                    try controller.setAutoSleep(afterMinutes: minutes)
                }.value
                sleepConfiguration = after
                lastBackupURL = backupURL
                lightingAvailable = true
                lightingMessage = "\(label)；键盘已回读确认"
            } catch {
                lightingMessage = "休眠时间设置失败：\(error.localizedDescription)"
            }
            lightingBusy = false
        }
    }

    func setBacklightMode(_ mode: Air75BacklightMode) {
        runLightingWrite(label: "背光灯效：\(mode.displayName)") { controller in
            try controller.setBacklight(mode: mode, brightness: nil, color: nil)
        }
    }

    func setSidelightMode(_ mode: Air75SidelightMode) {
        runLightingWrite(label: "侧灯灯效：\(mode.displayName)") { controller in
            try controller.setSidelight(mode: mode, brightness: nil, color: nil)
        }
    }

    func setSidelightStaticColor(hex: String) {
        guard let color = Air75RGBColor(hex: hex) else { return }
        runLightingWrite(label: "侧灯常亮颜色：\(hex.uppercased())") { controller in
            try controller.setSidelight(mode: .staticColor, brightness: nil, color: color)
        }
    }

    func setBacklightStaticColor(hex: String) {
        guard let color = Air75RGBColor(hex: hex) else { return }
        runLightingWrite(label: "背光常亮颜色：\(hex.uppercased())") { controller in
            try controller.setBacklight(mode: .staticColor, brightness: nil, color: color)
        }
    }

    func setHardwareStaticColor(hex: String, label: String? = nil) {
        guard let color = Air75RGBColor(hex: hex) else { return }
        runLightingWrite(label: label ?? "整键灯光颜色：\(hex.uppercased())") { controller in
            try controller.setStaticColor(color, brightness: nil)
        }
    }

    func setAgentLightingEnabled(_ enabled: Bool) {
        configuration.agentLightingEnabled = enabled
        lastAgentSignalLights = nil
        failedAgentSignalLights = nil
        lastAgentSignalWriteAt = nil
        lastAgentSignalAttemptAt = nil
        persistConfiguration()
        if enabled { syncAgentLighting() }
        else { restoreUserSignalLights() }
    }

    func taskLightColorHex(for state: CodexTaskLightState) -> String {
        configuration.resolvedTaskLightPalette.colorHex(for: state)
    }

    func setTaskLightColor(_ state: CodexTaskLightState, hex: String) {
        guard Air75RGBColor(hex: hex) != nil else { return }
        var palette = configuration.resolvedTaskLightPalette
        palette.setColorHex(hex.uppercased(), for: state)
        configuration.taskLightPalette = palette
        lastAgentSignalLights = nil
        failedAgentSignalLights = nil
        persistConfiguration()
        if lightingAvailable {
            syncAgentLighting()
        } else {
            lightingMessage = "颜色已保存；连接灯光通道后会自动应用到 Agent 实体键"
        }
    }

    func resetTaskLightColors() {
        configuration.taskLightPalette = .default
        lastAgentSignalLights = nil
        failedAgentSignalLights = nil
        persistConfiguration()
        if lightingAvailable { syncAgentLighting() }
    }

    private func restoreUserSignalLights() {
        let saved = userSignalLightsByIndex.values.sorted { $0.index < $1.index }
        guard !saved.isEmpty else {
            lightingMessage = "Codex 状态灯模式已关闭；键盘灯光已恢复"
            return
        }
        if lightingBusy {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.restoreUserSignalLights()
            }
            return
        }
        guard let controller = currentLightingDriver else { return }
        lightingBusy = true
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try controller.setSignalLights(saved)
                }.value
                userSignalLightsByIndex = [:]
                managedSignalLightIndices = Set(Air75V3LightingController.taskSignalLightIndices)
                lastAgentSignalLights = nil
                lightingMessage = "已恢复进入 Codex 模式前的实体键灯光"
            } catch {
                lightingMessage = "Agent 实体键灯光恢复失败：\(error.localizedDescription)"
            }
            lightingBusy = false
        }
    }

    func restoreUserLighting() {
        guard !lightingBusy else { return }
        guard let controller = currentLightingDriver else {
            lightingMessage = "当前键盘尚无经过实机验证的灯光驱动"
            return
        }
        guard controller.supportsFullLightingControl else {
            lightingMessage = "当前型号仅启用已验证的 Agent 单键状态灯；普通灯效保持键盘原设置"
            return
        }
        let saved = originalLightingStates
            ?? configurationStore.loadLatestLightingBackup(profileID: controller.profileID)?.states
        guard let saved else {
            lightingMessage = "还没有可恢复的硬件灯光备份"
            return
        }
        lightingBusy = true
        Task {
            do {
                lightingStates = try await Task.detached(priority: .userInitiated) {
                    try controller.restore(saved)
                }.value
                lightingAvailable = true
                lightingMessage = "已恢复首次修改前的原灯光设置"
            } catch { lightingMessage = "恢复失败：\(error.localizedDescription)" }
            lightingBusy = false
            if configuration.agentLightingEnabled == true {
                lastAgentSignalLights = nil
                syncAgentLighting()
            }
        }
    }

    private func runLightingWrite(
        label: String,
        operation: @escaping @Sendable (any KeyboardLightingDriver) throws -> [KeyboardLightingState],
        completion: ((Bool, [Air75LightingState]?) -> Void)? = nil
    ) {
        guard !lightingBusy else { return }
        guard let controller = currentLightingDriver else {
            lightingAvailable = false
            lightingMessage = "当前键盘尚无经过实机验证的灯光驱动"
            return
        }
        guard controller.supportsFullLightingControl else {
            lightingMessage = "当前型号仅启用已验证的 Agent 单键状态灯；普通背光和侧灯不会被改动"
            completion?(false, nil)
            return
        }
        lightingBusy = true
        lightingMessage = "正在写入并读回验证…"
        Task {
            var succeeded = false
            var beforeStates: [Air75LightingState]?
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let before = try controller.readStates()
                    let after = try operation(controller)
                    return (before, after)
                }.value
                beforeStates = result.0
                if originalLightingStates == nil {
                    if let existing = configurationStore.loadLatestLightingBackup(profileID: controller.profileID) {
                        originalLightingStates = existing.states
                    } else {
                        originalLightingStates = result.0
                        lastBackupURL = try configurationStore.createLightingBackup(
                            states: result.0,
                            note: "N Agent Bridge 首次修改前，从键盘逐字节读取的两个灯光 Profile。",
                            profileID: controller.profileID,
                            deviceFingerprint: self.devices.first(where: {
                                $0.isRecognized && self.hasDirectUSBConfigurationInterface($0)
                                    && $0.profileID == controller.profileID
                            })?.fingerprint
                        )
                    }
                }
                lightingStates = result.1
                lightingAvailable = true
                lightingMessage = "\(label)；键盘已回读确认"
                succeeded = true
            } catch {
                let writeError = error
                lightingConnection = controller.detectedConnection()
                do {
                    // A rejected setting is not the same as a lost HID
                    // channel. The controller has already attempted rollback;
                    // re-read it so one failed selection does not grey out all
                    // lighting controls until the next application restart.
                    lightingStates = try await Task.detached(priority: .userInitiated) {
                        try controller.readStates()
                    }.value
                    lightingAvailable = true
                    lightingMessage = "灯光设置未生效：\(writeError.localizedDescription)；当前设置已重新读取"
                } catch {
                    lightingAvailable = false
                    lightingMessage = "灯光设置失败：\(writeError.localizedDescription)"
                }
            }
            lightingBusy = false
            completion?(succeeded, beforeStates)
            if configuration.agentLightingEnabled == true { syncAgentLighting() }
        }
    }

    private func syncAgentLighting() {
        guard configuration.agentLightingEnabled == true, lightingAvailable,
              !lightingBusy, !hardwareProfileBusy else { return }
        if configuration.sidelightRestoredAfterSignalLights != true {
            restoreLegacyAgentSidelight()
            return
        }
        syncAgentSignalLights()
    }

    private func restoreLegacyAgentSidelight() {
        guard !lightingBusy, let controller = currentLightingDriver else { return }
        guard controller.supportsFullLightingControl else {
            configuration.sidelightRestoredAfterSignalLights = true
            persistConfiguration()
            syncAgentSignalLights()
            return
        }
        guard let original = configurationStore.loadOriginalLightingBackup(
            profileID: controller.profileID
        ) else {
            configuration.sidelightRestoredAfterSignalLights = true
            persistConfiguration()
            lightingMessage = "未找到旧侧灯备份；已停止 Codex 控制侧灯"
            syncAgentSignalLights()
            return
        }
        lightingBusy = true
        lightingMessage = "正在恢复官方侧灯灯效…"
        Task {
            do {
                lightingStates = try await Task.detached(priority: .userInitiated) {
                    try controller.restoreSidelight(from: original.states)
                }.value
                configuration.sidelightRestoredAfterSignalLights = true
                persistConfiguration()
                lightingMessage = "侧灯已恢复为接管前的官方灯效"
            } catch {
                lightingMessage = "侧灯恢复失败：\(error.localizedDescription)"
            }
            lightingBusy = false
            if configuration.sidelightRestoredAfterSignalLights == true {
                syncAgentSignalLights()
            }
        }
    }

    private func desiredAgentSignalLights() -> [Air75SignalLight] {
        let actions: [BridgeAction] = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6]
        var desiredByIndex: [UInt8: Air75SignalLight] = [:]
        let off = Air75RGBColor(red: 0, green: 0, blue: 0)
        let activeIndices = Set(actions.compactMap { action -> UInt8? in
            guard let value = activeKeyBindings.first(where: { $0.action == action })?.signalLightIndex,
                  (0...255).contains(value) else { return nil }
            return UInt8(value)
        })
        let staleIndices = Set(SignalLightLayout.staleManagedIndices(layoutID: currentSignalLightLayoutID)
            .compactMap { (0...255).contains($0) ? UInt8($0) : nil })
        let indicesToClear = managedSignalLightIndices
            .union(Air75V3LightingController.taskSignalLightIndices)
            .union(staleIndices)
            .subtracting(activeIndices)
        for index in indicesToClear { desiredByIndex[index] = Air75SignalLight(index: index, color: off) }
        for (taskIndex, action) in actions.enumerated() {
            guard let value = activeKeyBindings.first(where: { $0.action == action })?.signalLightIndex,
                  (0...255).contains(value) else { continue }
            let index = UInt8(value)
            let snapshot = codexTasks.indices.contains(taskIndex) ? codexTasks[taskIndex] : .unassigned
            let color = snapshot.threadID == nil
                ? off
                : (Air75RGBColor(hex: taskLightColorHex(for: snapshot.state)) ?? off)
            desiredByIndex[index] = Air75SignalLight(index: index, color: color)
        }
        managedSignalLightIndices.formUnion(activeIndices)
        // 0.10.0 accidentally wrote task 1 to index 0 (Esc). D8 colors
        // persist until explicitly replaced, so every sync clears that stale
        // indicator while writing the six real F-row indexes.
        let escapeOff = Air75SignalLight(
            index: Air75V3LightingController.escapeSignalLightIndex,
            color: Air75RGBColor(red: 0, green: 0, blue: 0)
        )
        desiredByIndex[Air75V3LightingController.escapeSignalLightIndex] = escapeOff
        return desiredByIndex.values.sorted { $0.index < $1.index }
    }

    private func syncAgentSignalLights() {
        guard configuration.agentLightingEnabled == true, lightingAvailable,
              !lightingBusy, !hardwareProfileBusy else { return }
        let desired = desiredAgentSignalLights()
        if failedAgentSignalLights != nil, failedAgentSignalLights != desired {
            agentSignalRetryCount = 0
            agentSignalRetryTask?.cancel()
        }
        let now = Date()
        let hasLiveStatus = codexTasks.contains { snapshot in
            snapshot.threadID != nil && snapshot.state != .idle
        }
        let keepaliveDue = hasLiveStatus
            && (lastAgentSignalWriteAt.map { now.timeIntervalSince($0) >= 90 } ?? true)
        let retryDue = failedAgentSignalLights == desired
            && (lastAgentSignalAttemptAt.map { now.timeIntervalSince($0) >= 30 } ?? true)
        guard desired.count >= 2,
              lastAgentSignalLights != desired || keepaliveDue,
              failedAgentSignalLights != desired || retryDue,
              let controller = currentLightingDriver else { return }

        let backupIndices = desired.map(\.index).filter {
            $0 != Air75V3LightingController.escapeSignalLightIndex
                && userSignalLightsByIndex[$0] == nil
        }

        lightingBusy = true
        lastAgentSignalAttemptAt = now
        lightingMessage = "正在同步六个 Agent 实体键状态…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let before = backupIndices.isEmpty
                        ? nil : (try? controller.readSignalLights(indices: backupIndices))
                    let written = try controller.setSignalLights(desired)
                    return (before, written)
                }.value
                if let before = result.0 {
                    for light in before where userSignalLightsByIndex[light.index] == nil {
                        userSignalLightsByIndex[light.index] = light
                    }
                }
                lastAgentSignalLights = result.1
                failedAgentSignalLights = nil
                agentSignalRetryCount = 0
                agentSignalRetryTask?.cancel()
                lastAgentSignalWriteAt = Date()
                if lightingConnection == .twoPointFourGHzReceiver {
                    configuration.lighting.bluetoothSingleKey = .verified
                } else {
                    configuration.lighting.usbSingleKey = .verified
                }
                persistConfiguration()
                lightingMessage = "六个 Agent 状态已同步到各自实体键；\(secondaryLightingZoneName)保持用户设置"
            } catch {
                failedAgentSignalLights = desired
                agentSignalRetryCount += 1
                lightingMessage = "Agent 实体键指示灯写入失败；\(secondaryLightingZoneName)不受影响：\(error.localizedDescription)"
            }
            lightingBusy = false
            if failedAgentSignalLights == nil { syncAgentLighting() }
            else { scheduleAgentSignalRetry() }
        }
    }

    private func scheduleAgentSignalRetry() {
        guard agentSignalRetryCount < 3 else { return }
        agentSignalRetryTask?.cancel()
        agentSignalRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self,
                  !self.lightingBusy, !self.hardwareProfileBusy,
                  self.lightingAvailable else { return }
            self.lastAgentSignalAttemptAt = nil
            self.syncAgentSignalLights()
        }
    }

    private func applyDesktopTaskSnapshots(_ snapshots: [CodexTaskLightSnapshot]) {
        codexThreadCandidates = snapshots
        bindPendingCustomThreadIfNeeded(from: snapshots)
        codexTasks = CodexAgentSlotResolver.resolve(
            candidates: snapshots,
            mode: configuration.resolvedAgentSourceMode,
            pinnedThreadIDs: configuration.resolvedPinnedAgentThreadIDs,
            customThreadIDs: configuration.resolvedCustomAgentThreadIDs
        )
        // Aggregate remains useful for compact software summaries; hardware
        // Hardware status is represented independently by the six current
        // Agent-key locations from schema 9 onward.
        codexTopTaskLightState = CodexTaskLightAggregator.aggregate(codexTasks.map(\.state))
        codexTopTaskID = codexTasks.first(where: { $0.threadID != nil })?.threadID
        for index in slots.indices {
            if index < codexTasks.count, codexTasks[index].threadID != nil {
                let snapshot = codexTasks[index]
                slots[index].sessionId = snapshot.threadID
                slots[index].title = snapshot.title?.isEmpty == false
                    ? snapshot.title! : "Codex 对话 \(index + 1)"
                slots[index].projectPath = snapshot.projectPath ?? slots[index].projectPath
                slots[index].state = Self.slotState(for: snapshot.state)
                slots[index].isUnread = snapshot.isUnread
                slots[index].isWaitingForApproval = snapshot.state == .waitingForConfirmation
                slots[index].hasError = snapshot.state == .error
                if let eventDate = snapshot.eventDate { slots[index].updatedAt = eventDate }
            } else {
                slots[index].sessionId = nil
                slots[index].state = .noAssignment
                slots[index].isUnread = false
                slots[index].isWaitingForApproval = false
                slots[index].hasError = false
            }
        }
        syncAgentLighting()
    }

    func setAgentSourceMode(_ mode: CodexAgentSourceMode) {
        configuration.agentSourceMode = mode
        persistConfiguration()
        applyDesktopTaskSnapshots(codexThreadCandidates)
    }

    func assignedThreadID(for slotIndex: Int, mode: CodexAgentSourceMode? = nil) -> String? {
        guard (0..<CodexAgentSlotResolver.slotCount).contains(slotIndex) else { return nil }
        switch mode ?? configuration.resolvedAgentSourceMode {
        case .custom: return configuration.resolvedCustomAgentThreadIDs[slotIndex]
        case .recent, .pinned, .priority:
            return codexTasks.indices.contains(slotIndex) ? codexTasks[slotIndex].threadID : nil
        }
    }

    func assignThread(_ threadID: String?, to slotIndex: Int, for mode: CodexAgentSourceMode) {
        guard (0..<CodexAgentSlotResolver.slotCount).contains(slotIndex),
              mode == .custom || mode == .pinned else { return }
        if mode == .custom {
            var values = configuration.resolvedCustomAgentThreadIDs
            values[slotIndex] = threadID
            configuration.customAgentThreadIDs = values
        } else {
            var values = configuration.resolvedPinnedAgentThreadIDs
            values[slotIndex] = threadID
            configuration.pinnedAgentThreadIDs = values
        }
        updateTrackedCodexThreadIDs()
        persistConfiguration()
        applyDesktopTaskSnapshots(codexThreadCandidates)
    }

    private func bindPendingCustomThreadIfNeeded(from candidates: [CodexTaskLightSnapshot]) {
        guard let pending = pendingCustomSlot else { return }
        guard Date() <= pending.expiresAt else {
            pendingCustomSlot = nil
            return
        }
        guard let created = candidates
            .filter({ snapshot in
                guard let id = snapshot.threadID else { return false }
                return !pending.knownThreadIDs.contains(id)
            })
            .max(by: { $0.recencyAtMS < $1.recencyAtMS }),
              let id = created.threadID else { return }
        var values = configuration.resolvedCustomAgentThreadIDs
        values[pending.index] = id
        configuration.customAgentThreadIDs = values
        pendingCustomSlot = nil
        updateTrackedCodexThreadIDs()
        persistConfiguration()
        lastMessage = "新对话已自动绑定到 Agent \(pending.index + 1)"
    }

    private func updateTrackedCodexThreadIDs() {
        let custom = configuration.resolvedCustomAgentThreadIDs.compactMap { $0 }
        let pinned = configuration.resolvedPinnedAgentThreadIDs.compactMap { $0 }
        codexDesktopStatusObserver.setTrackedThreadIDs(Set(custom + pinned))
    }

    private static func slotState(for state: CodexTaskLightState) -> AgentState {
        switch state {
        case .idle: return .idle
        case .reasoning: return .running
        case .complete: return .complete
        case .waitingForConfirmation: return .waitingForApproval
        case .error: return .error
        }
    }

    func installCodexDesktopBindings() {
        do {
            let result = try codexKeybindingInstaller.install()
            codexDesktopKeybindingsInstalled = true
            codexRestartRequired = result.changed || codexNeedsRestartForKeybindings()
            lastMessage = result.changed ? "Codex 中继快捷键已安装，请重启一次 Codex" : "Codex 中继快捷键已就绪"
            showOverlay("Codex 中继快捷键", detail: result.changed ? "请重启一次 Codex" : "已就绪")
        } catch {
            codexDesktopKeybindingsInstalled = false
            lastMessage = "Codex 快捷键安装失败：\(error.localizedDescription)"
        }
    }

    private func codexNeedsRestartForKeybindings() -> Bool {
        guard let modified = try? codexKeybindingInstaller.keybindingsURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let launchDate = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first?.launchDate else { return false }
        return modified > launchDate
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            configuration.launchAtLogin = enabled
            persistConfiguration()
        } catch {
            lastMessage = "无法更新开机启动：\(error.localizedDescription)"
        }
    }

    func persistConfiguration() {
        syncActiveInputConfiguration()
        deviceManager.configuration = configuration
        deviceManager.updateRuntimeKeyBindings(activeKeyBindings)
        syncDedicatedEventSuppression()
        do { try configurationStore.save(configuration) }
        catch { lastMessage = "保存配置失败：\(error.localizedDescription)" }
    }

    private func syncDedicatedEventSuppression() {
        let shouldRun = configuration.enabled
            && configuration.codexModeEnabled
            && inputMonitoringGranted
            && accessibilityGranted
        dedicatedEventSuppressionActive = dedicatedKeyEventSuppressor.setEnabled(
            shouldRun,
            keyBindings: activeKeyBindings
        )
        UserDefaults.standard.set(dedicatedEventSuppressionActive, forKey: "DedicatedEventSuppressionActive")
    }

    private func syncActiveInputConfiguration() {
        var runtime = configuration
        runtime.keyBindings = activeKeyBindings
        mappingEngine.configuration = runtime
        deviceManager.updateRuntimeKeyBindings(runtime.keyBindings)
        syncDedicatedEventSuppression()
    }

    private func perform(_ action: BridgeAction, event: HIDEvent, phase: KeyPhase) {
        if let slotIndex = Self.agentSlotIndex(for: action) {
            guard phase == .down else { return }
            performAgentAction(slotIndex: slotIndex)
            return
        }
        guard codexDesktopKeybindingsInstalled else {
            if phase == .down {
                lastMessage = "尚未安装 Codex 中继快捷键，请点“一键启用”"
                showOverlay("Codex 尚未连接", detail: "请在首页点“一键启用”")
            }
            return
        }
        guard inputMonitoringGranted else {
            if phase == .down {
                lastMessage = "系统尚未允许读取 Air75 按键；请在权限页开启输入监控"
                showOverlay("需要输入监控", detail: "允许 N Agent Bridge 后才能读取实体键")
            }
            return
        }
        do {
            try codexDesktopRelay.send(action, phase: phase)
            performDirectCodexFeedback(action, phase: phase)
        } catch {
            lastMessage = "Codex 控制失败：\(error.localizedDescription)"
            if phase == .down || phase == .up {
                showOverlay("Codex 控制未授权", detail: error.localizedDescription)
            }
        }
    }

    private static func agentSlotIndex(for action: BridgeAction) -> Int? {
        [BridgeAction.agent1, .agent2, .agent3, .agent4, .agent5, .agent6].firstIndex(of: action)
    }

    private func performAgentAction(slotIndex: Int) {
        let now = Date()
        let currentThreadID = assignedThreadID(for: slotIndex)
        let repeated = lastAgentPress.map {
            $0.slot == slotIndex && now.timeIntervalSince($0.date) <= 0.35
        } ?? false
        let threadID = repeated ? (lastAgentPress?.threadID ?? currentThreadID) : currentThreadID
        lastAgentPress = (slotIndex, currentThreadID, now)
        do {
            if let threadID {
                try codexDesktopRelay.openThread(threadID, activate: repeated)
                lastMessage = "Agent \(slotIndex + 1)：已打开对应对话"
            } else if repeated {
                try codexDesktopRelay.activateCodex()
            } else if configuration.resolvedAgentSourceMode == .custom {
                let known = Set(codexThreadCandidates.compactMap(\.threadID))
                pendingCustomSlot = (slotIndex, known, now.addingTimeInterval(30))
                try codexDesktopRelay.openNewThread(activate: true)
                lastMessage = "Agent \(slotIndex + 1)：新对话将在创建后自动绑定"
            } else {
                try codexDesktopRelay.openNewThread(activate: true)
                lastMessage = "当前 Agent 位没有对话，已打开新建对话"
            }
        } catch {
            lastMessage = "Codex 对话切换失败：\(error.localizedDescription)"
        }
    }

    private func performDirectCodexFeedback(_ action: BridgeAction, phase: KeyPhase) {
        guard phase == .down || (action == .confirm && phase == .up) else { return }
        let title: String
        let detail: String
        switch action {
        case .agent1, .agent2, .agent3, .agent4, .agent5, .agent6:
            let id = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6].firstIndex(of: action)! + 1
            title = "Codex 任务 \(id)"; detail = "已由 Codex 直接切换"
        case .quickAction: title = "Codex Fast Mode"; detail = "已切换快速模式"
        case .approve: title = "Codex 批准"; detail = "已发送批准命令"
        case .decline: title = "Codex 拒绝"; detail = "已发送拒绝命令"
        case .newChat: title = "Codex 新任务"; detail = "已创建新任务"
        case .pushToTalk: title = "Codex 听写"; detail = "使用 Codex 自带麦克风听写"
        case .send: title = "Codex 发送"; detail = "已发送当前输入"
        case .historyBack: title = "Codex 推理强度"; detail = "降低一级"
        case .historyForward: title = "Codex 推理强度"; detail = "提高一级"
        case .confirm: title = "Codex 模型与推理"; detail = "已打开选择器"
        default: title = action.displayName; detail = "命令已交给 Codex"
        }
        lastMessage = "\(title)：\(detail)"
    }

    private func handle(_ event: BackendEvent, backend: BackendKind) {
        switch event {
        case .connected:
            if backend == .codex { codexConnection = .connected } else { claudeConnection = .connected }
        case .disconnected(let reason):
            if backend == .codex { codexConnection = .disconnected } else { claudeConnection = .disconnected }
            if let reason { lastMessage = reason }
        case .sessionCreated(let id, let title):
            guard let index = slots.firstIndex(where: { $0.slotId == selectedSlot }) else { return }
            slots[index].sessionId = id
            slots[index].title = title ?? slots[index].title
            slots[index].state = .idle
            slots[index].updatedAt = Date()
        case .turnStarted(let sessionID, _): update(sessionID: sessionID, state: .running)
        case .state(let sessionID, let state): update(sessionID: sessionID, state: state)
        case .approval(let sessionID, let approval):
            update(sessionID: sessionID, state: .waitingForApproval)
            activeApproval = approval
            showOverlay("等待批准", detail: approval.summary)
        case .output(let sessionID, let text):
            output += text
            if let index = slots.firstIndex(where: { $0.sessionId == sessionID }), slots[index].slotId != selectedSlot {
                slots[index].isUnread = true
            }
        case .completed(let sessionID):
            update(sessionID: sessionID, state: .complete)
            showOverlay("Agent 已完成", detail: slots.first(where: { $0.sessionId == sessionID })?.title ?? "Codex")
        case .failed(let sessionID, let message):
            if let sessionID { update(sessionID: sessionID, state: .error) }
            lastMessage = message
        }
        if backend == .codex { codexConnection = codex.connectionState }
        if backend == .claudeCode { claudeConnection = claude.connectionState }
    }

    private func update(sessionID: String, state: AgentState) {
        guard let index = slots.firstIndex(where: { $0.sessionId == sessionID }) else { return }
        slots[index].state = state
        slots[index].isWaitingForApproval = state == .waitingForApproval
        slots[index].hasError = state == .error
        slots[index].updatedAt = Date()
        if slots[index].slotId == 1 { syncAgentLighting() }
    }

    private func backendForApproval() -> AgentBackend {
        currentSlot?.backend == .claudeCode ? claude : codex
    }

    private func showOverlay(_ title: String, detail: String) {
        guard configuration.overlayEnabled else { return }
        overlay.show(title: title, detail: detail, slots: slots, selectedSlot: selectedSlot)
    }
}
