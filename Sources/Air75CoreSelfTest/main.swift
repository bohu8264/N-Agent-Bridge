import Air75AgentBridgeCore
import Foundation
import SQLite3

if let argumentIndex = CommandLine.arguments.firstIndex(of: "--verify-app-bundle"),
   CommandLine.arguments.indices.contains(argumentIndex + 1) {
    let appPath = CommandLine.arguments[argumentIndex + 1]
    guard let appBundle = Bundle(path: appPath) else {
        fputs("Invalid app bundle: \(appPath)\n", stderr)
        exit(EXIT_FAILURE)
    }
    let expectedProfiles = [("Air75V3.json", "nuphy.air75-v3")]
    let profileBundleURL = appBundle.resourceURL?
        .appendingPathComponent("Air75AgentBridge_Air75AgentBridgeCore.bundle", isDirectory: true)
    let registry = DeviceProfileRegistry.loadBundled(applicationBundle: appBundle)
    for (filename, profileID) in expectedProfiles {
        guard let profileURL = profileBundleURL?.appendingPathComponent(filename),
              let profileData = try? Data(contentsOf: profileURL),
              let packagedProfile = try? JSONDecoder().decode(DeviceProfile.self, from: profileData),
              packagedProfile.profileID == profileID,
              registry.profile(id: profileID) != nil else {
            fputs("Packaged device profile \(profileID) could not be loaded from \(appPath)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
    print("APP BUNDLE RESOURCE TEST PASSED")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--migrate-configuration") {
    let store = ConfigurationStore()
    let configuration = store.load()
    do {
        try store.save(configuration)
        print("CONFIGURATION MIGRATED schema=\(configuration.schemaVersion) sidelight=\(configuration.agentLightingEnabled == true) overlay=\(configuration.overlayEnabled)")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Configuration migration failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.contains("--codex-six-task-dry-run") {
    let codexHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)
    let reader = CodexThreadIndexReader(codexHome: codexHome)
    guard let databaseURL = reader.currentDatabaseURL() else {
        fputs("未找到 ~/.codex/state_<N>.sqlite；Codex Desktop 是否安装并运行过？\n", stderr)
        exit(EXIT_FAILURE)
    }
    print("INDEX \(databaseURL.lastPathComponent)")
    let entries = reader.topUserThreads(limit: 6)
    if entries.isEmpty { print("NO USER THREADS") ; exit(EXIT_SUCCESS) }
    for (index, entry) in entries.enumerated() {
        let url = reader.rolloutURL(for: entry)
        var snapshot = CodexTaskLightSnapshot(threadID: entry.threadID, state: .idle, eventDate: nil)
        if let handle = try? FileHandle(forReadingFrom: url),
           let size = try? handle.seekToEnd() {
            let start = size > 1_500_000 ? size - 1_500_000 : 0
            try? handle.seek(toOffset: start)
            if let data = try? handle.readToEnd() {
                snapshot = CodexRolloutStatusParser.parse(data: data)
            }
            try? handle.close()
        }
        let idPrefix = String(entry.threadID.prefix(8))
        let age = snapshot.eventDate.map { String(format: "%.0fs前", -$0.timeIntervalSinceNow) } ?? "无事件时间"
        print("F\(index + 1)  \(idPrefix)…  \(snapshot.state.rawValue)  (\(snapshot.state.displayName), \(age))")
    }
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--install-codex-keybindings") {
    do {
        let result = try CodexKeybindingInstaller().install()
        print("CODEX KEYBINDINGS \(result.changed ? "INSTALLED" : "VERIFIED")")
        print(result.keybindingsURL.path)
        if let backupURL = result.backupURL { print("BACKUP \(backupURL.path)") }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Codex keybinding install failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

struct SelfTestFailure: Error { let message: String }
var failures: [String] = []

final class ActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [BridgeAction] = []

    func append(_ action: BridgeAction) {
        lock.lock()
        recorded.append(action)
        lock.unlock()
    }

    var actions: [BridgeAction] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() { print("PASS  \(name)") }
    else { print("FAIL  \(name)"); failures.append(name) }
}

let profile = DeviceProfile(
    schemaVersion: 1,
    model: "Air75 V3",
    usbIdentities: [.init(vendorID: 0x19F5, productID: 0x1028)],
    bluetoothVendorIDs: [0x07D7],
    productAliases: ["Air75 V3", "Air75 V3-2"],
    manufacturerAliases: ["NuPhy"],
    allowedUsagePages: [1, 7, 12],
    specialUsages: Array(0x3A...0x45)
)

let usbMatch = DeviceFingerprintMatcher.classify(
    vendorID: 0x19F5, productID: 0x1028, product: "Air75 V3", manufacturer: "NuPhy",
    transport: .usb, usagePage: 1, usage: 6, profile: profile, confirmedFingerprint: nil
)
if case .recognized(let confidence) = usbMatch { check(confidence == 100, "exact USB identity") }
else { check(false, "exact USB identity") }

let impostor = DeviceFingerprintMatcher.classify(
    vendorID: 1, productID: 2, product: "Air75 V3", manufacturer: "Unknown",
    transport: .usb, usagePage: 1, usage: 6, profile: profile, confirmedFingerprint: nil
)
if case .rejected = impostor { check(true, "rejects name-only impostor") }
else { check(false, "rejects name-only impostor") }

check(BridgeConfiguration.defaultBindings.map(\.usage) == Array(0x3A...0x45), "physical F1-F12 default usages")
check(Set(BridgeConfiguration.defaultBindings.map(\.action)).count == 12, "unique default actions")
check(Air75V3LightingController.preferredConnection(
    forProductIDs: [Air75V3LightingController.dongleProductID]
) == .twoPointFourGHzReceiver, "U1 dongle selects 2.4G lighting connection")
check(Air75V3LightingController.preferredConnection(
    forProductIDs: [Air75V3LightingController.dongleProductID, Air75V3LightingController.productID]
) == .usbCable, "wired lighting connection takes priority over U1 dongle")
check(Air75V3LightingController.preferredConnection(forProductIDs: [0xFFFF]) == nil,
      "unknown receiver cannot gain lighting write capability")
check(Air75V3LightingController().writableLightingHandles == [0],
      "Air75 V3 writes only the active macOS lighting profile")
var customBindings = BridgeConfiguration.defaultBindings
customBindings[0].usage = 0x1E
let installedBindings = BridgeConfiguration.bindingsForInstalledHardwareProfile(customBindings)
check(installedBindings[0].usage == 0x1E && installedBindings[1].usage == 0x69,
      "custom key survives hardware-profile conversion")
check(BridgeConfiguration.bindingsForOriginalHardwareProfile(installedBindings).map(\.usage)
        == customBindings.map(\.usage),
      "custom key survives original-profile restoration")
var airConfiguration = BridgeConfiguration()
airConfiguration.setHardwareProfileState(
    InstalledHardwareProfileState(installed: true, backupName: "air-original.json"),
    for: "nuphy.air75-v3"
)
airConfiguration.setBindings(BridgeConfiguration.hardwareProfileBindings, for: "nuphy.air75-v3")
check(airConfiguration.bindings(for: "nuphy.air75-v3").map(\.usage) == Array(0x68...0x73),
      "keeps installed Air75 hardware-profile usages")
check(!KeyBinding.isSupportedInputSource(
    usagePage: 0x07,
    usage: KeyBinding.hidArrayUsageSentinel
), "rejects HID keyboard-array sentinel as binding")
check(KeyBinding.normalizedLearnableUsage(
    usagePage: 0x07,
    usage: KeyBinding.hidArrayUsageSentinel,
    value: 0x68
) == 0x68, "normalizes valid usage carried by HID array value")
check(KeyBinding.normalizedLearnableUsage(
    usagePage: 0x07,
    usage: KeyBinding.hidArrayUsageSentinel,
    value: 1
) == nil, "rejects non-key HID array placeholder value")
var sentinelConfiguration = BridgeConfiguration()
sentinelConfiguration.enabled = true
sentinelConfiguration.codexModeEnabled = true
sentinelConfiguration.keyBindings = [
    KeyBinding(
        usagePage: 0x07,
        usage: KeyBinding.hidArrayUsageSentinel,
        action: .agent1
    )
]
let sentinelEngine = MappingEngine(configuration: sentinelConfiguration)
let sentinelRecorder = ActionRecorder()
sentinelEngine.actionHandler = { action, _, _ in sentinelRecorder.append(action) }
sentinelEngine.handle(HIDEvent(
    deviceID: "test",
    transport: .usb,
    usagePage: 0x07,
    usage: KeyBinding.hidArrayUsageSentinel,
    value: 0x04
))
check(sentinelRecorder.actions.isEmpty,
      "runtime mapping ignores persisted HID array sentinel")
var customPalette = CodexTaskLightPalette.default
customPalette.setColorHex("#123456", for: .reasoning)
check(customPalette.colorHex(for: .reasoning) == "#123456",
      "custom task sidelight palette")
check(Air75LightingState.sidelightPercent(from: 0xC0) == 75,
      "sidelight 0-255 raw brightness converts to percent")
check(Air75LightingState.sidelightRawValue(fromPercent: 75) == 0xBF,
      "sidelight percent converts to 0-255 raw brightness")
do {
    let state = try Air75LightingState(
        handle: 0,
        raw: [0x15, 0x64, 0x02, 0x00, 0x01, 0x00, 0x00, 0x09,
              0xFF, 0x02, 0xFF, 0x02, 0x00, 0x00, 0xFF, 0xFF, 0xFF]
    )
    check(state.backlight.mode == Air75BacklightMode.signalIndicator.rawValue,
          "new firmware backlight mode 0x15 is accepted")
} catch {
    check(false, "new firmware lighting state parses: \(error.localizedDescription)")
}
let d8Example = [
    Air75SignalLight(index: 0, color: Air75RGBColor(red: 0xFF, green: 0, blue: 0)),
    Air75SignalLight(index: 1, color: Air75RGBColor(red: 0, green: 0xFF, blue: 0))
].flatMap(\.encodedBytes)
check(d8Example == [0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0xFF, 0x00],
      "D8 signal light payload matches firmware protocol")

let handshakeChallenge = (0..<NuPhyS4ProtocolCodec.maximumPayloadSize).map { UInt8($0) }
let deterministicHandshake = NuPhyS4ProtocolCodec.Handshake(challenge: handshakeChallenge)
check(deterministicHandshake.sessionKey == 20,
      "S4 handshake derives the official byte-20 session key")
check(deterministicHandshake.report[0] == 0x55
        && deterministicHandshake.report[1] == 0xEE
        && deterministicHandshake.report[28] == 20
        && deterministicHandshake.report[3] == NuPhyS4ProtocolCodec.checksum(deterministicHandshake.report),
      "S4 handshake report matches the official 0xEE layout")

let decodedLightState: [UInt8] = [
    0x15, 0x64, 0x03, 0x00, 0x00, 0x00, 0xC5, 0x5A, 0xF1,
    0x03, 0x00, 0x00, 0x01, 0x09, 0xFF, 0x00, 0x00,
]
let testSessionKey: UInt8 = 0xF8
func encryptedD5Response(encryptsHeader: Bool) -> [UInt8] {
    var response = [UInt8](repeating: 0, count: NuPhyS4ProtocolCodec.reportSize)
    response[0] = 0xAA
    response[1] = 0xD5
    let header: [UInt8] = [17, 0, 0, 0]
    response.replaceSubrange(4...7, with: encryptsHeader ? header.map { $0 ^ testSessionKey } : header)
    response.replaceSubrange(8..<(8 + decodedLightState.count),
                             with: decodedLightState.map { $0 ^ testSessionKey })
    response[3] = NuPhyS4ProtocolCodec.checksum(response)
    return response
}
do {
    let legacy = try NuPhyS4ProtocolCodec.decodeResponse(
        encryptedD5Response(encryptsHeader: true),
        command: 0xD5, length: 17, address: 0, handle: 0,
        sessionKey: testSessionKey
    )
    check(Array(legacy[8..<25]) == decodedLightState,
          "S4 decoder accepts legacy encrypted header and payload")
    let firmware10166 = try NuPhyS4ProtocolCodec.decodeResponse(
        encryptedD5Response(encryptsHeader: false),
        command: 0xD5, length: 17, address: 0, handle: 0,
        sessionKey: testSessionKey
    )
    check(Array(firmware10166[8..<25]) == decodedLightState,
          "S4 decoder accepts firmware 1.0.16.6 plain header with encrypted payload")
} catch {
    check(false, "S4 encrypted response compatibility: \(error)")
}
check(Air75V3LightingController.taskSignalLightIndices == [1, 2, 3, 4, 5, 6],
      "Air75 V3 F1-F6 use firmware indicator indexes 1-6; index 0 is Esc")
check(SignalLightLayout.staleManagedIndices(layoutID: "nuphy.air75-v3.ansi-d8") == [30],
      "Air75 V3 clears the stale Tab indicator left by the 0.13.1 binding bug")
check(SignalLightLayout.index(layoutID: "nuphy.air75-v3.ansi-d8", usagePage: 0x07, usage: 0x1E) == 16,
      "Air75 V3 number 1 resolves to official-layout light index")
check(SignalLightLayout.index(layoutID: "nuphy.air75-v3.ansi-d8", usagePage: 0x07, usage: 0x68) == 1,
      "Air75 V3 Bridge F13 source resolves to physical F1 light")
check(Air75V3LightingController.escapeSignalLightIndex == 0,
      "legacy task color can be explicitly cleared from Esc")

let sidebarMetadata = """
{
  "electron-persisted-atom-state": {
    "thread-descriptions-v1": {
      "thread-1": "Codex 左侧栏任务名",
      "thread-2": "  ",
      "thread-3": "Renamed task"
    }
  }
}
""".data(using: .utf8)!
let sidebarTitles = CodexSidebarTitleIndex.titles(in: sidebarMetadata)
check(sidebarTitles == ["thread-1": "Codex 左侧栏任务名", "thread-3": "Renamed task"],
      "Codex sidebar title metadata parses exact visible names")
check(CodexSidebarTitleIndex.preferredTitle(
    for: "thread-1", indexedTitle: "旧数据库标题", sidebarTitles: sidebarTitles
) == "Codex 左侧栏任务名", "Codex sidebar title overrides stale SQLite title")
check(CodexSidebarTitleIndex.preferredTitle(
    for: "thread-2", indexedTitle: "数据库兜底标题", sidebarTitles: sidebarTitles
) == "数据库兜底标题", "Codex SQLite title remains fallback")
let appServerThreadList = """
{"id":2,"result":{"data":[
  {"id":"thread-1","name":"构建 Air75 Agent Bridge macOS 应用","preview":"旧的首条输入"},
  {"id":"thread-2","name":"  ","preview":"不可作为任务名"}
]}}
""".data(using: .utf8)!
let appServerTitles = CodexThreadListTitleIndex.titles(in: appServerThreadList)
check(appServerTitles == ["thread-1": "构建 Air75 Agent Bridge macOS 应用"],
      "Codex app-server parses Thread.name without using preview")
check(CodexSidebarTitleIndex.preferredTitle(
    for: "thread-1", indexedTitle: "旧数据库标题",
    sidebarTitles: sidebarTitles, appServerTitles: appServerTitles
) == "构建 Air75 Agent Bridge macOS 应用",
      "Codex app-server Thread.name overrides all stale title fallbacks")

do {
    let current = try KeyboardSleepConfiguration(raw: [0x01, 0x06, 0x18])
    check(current.autoSleepEnabled && current.idleMinutes == 6 && current.deepSleepRawValue == 0x18,
          "S4 sleep payload parses official three fields")
    let alwaysOn = try current.settingAutoSleep(afterMinutes: nil)
    check(alwaysOn.raw == [0x00, 0x06, 0x18],
          "always-on disables auto sleep and preserves firmware fields")
    let sixtyMinutes = try current.settingAutoSleep(afterMinutes: 60)
    check(sixtyMinutes.raw == [0x01, 0x3C, 0x18],
          "sleep duration encodes minutes and preserves deep sleep")
    check((try? KeyboardSleepConfiguration(raw: [0x02, 0x06, 0x18])) == nil,
          "rejects invalid S4 sleep enable flag")
} catch {
    check(false, "S4 sleep configuration: \(error.localizedDescription)")
}

let rolloutNow = ISO8601DateFormatter().date(from: "2026-07-19T05:00:10Z")!
let runningRollout = """
{"timestamp":"2026-07-19T05:00:00.000Z","type":"session_meta","payload":{"session_id":"thread-1","thread_source":"user"}}
{"timestamp":"2026-07-19T05:00:01.000Z","type":"event_msg","payload":{"type":"task_started"}}
""".data(using: .utf8)!
let runningSnapshot = CodexRolloutStatusParser.parse(data: runningRollout, now: rolloutNow)
check(runningSnapshot.threadID == "thread-1" && runningSnapshot.state == .reasoning,
      "Codex rollout running state")
let waitingRollout = runningRollout + Data("\n{\"timestamp\":\"2026-07-19T05:00:02.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call\",\"name\":\"request_user_input\",\"status\":\"completed\"}}".utf8)
check(CodexRolloutStatusParser.parse(data: waitingRollout, now: rolloutNow).state == .waitingForConfirmation,
      "Codex user-input request enters confirmation state")
let namedConfirmationOutput = waitingRollout + Data("\n{\"timestamp\":\"2026-07-19T05:00:04.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call_output\",\"name\":\"request_user_input\",\"status\":\"completed\"}}".utf8)
check(CodexRolloutStatusParser.parse(data: namedConfirmationOutput, now: rolloutNow).state == .reasoning,
      "named confirmation output clears waiting state")
let unrelatedApprovalName = runningRollout + Data("\n{\"timestamp\":\"2026-07-19T05:00:04.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"agent_message\",\"name\":\"approval_policy\"}}".utf8)
check(CodexRolloutStatusParser.parse(data: unrelatedApprovalName, now: rolloutNow).state == .reasoning,
      "unrelated approval metadata does not request confirmation")
let tailWithoutStart = """
{"timestamp":"2026-07-19T05:00:06.000Z","type":"event_msg","payload":{"type":"agent_reasoning"}}
{"timestamp":"2026-07-19T05:00:07.000Z","type":"response_item","payload":{"type":"custom_tool_call","status":"completed","name":"exec"}}
{"timestamp":"2026-07-19T05:00:08.000Z","type":"response_item","payload":{"type":"custom_tool_call_output"}}
""".data(using: .utf8)!
check(CodexRolloutStatusParser.parse(data: tailWithoutStart, now: rolloutNow).state == .reasoning,
      "Codex long-task tail stays running after turn_started leaves read window")
let completeRollout = runningRollout + Data("\n{\"timestamp\":\"2026-07-19T05:00:04.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}".utf8)
check(CodexRolloutStatusParser.parse(data: completeRollout, now: rolloutNow).state == .complete,
      "Codex rollout completed state")
let completedAfterActivity = tailWithoutStart + Data("\n{\"timestamp\":\"2026-07-19T05:00:09.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_complete\"}}".utf8)
check(CodexRolloutStatusParser.parse(data: completedAfterActivity, now: rolloutNow).state == .complete,
      "Codex terminal event overrides ongoing activity")

// 用户主动停止不是故障：turn_aborted 应回到空闲而不是红灯。
let abortedRollout = runningRollout + Data("\n{\"timestamp\":\"2026-07-19T05:00:05.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\"}}".utf8)
check(CodexRolloutStatusParser.parse(data: abortedRollout, now: rolloutNow).state == .idle,
      "Codex rollout aborted maps to idle")

let activityLog = """
2026-07-20T16:01:22Z info thread_stream_view_activity_changed active=true conversationId=thread-a rendererWindowId=1
2026-07-20T16:01:23Z info thread_stream_view_activity_changed active=false conversationId=thread-a rendererWindowId=1
2026-07-20T16:01:24Z info thread_stream_view_activity_changed active=true conversationId=thread-b rendererWindowId=1
"""
check(CodexDesktopConfirmationState.activeThreadID(in: activityLog) == "thread-b",
      "Codex Desktop activity log resolves exact visible thread")
check(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["暂不 Esc", "安装 ↵"]),
      "Codex MCP installation card requires confirmation")
check(CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["拒绝", "批准一次", "总是允许"]),
      "Codex permission card requires confirmation")
check(!CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation(["安装 ↵"]),
      "single focused install action is not confirmation proof")
check(CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation(["暂不 Esc", "安装 ↵"]),
      "focused confirmation group requires both choices")
check(!CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation(["继续", "新建任务"]),
      "generic focused actions do not trigger confirmation")
check(!CodexDesktopConfirmationState.focusedButtonLabelsIndicateConfirmation(["请求批准"]),
      "composer request-approval entrypoint is not a pending approval")
check(!CodexDesktopConfirmationState.buttonLabelsContainConfirmationAction(["Request approval"]),
      "English request-approval entrypoint is not a confirmation action")
check(!CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["请求批准", "取消"]),
      "request-approval entrypoint cannot pair with unrelated cancel")
check(!CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["新建任务", "插件", "搜索"]),
      "normal Codex navigation is not a confirmation")
check(!CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["取消", "确认"]),
      "generic confirm and cancel pair is not a permission request")
check(!CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["Cancel", "Confirm"]),
      "English generic confirm and cancel pair is not a permission request")
check(!CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["不允许", "拒绝"]),
      "negative Chinese labels cannot satisfy the affirmative marker")
check(!CodexDesktopConfirmationState.buttonLabelsRequireConfirmation(["Disallow", "Decline"]),
      "negative English labels cannot satisfy the affirmative marker")

// 缓存的原始解析结果在每次轮询时重新计算衰减。
let staleComplete = CodexTaskLightSnapshot(threadID: "t", state: .complete, eventDate: rolloutNow.addingTimeInterval(-61))
check(CodexRolloutStatusParser.applyDecay(to: staleComplete, now: rolloutNow).state == .idle,
      "complete decays to idle after 60s")
let freshError = CodexTaskLightSnapshot(threadID: "t", state: .error, eventDate: rolloutNow.addingTimeInterval(-119))
check(CodexRolloutStatusParser.applyDecay(to: freshError, now: rolloutNow).state == .error,
      "error persists within 120s")
let staleError = CodexTaskLightSnapshot(threadID: "t", state: .error, eventDate: rolloutNow.addingTimeInterval(-121))
check(CodexRolloutStatusParser.applyDecay(to: staleError, now: rolloutNow).state == .idle,
      "error decays to idle after 120s")
let freshReasoning = CodexTaskLightSnapshot(
    threadID: "t", state: .reasoning,
    eventDate: rolloutNow.addingTimeInterval(-CodexRolloutStatusParser.reasoningStaleDuration + 1)
)
check(CodexRolloutStatusParser.applyDecay(to: freshReasoning, now: rolloutNow).state == .reasoning,
      "recent reasoning remains blue")
let staleReasoning = CodexTaskLightSnapshot(
    threadID: "t", state: .reasoning,
    eventDate: rolloutNow.addingTimeInterval(-CodexRolloutStatusParser.reasoningStaleDuration - 1)
)
check(CodexRolloutStatusParser.applyDecay(
    to: staleReasoning,
    now: rolloutNow,
    preserveUnreadCompletion: true
).state == .idle, "stale unread reasoning cannot remain blue forever")
check(CodexRolloutStatusParser.applyDecay(
    to: staleComplete,
    now: rolloutNow,
    preserveUnreadCompletion: true
).state == .complete, "unread completion may remain green")

// 侧灯聚合：显示六任务里最需要关注的状态。
check(CodexTaskLightAggregator.aggregate([]) == .idle, "aggregate empty is idle")
check(CodexTaskLightAggregator.aggregate([.idle, .complete, .reasoning]) == .reasoning,
      "aggregate prefers reasoning over complete")
check(CodexTaskLightAggregator.aggregate([.reasoning, .waitingForConfirmation]) == .waitingForConfirmation,
      "aggregate prefers confirmation over reasoning")
check(CodexTaskLightAggregator.aggregate([.waitingForConfirmation, .error, .reasoning]) == .error,
      "aggregate prefers error above all")

let candidateSnapshots = [
    CodexTaskLightSnapshot(threadID: "recent", state: .idle, eventDate: nil, recencyAtMS: 300, pinnedOrder: 1),
    CodexTaskLightSnapshot(threadID: "running", state: .reasoning, eventDate: nil, recencyAtMS: 100),
    CodexTaskLightSnapshot(threadID: "unread", state: .complete, eventDate: nil, recencyAtMS: 200, isUnread: true, pinnedOrder: 0),
    CodexTaskLightSnapshot(threadID: "waiting", state: .waitingForConfirmation, eventDate: nil, recencyAtMS: 50)
]
let recentSlots = CodexAgentSlotResolver.resolve(
    candidates: candidateSnapshots, mode: .recent,
    pinnedThreadIDs: [], customThreadIDs: []
)
check(recentSlots.prefix(4).compactMap(\.threadID) == ["recent", "unread", "running", "waiting"],
      "recent Agent mode follows recency while preserving exact IDs")
let prioritySlots = CodexAgentSlotResolver.resolve(
    candidates: candidateSnapshots, mode: .priority,
    pinnedThreadIDs: [], customThreadIDs: []
)
check(prioritySlots.prefix(4).compactMap(\.threadID) == ["waiting", "unread", "running", "recent"],
      "priority Agent mode orders attention unread active then recent")
let pinnedSlots = CodexAgentSlotResolver.resolve(
    candidates: candidateSnapshots, mode: .pinned,
    pinnedThreadIDs: ["running"], customThreadIDs: []
)
check(pinnedSlots.prefix(2).compactMap(\.threadID) == ["unread", "recent"],
      "pinned Agent mode follows Codex pinned-thread order")
let customSlots = CodexAgentSlotResolver.resolve(
    candidates: candidateSnapshots, mode: .custom,
    pinnedThreadIDs: [], customThreadIDs: ["running", nil, "recent"]
)
check(customSlots[0].threadID == "running" && customSlots[1].threadID == nil
        && customSlots[2].threadID == "recent" && customSlots.count == 6,
      "custom Agent mode keeps exact slot identity and empty keys")

// Codex 线程索引：只取未归档用户线程、按 recency 降序、限六条。
let indexDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("Air75SelfTest-Index-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: indexDirectory) }
let indexDatabase = indexDirectory.appendingPathComponent("state_5.sqlite")
var testDB: OpaquePointer?
if sqlite3_open(indexDatabase.path, &testDB) == SQLITE_OK, let testDB {
    sqlite3_exec(testDB, """
    CREATE TABLE threads (
        id TEXT, rollout_path TEXT, thread_source TEXT,
        archived INTEGER, recency_at_ms INTEGER
    );
    INSERT INTO threads VALUES ('u1', 'sessions/u1.jsonl', 'user', 0, 600);
    INSERT INTO threads VALUES ('sub1', 'sessions/sub1.jsonl', 'subagent', 0, 999);
    INSERT INTO threads VALUES ('arch1', 'sessions/arch1.jsonl', 'user', 1, 998);
    INSERT INTO threads VALUES ('u2', 'sessions/u2.jsonl', 'user', 0, 500);
    INSERT INTO threads VALUES ('u3', '/abs/u3.jsonl', 'user', 0, 400);
    INSERT INTO threads VALUES ('u4', 'sessions/u4.jsonl', NULL, 0, 300);
    INSERT INTO threads VALUES ('u5', 'sessions/u5.jsonl', 'user', 0, 200);
    INSERT INTO threads VALUES ('u6', 'sessions/u6.jsonl', 'user', NULL, 100);
    INSERT INTO threads VALUES ('u7', 'sessions/u7.jsonl', 'user', 0, 50);
    INSERT INTO threads VALUES ('nopath', NULL, 'user', 0, 997);
    """, nil, nil, nil)
    sqlite3_close(testDB)

    let reader = CodexThreadIndexReader(codexHome: indexDirectory)
    check(reader.currentDatabaseURL()?.lastPathComponent == "state_5.sqlite",
          "thread index picks latest state database")
    let top = reader.topUserThreads(limit: 6)
    check(top.map(\.threadID) == ["u1", "u2", "u3", "u4", "u5", "u6"],
          "thread index filters and orders user threads")
    check(!top.contains(where: { $0.threadID == "sub1" || $0.threadID == "arch1" || $0.threadID == "nopath" }),
          "thread index excludes subagent, archived and pathless rows")
    check(reader.userThreads(withIDs: ["u7"]).map(\.threadID) == ["u7"],
          "thread index keeps old custom assignment outside recent window")
    if let first = top.first, let absolute = top.first(where: { $0.threadID == "u3" }) {
        check(reader.rolloutURL(for: first).path == indexDirectory.appendingPathComponent("sessions/u1.jsonl").path,
              "thread index resolves relative rollout path")
        check(reader.rolloutURL(for: absolute).path == "/abs/u3.jsonl",
              "thread index keeps absolute rollout path")
    } else {
        check(false, "thread index resolves relative rollout path")
        check(false, "thread index keeps absolute rollout path")
    }
} else {
    check(false, "thread index picks latest state database")
}

var reasoning = ReasoningLevel.minimal
reasoning.step(-1)
check(reasoning == .minimal, "reasoning lower clamp")
reasoning.step(99)
check(reasoning == .xhigh, "reasoning upper clamp")

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Air75SelfTest-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: temporary) }
let store = ConfigurationStore(baseURL: temporary)
var configuration = BridgeConfiguration()
configuration.enabled = true
do {
    try store.save(configuration)
    check(store.load().enabled, "configuration atomic round-trip")
    var indicatorConfiguration = BridgeConfiguration()
    check(!indicatorConfiguration.hasInitializedIndicatorMode(for: "nuphy.air75-v3"),
          "indicator default begins uninitialized")
    indicatorConfiguration.markIndicatorModeInitialized(for: "nuphy.air75-v3")
    try store.save(indicatorConfiguration)
    check(store.load().hasInitializedIndicatorMode(for: "nuphy.air75-v3"),
          "indicator default persists per model")
    var legacy = BridgeConfiguration()
    legacy.schemaVersion = 1
    legacy.keyBindings = zip(0x68...0x73, BridgeConfiguration.defaultBindings.map(\.action)).map {
        KeyBinding(usagePage: 0x07, usage: $0.0, action: $0.1)
    }
    try store.save(legacy)
    let migrated = store.load()
    check(migrated.schemaVersion == 14
            && migrated.sidelightRestoredAfterSignalLights == false
            && migrated.resolvedAgentSourceMode == .recent
            && migrated.keyBindings.map(\.usage) == Array(0x3A...0x45),
          "migrates v1 F13-F24 configuration")
    var corrupted = BridgeConfiguration()
    corrupted.schemaVersion = 6
    corrupted.hardwareProfileInstalled = true
    corrupted.keyBindings = BridgeConfiguration.hardwareProfileBindings
    corrupted.keyBindings[0].usage = KeyBinding.hidArrayUsageSentinel
    try store.save(corrupted)
    let repaired = store.load()
    check(repaired.schemaVersion == 14
            && repaired.sidelightRestoredAfterSignalLights == false
            && repaired.keyBindings[0].usage == 0x68
            && repaired.keyBindings.dropFirst().map(\.usage) == Array(0x69...0x73),
          "repairs persisted HID array sentinel without changing other bindings")
    var mixedAir = BridgeConfiguration()
    mixedAir.schemaVersion = 12
    mixedAir.setHardwareProfileState(
        InstalledHardwareProfileState(installed: true),
        for: "nuphy.air75-v3"
    )
    var mixedAirBindings = BridgeConfiguration.hardwareProfileBindings
    mixedAirBindings[1].usage = 0x6A
    mixedAirBindings[2].usage = 0x2B
    mixedAir.setBindings(mixedAirBindings, for: "nuphy.air75-v3")
    try store.save(mixedAir)
    let repairedAir = store.load()
    check(repairedAir.schemaVersion == 14
            && repairedAir.bindings(for: "nuphy.air75-v3").map(\.usage) == Array(0x68...0x73),
          "repairs exact Air75 F13/F15/Tab/F16-F24 first-run corruption")
    var schema13Mixed = BridgeConfiguration()
    schema13Mixed.schemaVersion = 13
    var schema13MixedBindings = BridgeConfiguration.hardwareProfileBindings
    schema13MixedBindings[1].usage = 0x6A
    schema13MixedBindings[2].usage = 0x2B
    schema13Mixed.setHardwareProfileState(
        InstalledHardwareProfileState(installed: true),
        for: "nuphy.air75-v3"
    )
    schema13Mixed.setBindings(schema13MixedBindings, for: "nuphy.air75-v3")
    try store.save(schema13Mixed)
    let schema14Repaired = store.load()
    check(schema14Repaired.schemaVersion == 14
            && schema14Repaired.bindings(for: "nuphy.air75-v3").map(\.usage)
                == Array(0x68...0x73),
          "schema 14 repairs saved mixed defaults for Air75 V3")
    let freshConfiguration = BridgeConfiguration()
    check(freshConfiguration.bindings(for: "nuphy.air75-v3").map(\.usage)
            == Array(0x3A...0x45),
          "fresh configuration starts Air75 V3 on physical F1-F12 before setup")
    var genuineCustomAir = BridgeConfiguration.hardwareProfileBindings
    genuineCustomAir[2].usage = 0x14
    check(BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
        genuineCustomAir,
        hardwareProfileInstalled: true
    ) == genuineCustomAir,
          "preserves genuine custom bindings while repairing known first-run corruption")
    check(DeviceProfileRegistry.loadBundled().profile(id: "nuphy.air75-v3") != nil,
          "loads the bundled Air75 V3 profile")
    check(KeyboardDriverRegistry.keymapDriver(for: .air75V3Fallback) != nil,
          "registers verified Air75 V3 keymap driver")
    check(KeyboardDriverRegistry.lightingDriver(for: .air75V3Fallback)?.supportedSidelightModes
            == Air75SidelightMode.allCases,
          "keeps all five Air75 V3 sidelight modes")
    check(KeyboardDriverRegistry.sleepDriver(for: .air75V3Fallback) != nil,
          "registers verified Air75 V3 sleep driver")
} catch {
    check(false, "configuration atomic round-trip: \(error.localizedDescription)")
}

private func + (lhs: Data, rhs: Data) -> Data {
    var result = lhs
    result.append(rhs)
    return result
}

do {
    let codexHome = temporary.appendingPathComponent("codex-home", isDirectory: true)
    let keybindingBackups = temporary.appendingPathComponent("keybinding-backups", isDirectory: true)
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    let legacy = """
    [
      {"command":"thread1","key":"F13"},
      {"command":"newTask","key":"Command+O"},
      {"command":"composer.startDictation","key":"F23"},
      {"command":"custom.command","key":"Command+Y"}
    ]
    """.data(using: .utf8)!
    try legacy.write(to: codexHome.appendingPathComponent("keybindings.json"))
    let installer = CodexKeybindingInstaller(codexHome: codexHome, backupDirectory: keybindingBackups)
    _ = try installer.install()
    let installed = try JSONDecoder().decode(
        [CodexKeybinding].self,
        from: Data(contentsOf: installer.keybindingsURL)
    )
    check(installer.isInstalled(), "Codex relay keybindings verify")
    check(!installed.contains(where: { $0.key == "F13" || $0.key == "F23" || $0.key == "Command+O" }),
          "legacy direct hardware bindings removed")
    check(installed.contains(.init(command: "composer.startDictation", key: "F11")),
          "physical F11 dictation shortcut installed")
    check(installed.contains(.init(command: "composer.startDictation", key: "Ctrl+Shift+D")),
          "Codex dictation relay shortcut installed")
} catch {
    check(false, "Codex relay keybinding install: \(error.localizedDescription)")
}

do {
    var bytes = [UInt8](repeating: 0, count: Air75V3KeymapController.keymapByteCount)
    func setCode(_ value: UInt16, entry: Int) {
        bytes[entry * 2] = UInt8(value >> 8)
        bytes[entry * 2 + 1] = UInt8(value & 0xFF)
    }
    for layer in 0..<8 {
        setCode(0x00A8, entry: layer * 98 + 60)
        setCode(0x00AA, entry: layer * 98 + 96)
        setCode(0x00A9, entry: layer * 98 + 97)
    }
    let candidate = try Air75V3KeymapController().makeBridgeProfile(from: bytes)
    func code(_ entry: Int) -> UInt16 {
        (UInt16(candidate[entry * 2]) << 8) | UInt16(candidate[entry * 2 + 1])
    }
    check((1...12).map(code) == Array(0x68...0x73).map(UInt16.init), "hardware top row F13-F24")
    check(Air75V3KeymapController.hasBridgeProfile(candidate)
            && !Air75V3KeymapController.hasBridgeProfile(bytes),
          "distinguishes original backup from Bridge profile")
    check(Air75V3KeymapController.isPlausibleKeymap(bytes)
            && Air75V3KeymapController.isPlausibleKeymap(candidate),
          "accepts original and Bridge keymaps as plausible")
    var encryptedSessionGarbage = [UInt8](repeating: 0xE5, count: Air75V3KeymapController.keymapByteCount)
    for index in stride(from: 0, to: encryptedSessionGarbage.count, by: 7) {
        encryptedSessionGarbage[index] = 0x1A
    }
    check(!Air75V3KeymapController.isPlausibleKeymap(encryptedSessionGarbage),
          "rejects encrypted keymap reads before backup")
    check(code(60) == 0x0048 && code(96) == 0x0047 && code(97) == 0x0046,
          "hardware knob unique left-click-right events")
} catch {
    check(false, "hardware profile transform: \(error.localizedDescription)")
}

if CommandLine.arguments.contains("--software-only") {
    print("SKIP  hardware HID checks (--software-only)")
} else {
    let detected = HIDDeviceManager.enumerateAllInterfaces()
    check(detected.allSatisfy { $0.productName.localizedCaseInsensitiveContains("Air75") }, "HID enumeration only returns profile matches")
    if !detected.isEmpty {
        check(detected.contains { $0.vendorID == 0x19F5 && $0.productID == 0x1028 }, "connected Air75 USB VID/PID")
        if detected.contains(where: { $0.vendorID == 0x19F5 && $0.productID == 0x1028 && $0.transport == .usb }) {
            do {
                let controller = Air75V3LightingController()
                let states = try controller.readStates()
                check(states.count == 2 && states.allSatisfy { $0.raw.count == 17 },
                      "official NuPhyIO lighting state read")
                let sleep = try controller.readSleepConfiguration()
                check(sleep.raw.count == 3 && KeyboardSleepConfiguration.validIdleMinutes.contains(sleep.idleMinutes),
                      "official NuPhyIO sleep configuration read")
            } catch {
                check(false, "official NuPhyIO hardware state read: \(error.localizedDescription)")
            }
        }
    }
}

if failures.isEmpty {
    print("SELF TEST PASSED")
    exit(EXIT_SUCCESS)
} else {
    print("SELF TEST FAILED: \(failures.joined(separator: ", "))")
    exit(EXIT_FAILURE)
}
