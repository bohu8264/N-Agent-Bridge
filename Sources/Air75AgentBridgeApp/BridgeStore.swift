import Air75AgentBridgeCore
import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class BridgeStore: ObservableObject {
    @Published var configuration: BridgeConfiguration
    @Published var devices: [DeviceSnapshot] = []
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
    let dedicatedKeyEventSuppressor = DedicatedKeyEventSuppressor()

    private var cancellables = Set<AnyCancellable>()
    private var originalLightingStates: [Air75LightingState]?
    private var userSignalLights: [Air75SignalLight]?
    private var lastAgentSignalLights: [Air75SignalLight]?
    private var failedAgentSignalLights: [Air75SignalLight]?
    private var pendingLearningEvent: HIDEvent?
    private var wirelessLightingRetryTask: Task<Void, Never>?

    init() {
        let loaded = configurationStore.load()
        configuration = loaded
        hardwareProfileMessage = loaded.hardwareProfileInstalled == true
            ? "键盘专用层已写入并在实机完整回读确认；物理 F1–F12 与旋钮可随蓝牙使用"
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
        if loaded.hardwareProfileInstalled == true,
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

                // The U1 receiver is physically USB, but it is a distinct
                // 2.4G lighting path. Re-probe whenever the active path
                // changes so stale wired state cannot keep wireless writes
                // disabled after the cable is removed.
                let detectedConnection = self.currentLightingDriver?.detectedConnection()
                let connectionChanged = detectedConnection != self.lightingConnection
                if connectionChanged {
                    self.lightingConnection = detectedConnection
                    self.lightingAvailable = false
                    self.sleepConfiguration = nil
                    self.lastAgentSignalLights = nil
                }
                if detectedConnection != nil,
                   (connectionChanged || self.lightingStates.isEmpty || !self.lightingAvailable),
                   !self.lightingBusy {
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

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPermissions() }
            .store(in: &cancellables)

        deviceManager.start()
        codexDesktopStatusObserver.start()
        syncDedicatedEventSuppression()
        publishPermissionDiagnostics()
    }

    var currentDevice: DeviceSnapshot? {
        devices.first(where: { $0.isRecognized && $0.transports.contains(.bluetooth) })
            ?? devices.first(where: { $0.isRecognized })
    }

    var currentSlot: AgentSlot? { slots.first(where: { $0.slotId == selectedSlot }) }

    var currentModelName: String {
        currentDevice?.modelName ?? "支持的 NuPhy 键盘"
    }

    private func profile(for device: DeviceSnapshot?) -> DeviceProfile? {
        profileRegistry.profile(id: device?.profileID)
    }

    private var currentLightingProfile: DeviceProfile? {
        if let configurableDevice = devices.first(where: {
            $0.isRecognized
                && $0.transports.contains(.usb)
                && profile(for: $0)?.capabilities?.lightingDriverID != nil
        }) {
            return profile(for: configurableDevice)
        }
        if let installed = profileRegistry.profile(id: configuration.hardwareProfileID),
           installed.capabilities?.lightingDriverID != nil {
            return installed
        }
        let connected = profile(for: currentDevice)
        return connected?.capabilities?.lightingDriverID == nil ? nil : connected
    }

    private var currentLightingDriver: (any KeyboardLightingDriver)? {
        KeyboardDriverRegistry.lightingDriver(for: currentLightingProfile)
    }

    private var currentSleepDriver: (any KeyboardSleepDriver)? {
        KeyboardDriverRegistry.sleepDriver(for: currentLightingProfile)
    }

    func oneClickEnable() {
        guard !hardwareProfileBusy else { return }
        if configuration.hardwareProfileInstalled == true {
            guard let device = currentDevice,
                  device.profileID == configuration.hardwareProfileID else {
                lastMessage = "当前键盘不是已安装专用层的型号；请先连接原键盘并恢复，再配置另一型号"
                return
            }
            configuration.enabled = true
            configuration.codexModeEnabled = true
            configuration.mappingPausedByUser = false
            persistConfiguration()
            if !codexDesktopKeybindingsInstalled { installCodexDesktopBindings() }
            lastMessage = inputMonitoringGranted && accessibilityGranted
                ? "\(device.modelName ?? device.productName) 控制已启用"
                : "控制已启用，还需要完成两项系统权限"
            showOverlay("键盘控制已启用", detail: "专用按键现在只控制 Codex")
            return
        }
        guard let usbDevice = devices.first(where: { $0.isRecognized && $0.transports.contains(.usb) }) else {
            lastMessage = "请先用 USB-C 数据线连接受支持的 NuPhy 键盘"
            showOverlay("需要 USB-C", detail: "首次写入键盘专用层时请连接数据线")
            return
        }
        let targetProfile = profile(for: usbDevice)
        guard let controller = KeyboardDriverRegistry.keymapDriver(for: targetProfile) else {
            lastMessage = "\(usbDevice.modelName ?? usbDevice.productName) 目前只支持安全的软件按键模式，硬件专用层尚未验证"
            return
        }
        hardwareProfileBusy = true
        hardwareProfileMessage = "正在读取并备份完整键位表…"
        lastMessage = hardwareProfileMessage
        let configStore = configurationStore
        let currentConfiguration = configuration
        let targetProfileID = controller.profileID
        let targetModelName = usbDevice.modelName ?? usbDevice.productName
        Task {
            do {
                let keybindingInstaller = codexKeybindingInstaller
                let result = try await Task.detached(priority: .userInitiated) { () -> (KeyboardKeymapInstallResult, URL, URL, CodexKeybindingInstallResult) in
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
                            preferredName: currentConfiguration.hardwareProfileBackupName,
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
                    return (installed, keymapBackup, runtimeBackup, keybindings)
                }.value
                lastBackupURL = result.1
                configuration.boundFingerprint = usbDevice.fingerprint
                configuration.mappingMode = .hardwareProfile
                configuration.enabled = true
                configuration.codexModeEnabled = true
                configuration.mappingPausedByUser = false
                configuration.hardwareProfileInstalled = true
                configuration.hardwareProfileID = targetProfileID
                configuration.hardwareProfileBackupName = result.1.lastPathComponent
                configuration.keyBindings = BridgeConfiguration.bindingsForInstalledHardwareProfile(
                    configuration.keyBindings
                )
                persistConfiguration()
                codexDesktopKeybindingsInstalled = true
                codexRestartRequired = result.3.changed || codexNeedsRestartForKeybindings()
                hardwareProfileMessage = result.0.changedChunkAddresses.isEmpty
                    ? "键盘专用事件与 Codex 命令中继均已验证"
                    : "键盘专用事件已写入，Codex 命令中继已安装"
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
        }
    }

    func completeOnboarding() {
        configuration.hasCompletedOnboarding = true
        showOnboarding = false
        persistConfiguration()
    }

    func disable() {
        guard !hardwareProfileBusy else { return }
        guard configuration.hardwareProfileInstalled == true else {
            finishSoftwareDisable(message: "Codex 控制已停止；键盘保持普通行为")
            return
        }
        guard devices.contains(where: { $0.isRecognized && $0.transports.contains(.usb) }) else {
            lastMessage = "请保持 USB-C 连接并再次点停止；恢复完成后再拔线"
            showOverlay("暂未停止", detail: "需要先恢复键盘原生 F 区，完成后才能安全拔线")
            return
        }
        restoreOriginalConfiguration()
    }

    func restoreOriginalConfiguration() {
        guard !hardwareProfileBusy else { return }
        guard let installedProfile = profileRegistry.profile(id: configuration.hardwareProfileID),
              let controller = KeyboardDriverRegistry.keymapDriver(for: installedProfile) else {
            lastMessage = "找不到已安装专用层对应的安全恢复驱动，未执行任何硬件写入"
            return
        }
        guard let usbDevice = devices.first(where: {
            $0.isRecognized && $0.transports.contains(.usb) && $0.profileID == controller.profileID
        }) else {
            lastMessage = "恢复原始键位需要先用 USB-C 连接 \(installedProfile.model)"
            return
        }
        guard let selected = configurationStore.loadOriginalKeymapBackup(
            profileID: controller.profileID,
            expectedByteCount: controller.keymapSize,
            preferredName: configuration.hardwareProfileBackupName,
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
                configuration.hardwareProfileInstalled = false
                configuration.hardwareProfileID = nil
                configuration.keyBindings = BridgeConfiguration.bindingsForOriginalHardwareProfile(
                    configuration.keyBindings
                )
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
        guard configuration.keyBindings.indices.contains(index) else { return }
        learningBindingIndex = index
        pendingLearningEvent = nil
        deviceManager.calibrationMode = true
        lastMessage = "正在学习“\(configuration.keyBindings[index].action.displayName)”：请按一下要使用的实体键"
    }

    func cancelLearningBinding() {
        learningBindingIndex = nil
        pendingLearningEvent = nil
        deviceManager.calibrationMode = false
        lastMessage = "已取消按键学习"
    }

    func resetBindingsToPhysicalFunctionKeys() {
        configuration.keyBindings = configuration.hardwareProfileInstalled == true
            ? BridgeConfiguration.hardwareProfileBindings : BridgeConfiguration.defaultBindings
        learningBindingIndex = nil
        pendingLearningEvent = nil
        deviceManager.calibrationMode = false
        persistConfiguration()
        lastMessage = "已恢复为实体 F1–F12 默认映射"
    }

    private func consumeLearningEvent(_ event: HIDEvent) -> Bool {
        guard let index = learningBindingIndex,
              configuration.keyBindings.indices.contains(index) else { return false }
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
            lastMessage = "已识别 \(KeyBinding(usagePage: event.usagePage, usage: normalizedUsage, action: configuration.keyBindings[index].action).displayName)，松开按键即可保存"
            return true
        }
        guard let learnedEvent = pendingLearningEvent else { return true }
        let isArrayRelease = event.usagePage == 0x07
            && event.usage == KeyBinding.hidArrayUsageSentinel
        guard isArrayRelease || (
            learnedEvent.usagePage == event.usagePage
                && learnedEvent.usage == event.usage
        ) else { return true }

        let previous = configuration.keyBindings[index]
        if let duplicate = configuration.keyBindings.indices.first(where: {
            $0 != index && configuration.keyBindings[$0].usagePage == learnedEvent.usagePage
                && configuration.keyBindings[$0].usage == learnedEvent.usage
        }) {
            configuration.keyBindings[duplicate].usagePage = previous.usagePage
            configuration.keyBindings[duplicate].usage = previous.usage
        }
        configuration.keyBindings[index].usagePage = learnedEvent.usagePage
        configuration.keyBindings[index].usage = learnedEvent.usage
        let learnedName = configuration.keyBindings[index].displayName
        learningBindingIndex = nil
        pendingLearningEvent = nil
        deviceManager.calibrationMode = false
        persistConfiguration()
        lastMessage = "已学习 \(learnedName) → \(configuration.keyBindings[index].action.displayName)"
        showOverlay("按键已学习", detail: "\(learnedName) → \(configuration.keyBindings[index].action.displayName)")
        return true
    }

    func refreshLighting() {
        guard !lightingBusy else { return }
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
                    // D5 is the capability required for lighting. Some U1
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
                lightingMessage = "\(connection.displayName) 灯光通道已就绪"
                configuration.lighting.usbDynamic = .verified
                configuration.lighting.usbSingleKey = .unavailable
                configuration.lighting.bluetoothDynamic = .blocked
                configuration.lighting.bluetoothSingleKey = .blocked
                configuration.lighting.reason = "USB-C 与 U1 2.4G 接收器支持整键背光和侧灯；当前固件未提供蓝牙实时配置通道"
                failedAgentSignalLights = nil
            } catch {
                lightingAvailable = false
                lightingMessage = connection == .twoPointFourGHzReceiver
                    ? "2.4G 接收器已插入，但键盘没有响应灯光指令；请确认已切到 2.4G，并按任意键唤醒。\(error.localizedDescription)"
                    : error.localizedDescription
            }
            lightingBusy = false
            if configuration.agentLightingEnabled == true { syncAgentLighting() }
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
        currentLightingDriver?.preferConnection(connection)
        guard lightingConnection != connection else { return }
        lightingConnection = connection
        lightingAvailable = false
        sleepConfiguration = nil
        lastAgentSignalLights = nil
        failedAgentSignalLights = nil
    }

    func setKeyboardLightStayOnMinutes(_ minutes: Int?) {
        guard !lightingBusy else { return }
        guard lightingConnection == .usbCable else {
            lightingMessage = "灯光保持时间属于键盘管理设置，请连接 USB-C 后修改；F1–F6 状态灯不受影响"
            return
        }
        guard let controller = currentSleepDriver else {
            lightingMessage = "当前键盘尚无经过实机验证的休眠设置驱动"
            return
        }
        let fingerprint = devices.first(where: {
            $0.isRecognized && $0.transports.contains(.usb) && $0.profileID == controller.profileID
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

    func setBacklightBrightness(_ value: Int) {
        runLightingWrite(label: "背光亮度已设为 \(value)%") { controller in
            try controller.setBacklight(mode: nil, brightness: value, color: nil)
        }
    }

    func setSidelightBrightness(_ value: Int) {
        runLightingWrite(label: "侧灯亮度已设为 \(value)%") { controller in
            try controller.setSidelight(mode: nil, brightness: value, color: nil)
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
            lightingMessage = "颜色已保存；连接 USB-C 后会自动应用到 F1–F6"
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
        guard let saved = userSignalLights else {
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
                userSignalLights = nil
                lastAgentSignalLights = nil
                lightingMessage = "已恢复进入 Codex 模式前的 F1–F6 灯光"
            } catch {
                lightingMessage = "F1–F6 灯光恢复失败：\(error.localizedDescription)"
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
                                $0.isRecognized && $0.transports.contains(.usb) && $0.profileID == controller.profileID
                            })?.fingerprint
                        )
                    }
                }
                lightingStates = result.1
                lightingAvailable = true
                lightingMessage = "\(label)；键盘已回读确认"
                succeeded = true
            } catch {
                lightingAvailable = false
                lightingConnection = controller.detectedConnection()
                lightingMessage = "灯光设置失败：\(error.localizedDescription)"
            }
            lightingBusy = false
            completion?(succeeded, beforeStates)
            if configuration.agentLightingEnabled == true { syncAgentLighting() }
        }
    }

    private func syncAgentLighting() {
        guard configuration.agentLightingEnabled == true, lightingAvailable, !lightingBusy else { return }
        if configuration.sidelightRestoredAfterSignalLights != true {
            restoreLegacyAgentSidelight()
            return
        }
        syncAgentSignalLights()
    }

    private func restoreLegacyAgentSidelight() {
        guard !lightingBusy, let controller = currentLightingDriver else { return }
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
        let taskLights = Air75V3LightingController.taskSignalLightIndices.enumerated().compactMap {
            (taskIndex, lightIndex) -> Air75SignalLight? in
            let state = taskIndex < codexTasks.count ? codexTasks[taskIndex].state : .idle
            guard let color = Air75RGBColor(hex: taskLightColorHex(for: state)) else { return nil }
            return Air75SignalLight(index: lightIndex, color: color)
        }
        // 0.10.0 accidentally wrote task 1 to index 0 (Esc). D8 colors
        // persist until explicitly replaced, so every sync clears that stale
        // indicator while writing the six real F-row indexes.
        let escapeOff = Air75SignalLight(
            index: Air75V3LightingController.escapeSignalLightIndex,
            color: Air75RGBColor(red: 0, green: 0, blue: 0)
        )
        return [escapeOff] + taskLights
    }

    private func syncAgentSignalLights() {
        guard configuration.agentLightingEnabled == true, lightingAvailable, !lightingBusy else { return }
        let desired = desiredAgentSignalLights()
        guard desired.count == 7, lastAgentSignalLights != desired,
              failedAgentSignalLights != desired,
              let controller = currentLightingDriver else { return }

        lightingBusy = true
        lightingMessage = "正在同步 F1–F6 六个任务状态…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let before = try? controller.readSignalLights(
                        indices: Air75V3LightingController.taskSignalLightIndices
                    )
                    let written = try controller.setSignalLights(desired)
                    return (before, written)
                }.value
                if userSignalLights == nil, let before = result.0, before.count == 6 {
                    userSignalLights = before
                }
                lastAgentSignalLights = result.1
                failedAgentSignalLights = nil
                if lightingConnection == .twoPointFourGHzReceiver {
                    configuration.lighting.bluetoothSingleKey = .verified
                } else {
                    configuration.lighting.usbSingleKey = .verified
                }
                persistConfiguration()
                lightingMessage = "F1–F6 已分别同步六个 Codex 任务状态；侧灯保持官方灯效"
            } catch {
                failedAgentSignalLights = desired
                lightingMessage = "F1–F6 指示灯写入失败；侧灯不受影响：\(error.localizedDescription)"
            }
            lightingBusy = false
            if failedAgentSignalLights == nil { syncAgentLighting() }
        }
    }

    private func applyDesktopTaskSnapshots(_ snapshots: [CodexTaskLightSnapshot]) {
        codexTasks = Array(snapshots.prefix(CodexDesktopStatusObserver.maximumTaskCount))
        // Aggregate remains useful for compact software summaries; hardware
        // status is represented independently by F1-F6 from schema 8 onward.
        codexTopTaskLightState = CodexTaskLightAggregator.aggregate(codexTasks.map(\.state))
        codexTopTaskID = codexTasks.first?.threadID
        for index in slots.indices {
            if index < codexTasks.count {
                let snapshot = codexTasks[index]
                slots[index].sessionId = snapshot.threadID
                slots[index].state = Self.slotState(for: snapshot.state)
                slots[index].isWaitingForApproval = snapshot.state == .waitingForConfirmation
                slots[index].hasError = snapshot.state == .error
                if let eventDate = snapshot.eventDate { slots[index].updatedAt = eventDate }
            } else {
                slots[index].sessionId = nil
                slots[index].state = .noAssignment
                slots[index].isWaitingForApproval = false
                slots[index].hasError = false
            }
        }
        syncAgentLighting()
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
        mappingEngine.configuration = configuration
        deviceManager.configuration = configuration
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
            keyBindings: configuration.keyBindings
        )
        UserDefaults.standard.set(dedicatedEventSuppressionActive, forKey: "DedicatedEventSuppressionActive")
    }

    private func perform(_ action: BridgeAction, event: HIDEvent, phase: KeyPhase) {
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
