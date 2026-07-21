import XCTest
@testable import Air75AgentBridgeCore

final class CoreTests: XCTestCase {
    func testCodexThreadListNameIsAuthoritativeTitle() throws {
        let data = """
        {"id":2,"result":{"data":[
          {"id":"thread-1","name":"构建 Air75 Agent Bridge macOS 应用","preview":"旧的首条输入"},
          {"id":"thread-2","name":"  ","preview":"不要作为标题"},
          {"id":"thread-3","name":null,"preview":"也不要作为标题"}
        ]}}
        """.data(using: .utf8)!
        let appServerTitles = CodexThreadListTitleIndex.titles(in: data)
        XCTAssertEqual(appServerTitles, ["thread-1": "构建 Air75 Agent Bridge macOS 应用"])
        XCTAssertEqual(
            CodexSidebarTitleIndex.preferredTitle(
                for: "thread-1",
                indexedTitle: "旧数据库标题",
                sidebarTitles: ["thread-1": "旧描述"],
                appServerTitles: appServerTitles
            ),
            "构建 Air75 Agent Bridge macOS 应用"
        )
    }

    func testCodexSidebarTitlesOverrideIndexedTitles() throws {
        let data = """
        {"wrapper":{"thread-descriptions-v1":{
          "thread-1":"左侧栏名称",
          "thread-2":"  ",
          "thread-3":"Renamed task"
        }}}
        """.data(using: .utf8)!
        let titles = CodexSidebarTitleIndex.titles(in: data)
        XCTAssertEqual(titles, ["thread-1": "左侧栏名称", "thread-3": "Renamed task"])
        XCTAssertEqual(
            CodexSidebarTitleIndex.preferredTitle(
                for: "thread-1", indexedTitle: "旧标题", sidebarTitles: titles
            ),
            "左侧栏名称"
        )
        XCTAssertEqual(
            CodexSidebarTitleIndex.preferredTitle(
                for: "thread-2", indexedTitle: "数据库兜底", sidebarTitles: titles
            ),
            "数据库兜底"
        )
    }

    func testCodexKeybindingInstallerPreservesExistingBindingsAndInstallsDirectCommands() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let original = """
        [
          {"command":"custom.command","key":"Command+Y"},
          {"command":"newThread","key":"Command+O"},
          {"command":"someone.else","key":"F13"}
        ]
        """.data(using: .utf8)!
        try original.write(to: codexHome.appendingPathComponent("keybindings.json"))

        let installer = CodexKeybindingInstaller(codexHome: codexHome, backupDirectory: backups)
        let result = try installer.install()
        XCTAssertTrue(result.changed)
        XCTAssertNotNil(result.backupURL)
        XCTAssertTrue(installer.isInstalled())

        let data = try Data(contentsOf: installer.keybindingsURL)
        let bindings = try JSONDecoder().decode([CodexKeybinding].self, from: data)
        XCTAssertTrue(bindings.contains(.init(command: "custom.command", key: "Command+Y")))
        XCTAssertTrue(bindings.contains(.init(command: "thread1", key: "Command+1")))
        XCTAssertTrue(bindings.contains(.init(command: "someone.else", key: "F13")))
        XCTAssertFalse(bindings.contains(.init(command: "thread1", key: "F13")))
        XCTAssertTrue(bindings.contains(.init(command: "composer.startDictation", key: "F11")))
        XCTAssertTrue(bindings.contains(.init(command: "composer.startDictation", key: "Ctrl+Shift+D")))
        XCTAssertTrue(bindings.contains(.init(command: "composer.increaseReasoningEffort", key: "Ctrl+Alt+Command+]")))
        XCTAssertTrue(bindings.contains(.init(command: "newTask", key: "Command+N")))
    }

    func testUSBIdentityRequiresVIDPIDAndProduct() {
        let profile = DeviceProfile(
            schemaVersion: 1,
            model: "Air75 V3",
            usbIdentities: [.init(vendorID: 0x19F5, productID: 0x1028)],
            bluetoothVendorIDs: [0x07D7],
            productAliases: ["Air75 V3"],
            manufacturerAliases: ["NuPhy"],
            allowedUsagePages: [1],
            specialUsages: Array(0x3A...0x45)
        )
        let match = DeviceFingerprintMatcher.classify(
            vendorID: 0x19F5, productID: 0x1028, product: "Air75 V3", manufacturer: "NuPhy",
            transport: .usb, usagePage: 1, usage: 6, profile: profile, confirmedFingerprint: nil
        )
        if case .recognized(let confidence) = match { XCTAssertEqual(confidence, 100) }
        else { XCTFail("Expected exact USB recognition") }

        let rejection = DeviceFingerprintMatcher.classify(
            vendorID: 1, productID: 2, product: "Air75 V3", manufacturer: "Unknown",
            transport: .usb, usagePage: 1, usage: 6, profile: profile, confirmedFingerprint: nil
        )
        if case .rejected = rejection {} else { XCTFail("Name-only recognition must be rejected") }
    }

    func testDefaultBindingsUsePhysicalF1ThroughF12() {
        XCTAssertEqual(BridgeConfiguration.defaultBindings.map(\.usage), Array(0x3A...0x45))
        XCTAssertEqual(BridgeConfiguration.defaultBindings.count, 12)
    }

    func testReasoningClamps() {
        var level = ReasoningLevel.minimal
        level.step(-1)
        XCTAssertEqual(level, .minimal)
        level.step(99)
        XCTAssertEqual(level, .xhigh)
    }

    func testSidelightBrightnessUsesByteRangeAndPercentageUI() {
        XCTAssertEqual(Air75LightingState.sidelightPercent(from: 0xC0), 75)
        XCTAssertEqual(Air75LightingState.sidelightRawValue(fromPercent: 75), 0xBF)
        XCTAssertEqual(Air75LightingState.sidelightRawValue(fromPercent: 100), 0xFF)
    }

    func testNewFirmwareIndicatorModeParses() throws {
        let state = try Air75LightingState(
            handle: 0,
            raw: [0x15, 0x64, 0x02, 0x00, 0x01, 0x00, 0x00, 0x09,
                  0xFF, 0x02, 0xFF, 0x02, 0x00, 0x00, 0xFF, 0xFF, 0xFF]
        )
        XCTAssertEqual(state.backlight.mode, Air75BacklightMode.signalIndicator.rawValue)
        XCTAssertEqual(state.sidelight.mode, Air75SidelightMode.staticColor.rawValue)
    }

    func testD8SignalLightPayloadMatchesFirmwareProtocol() {
        let lights = [
            Air75SignalLight(index: 0, color: Air75RGBColor(red: 0xFF, green: 0, blue: 0)),
            Air75SignalLight(index: 1, color: Air75RGBColor(red: 0, green: 0xFF, blue: 0))
        ]
        XCTAssertEqual(lights.flatMap(\.encodedBytes),
                       [0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0xFF, 0x00])
        XCTAssertEqual(Air75V3LightingController.escapeSignalLightIndex, 0)
        XCTAssertEqual(Air75V3LightingController.taskSignalLightIndices, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(SignalLightLayout.staleManagedIndices(layoutID: "nuphy.air75-v3.ansi-d8"), [30])
    }

    func testLegacyF13ConfigurationMigratesToPhysicalKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(baseURL: root)
        var legacy = BridgeConfiguration()
        legacy.schemaVersion = 1
        legacy.keyBindings = zip(0x68...0x73, BridgeConfiguration.defaultBindings.map(\.action)).map {
            KeyBinding(usagePage: 0x07, usage: $0.0, action: $0.1)
        }
        try store.save(legacy)
        let migrated = store.load()
        XCTAssertEqual(migrated.schemaVersion, 14)
        XCTAssertEqual(migrated.keyBindings.map(\.usage), Array(0x3A...0x45))
        XCTAssertEqual(migrated.agentLightingEnabled, true)
        XCTAssertFalse(migrated.overlayEnabled)
        XCTAssertEqual(migrated.resolvedTaskLightPalette, .default)
        XCTAssertEqual(migrated.sidelightRestoredAfterSignalLights, false)
        XCTAssertEqual(migrated.resolvedAgentSourceMode, .recent)
    }

    func testSchema13RepairsExactAir75MixedFirstRunBindingsOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(baseURL: root)
        var corrupted = BridgeConfiguration()
        corrupted.schemaVersion = 12
        corrupted.setHardwareProfileState(
            InstalledHardwareProfileState(installed: true),
            for: "nuphy.air75-v3"
        )
        var corruptedBindings = BridgeConfiguration.hardwareProfileBindings
        corruptedBindings[1].usage = 0x6A // F15 instead of F14
        corruptedBindings[2].usage = 0x2B // Tab instead of F15
        corrupted.setBindings(corruptedBindings, for: "nuphy.air75-v3")
        try store.save(corrupted)

        let repaired = store.load()
        XCTAssertEqual(repaired.schemaVersion, 14)
        XCTAssertEqual(repaired.bindings(for: "nuphy.air75-v3").map(\.usage), Array(0x68...0x73))

        var custom = BridgeConfiguration.hardwareProfileBindings
        custom[2].usage = 0x14 // A genuine learned Q binding must survive.
        XCTAssertEqual(
            BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
                custom,
                hardwareProfileInstalled: true
            ),
            custom
        )
    }

    func testSchema14AlsoRepairsCorruptionAlreadySavedAsSchema13() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(baseURL: root)
        var corrupted = BridgeConfiguration()
        corrupted.schemaVersion = 13
        var mixed = BridgeConfiguration.hardwareProfileBindings
        mixed[1].usage = 0x6A
        mixed[2].usage = 0x2B
        corrupted.setHardwareProfileState(
            InstalledHardwareProfileState(installed: true),
            for: "nuphy.air75-v3"
        )
        corrupted.setBindings(mixed, for: "nuphy.air75-v3")
        try store.save(corrupted)

        let repaired = store.load()
        XCTAssertEqual(repaired.schemaVersion, 14)
        XCTAssertEqual(
            repaired.bindings(for: "nuphy.air75-v3").map(\.usage),
            Array(0x68...0x73)
        )
    }

    func testProfileRegistrySelectsExactModelAndGatesHardwareDrivers() {
        let softwareOnly = DeviceProfile(
            schemaVersion: 2, model: "NuPhy Future",
            usbIdentities: [.init(vendorID: 0x19F5, productID: 0x9000)],
            bluetoothVendorIDs: [0x19F5], productAliases: ["NuPhy Future"],
            manufacturerAliases: ["NuPhy"], allowedUsagePages: [1], specialUsages: [],
            id: "nuphy.future", protocolFamily: .softwareOnly,
            capabilities: .init()
        )
        let registry = DeviceProfileRegistry(profiles: [.air75V3Fallback, softwareOnly])
        let match = registry.bestMatch(
            vendorID: 0x19F5, productID: 0x9000, product: "NuPhy Future", manufacturer: "NuPhy",
            transport: .usb, usagePage: 1, usage: 6, confirmedFingerprint: nil
        )
        XCTAssertEqual(match?.profile.profileID, "nuphy.future")
        XCTAssertNil(KeyboardDriverRegistry.keymapDriver(for: match?.profile))
        XCTAssertNil(KeyboardDriverRegistry.lightingDriver(for: match?.profile))
        XCTAssertNotNil(KeyboardDriverRegistry.keymapDriver(for: .air75V3Fallback))
        XCTAssertNotNil(KeyboardDriverRegistry.lightingDriver(for: .air75V3Fallback))
    }

    func testHardwareProfileUsesUniqueTopRowAndKnobEvents() throws {
        var bytes = [UInt8](repeating: 0, count: Air75V3KeymapController.keymapByteCount)
        func set(_ value: UInt16, _ entry: Int) {
            bytes[entry * 2] = UInt8(value >> 8)
            bytes[entry * 2 + 1] = UInt8(value & 0xFF)
        }
        for layer in 0..<8 {
            set(0x00A8, layer * 98 + 60)
            set(0x00AA, layer * 98 + 96)
            set(0x00A9, layer * 98 + 97)
        }
        let result = try Air75V3KeymapController().makeBridgeProfile(from: bytes)
        func get(_ entry: Int) -> UInt16 {
            (UInt16(result[entry * 2]) << 8) | UInt16(result[entry * 2 + 1])
        }
        XCTAssertEqual((1...12).map { get($0) }, Array(0x68...0x73).map(UInt16.init))
        XCTAssertEqual(get(60), 0x0048)
        XCTAssertEqual(get(96), 0x0047)
        XCTAssertEqual(get(97), 0x0046)
        XCTAssertTrue(Air75V3KeymapController.hasBridgeProfile(result))
        XCTAssertFalse(Air75V3KeymapController.hasBridgeProfile(bytes))
    }

    func testCustomBindingsSurviveHardwareProfileInstallAndRestore() {
        var bindings = BridgeConfiguration.defaultBindings
        bindings[0].usage = 0x1E // number row 1
        bindings[1].usage = 0x05 // B

        let installed = BridgeConfiguration.bindingsForInstalledHardwareProfile(bindings)
        XCTAssertEqual(installed[0].usage, 0x1E)
        XCTAssertEqual(installed[1].usage, 0x05)
        XCTAssertEqual(installed[2].usage, 0x6A)

        let restored = BridgeConfiguration.bindingsForOriginalHardwareProfile(installed)
        XCTAssertEqual(restored.map(\.usage), bindings.map(\.usage))
        XCTAssertEqual(bindings[0].displayName, "1")
        XCTAssertEqual(bindings[1].displayName, "B")
    }

    func testTaskLightPaletteCanBeCustomized() {
        var palette = CodexTaskLightPalette.default
        palette.setColorHex("#123456", for: .reasoning)
        XCTAssertEqual(palette.colorHex(for: .reasoning), "#123456")
        XCTAssertEqual(palette.colorHex(for: .error), "#FF453A")
    }

    func testCodexRolloutFiveStateParsing() throws {
        let started = """
        {"timestamp":"2026-07-19T05:00:00.000Z","type":"session_meta","payload":{"session_id":"thread-1","thread_source":"user"}}
        {"timestamp":"2026-07-19T05:00:01.000Z","type":"event_msg","payload":{"type":"task_started"}}
        """.data(using: .utf8)!
        let now = ISO8601DateFormatter().date(from: "2026-07-19T05:00:10Z")!
        let running = CodexRolloutStatusParser.parse(data: started, now: now)
        XCTAssertEqual(running.threadID, "thread-1")
        XCTAssertEqual(running.state, .reasoning)
        XCTAssertEqual(running.state.colorHex, "#168BFF")

        let waiting = started + Data("\n{\"timestamp\":\"2026-07-19T05:00:02.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call\",\"name\":\"request_user_input\",\"status\":\"completed\"}}".utf8)
        XCTAssertEqual(CodexRolloutStatusParser.parse(data: waiting, now: now).state, .waitingForConfirmation)

        let resumed = waiting + Data("\n{\"timestamp\":\"2026-07-19T05:00:03.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call_output\"}}".utf8)
        XCTAssertEqual(CodexRolloutStatusParser.parse(data: resumed, now: now).state, .reasoning)

        let completed = started + Data("\n{\"timestamp\":\"2026-07-19T05:00:04.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}".utf8)
        XCTAssertEqual(CodexRolloutStatusParser.parse(data: completed, now: now).state, .complete)
        let later = now.addingTimeInterval(CodexRolloutStatusParser.completionVisibleDuration + 1)
        XCTAssertEqual(CodexRolloutStatusParser.parse(data: completed, now: later).state, .idle)

        let failed = started + Data("\n{\"timestamp\":\"2026-07-19T05:00:05.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"error\"}}".utf8)
        XCTAssertEqual(CodexRolloutStatusParser.parse(data: failed, now: now).state, .error)

        let staleReasoning = CodexTaskLightSnapshot(
            threadID: "thread-1",
            state: .reasoning,
            eventDate: now.addingTimeInterval(-CodexRolloutStatusParser.reasoningStaleDuration - 1)
        )
        XCTAssertEqual(
            CodexRolloutStatusParser.applyDecay(
                to: staleReasoning,
                now: now,
                preserveUnreadCompletion: true
            ).state,
            .idle
        )
        let staleUnreadCompletion = CodexTaskLightSnapshot(
            threadID: "thread-1",
            state: .complete,
            eventDate: now.addingTimeInterval(-CodexRolloutStatusParser.completionVisibleDuration - 1)
        )
        XCTAssertEqual(
            CodexRolloutStatusParser.applyDecay(
                to: staleUnreadCompletion,
                now: now,
                preserveUnreadCompletion: true
            ).state,
            .complete
        )
    }

    func testIndicatorModeInitializationIsTrackedPerModel() {
        var configuration = BridgeConfiguration()
        XCTAssertFalse(configuration.hasInitializedIndicatorMode(for: "nuphy.air75-v3"))
        configuration.markIndicatorModeInitialized(for: "nuphy.air75-v3")
        XCTAssertTrue(configuration.hasInitializedIndicatorMode(for: "nuphy.air75-v3"))
    }

    func testCodexDesktopConfirmationCardAndActiveThreadParsing() {
        let log = """
        ignored line
        thread_stream_view_activity_changed active=true conversationId=thread-a rendererWindowId=1
        thread_stream_view_activity_changed active=false conversationId=thread-a rendererWindowId=1
        thread_stream_view_activity_changed active=true conversationId=thread-b rendererWindowId=1
        """
        XCTAssertEqual(CodexDesktopConfirmationState.activeThreadID(in: log), "thread-b")
        XCTAssertTrue(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation([
            "暂不 Esc", "安装 ↵"
        ]))
        XCTAssertTrue(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation([
            "Decline", "Approve once", "Always allow"
        ]))
        XCTAssertTrue(CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation([
            "安装 ↵"
        ]))
        XCTAssertFalse(CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation([
            "继续", "新建任务"
        ]))
        XCTAssertFalse(CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation([
            "请求批准"
        ]))
        XCTAssertFalse(CodexDesktopConfirmationState.buttonLabelsContainConfirmationAction([
            "Request approval"
        ]))
        XCTAssertFalse(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation([
            "请求批准", "取消"
        ]))
        XCTAssertFalse(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation([
            "Request approval", "Cancel"
        ]))
        XCTAssertFalse(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation([
            "搜索", "新建任务", "插件"
        ]))
    }
}

private func + (lhs: Data, rhs: Data) -> Data {
    var result = lhs
    result.append(rhs)
    return result
}
