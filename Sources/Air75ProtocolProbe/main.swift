import Air75AgentBridgeCore
import Foundation
import IOKit.hid

private final class ProtocolProbe {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var response: [UInt8]?
    private let targetProductID: Int?
    private var device: IOHIDDevice?
    private var expectedCommand: UInt8?
    private var isOpen = false

    init(targetProductID: Int? = nil) {
        self.targetProductID = targetProductID
    }

    deinit {
        if isOpen {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputBuffer.deallocate()
    }

    func transact(command: UInt8, length: UInt8, address: UInt16, handle: UInt8,
                  payload: [UInt8] = []) throws -> [UInt8] {
        // 匹配 Air75 V3、官方 U1 接收器，或由 --product-id 明确指定的
        // NuPhy 型号。自定义 PID 只开放给下方显式命令，不会扩大产品代码
        // 中已验证的写入驱动范围。
        var productIDs = [0x1028, 0x2620]
        if let targetProductID, !productIDs.contains(targetProductID) {
            productIDs.append(targetProductID)
        }
        let allMatches: [[String: Int]] = productIDs.map { productID in
            [
                kIOHIDVendorIDKey: 0x19F5,
                kIOHIDProductIDKey: productID,
                kIOHIDPrimaryUsagePageKey: 1,
                kIOHIDPrimaryUsageKey: 0
            ]
        }
        let matches = targetProductID.map { target in
            allMatches.filter { $0[kIOHIDProductIDKey] == target }
        } ?? allMatches
        if !isOpen {
            IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else { throw ProbeError.managerOpen(openResult) }
            isOpen = true
            let candidates = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
            func rank(_ device: IOHIDDevice) -> Int {
                (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) == 0x1028 ? 0 : 1
            }
            guard let selected = candidates.sorted(by: { rank($0) < rank($1) }).first else {
                throw ProbeError.deviceNotFound
            }
            device = selected
            inputBuffer.initialize(repeating: 0, count: 64)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(selected, inputBuffer, 64, Self.inputReport, context)
        }

        guard let device else { throw ProbeError.deviceNotFound }

        response = nil
        expectedCommand = command
        var report = Self.makeReport(command: command, length: length, address: address,
                                     handle: handle, payload: payload)
        let reportLength = report.count
        let writeResult = report.withUnsafeMutableBytes { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0,
                                 bytes.bindMemory(to: UInt8.self).baseAddress!, reportLength)
        }
        guard writeResult == kIOReturnSuccess else { throw ProbeError.writeFailed(writeResult) }

        let deadline = Date().addingTimeInterval(1.5)
        while response == nil && RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) && Date() < deadline {}
        guard let response else { throw ProbeError.timeout }
        try Self.validate(response: response, command: command, length: length,
                          address: address, handle: handle)
        return response
    }

    static func payload(from response: [UInt8], expectedLength: Int) throws -> [UInt8] {
        guard expectedLength >= 0, response.count >= 8 + expectedLength,
              Int(response[4]) >= expectedLength else {
            throw ProbeError.verificationFailed("response payload is shorter than expected")
        }
        return Array(response[8..<(8 + expectedLength)])
    }

    private static func validate(response: [UInt8], command: UInt8, length: UInt8,
                                 address: UInt16, handle: UInt8) throws {
        guard response.count == 64, response[0] == 0xAA, response[1] == command else {
            throw ProbeError.verificationFailed("invalid S4 response header")
        }
        let checksum = UInt8(response[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        guard checksum == response[3] else {
            throw ProbeError.verificationFailed("invalid S4 response checksum")
        }
        let keyCandidates: Set<UInt8> = [
            response[4] ^ length,
            response[5] ^ UInt8(address & 0xFF),
            response[6] ^ UInt8((address >> 8) & 0xFF),
            response[7] ^ handle
        ]
        if keyCandidates.count == 1, let key = keyCandidates.first, key != 0 {
            throw ProbeError.verificationFailed(
                "another configurator left session key 0x\(String(format: "%02X", key)) active"
            )
        }
        guard Int(response[4]) >= Int(length) else {
            throw ProbeError.verificationFailed("S4 response length is shorter than requested")
        }
    }

    static func makeReport(command: UInt8, length: UInt8, address: UInt16, handle: UInt8,
                           payload: [UInt8] = []) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0x55
        report[1] = command
        report[2] = 0
        report[4] = length
        report[5] = UInt8(address & 0xFF)
        report[6] = UInt8((address >> 8) & 0xFF)
        report[7] = handle
        for (index, byte) in payload.prefix(56).enumerated() { report[8 + index] = byte }
        report[3] = UInt8(report[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        return report
    }

    private static let inputReport: IOHIDReportCallback = { context, result, _, _, _, report, length in
        guard result == kIOReturnSuccess, let context else { return }
        let probe = Unmanaged<ProtocolProbe>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard bytes.count >= 2, bytes[0] == 0xAA,
              probe.expectedCommand == bytes[1] else { return }
        probe.response = bytes
    }
}

private enum ProbeError: LocalizedError {
    case managerOpen(IOReturn)
    case deviceNotFound
    case writeFailed(IOReturn)
    case timeout
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .managerOpen(let code): return "无法打开 IOHIDManager：0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .deviceNotFound: return "未找到 Air75 V3 的 usage 1/0 配置接口"
        case .writeFailed(let code): return "读取请求发送失败：0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .timeout: return "等待 Air75 V3 响应超时"
        case .verificationFailed(let detail): return "硬件回读验证失败：\(detail)"
        }
    }
}

private func hexBytes(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func kick75ReadState(_ probe: ProtocolProbe, handle: Int) throws -> [UInt8] {
    let response = try probe.transact(
        command: 0xD5,
        length: 17,
        address: 0,
        handle: UInt8(handle)
    )
    return try ProtocolProbe.payload(from: response, expectedLength: 17)
}

@discardableResult
private func kick75WriteState(_ probe: ProtocolProbe, handle: Int,
                              desired: [UInt8],
                              toleratedDeltas: [Int: Int] = [:]) throws -> [UInt8] {
    guard desired.count == 17 else {
        throw ProbeError.verificationFailed("Kick75 D6 payload must contain 17 bytes")
    }
    let acknowledgement = try probe.transact(
        command: 0xD6,
        length: 17,
        address: 0,
        handle: UInt8(handle),
        payload: desired
    )
    let echoed = try ProtocolProbe.payload(from: acknowledgement, expectedLength: 17)
    guard echoed == desired else {
        throw ProbeError.verificationFailed(
            "Kick75 D6 handle \(handle) ACK differs: expected \(hexBytes(desired)); got \(hexBytes(echoed))"
        )
    }
    Thread.sleep(forTimeInterval: 0.22)
    let readback = try kick75ReadState(probe, handle: handle)
    let offsets = desired.indices.filter { byteIndex in
        abs(Int(desired[byteIndex]) - Int(readback[byteIndex]))
            > (toleratedDeltas[byteIndex] ?? 0)
    }
    guard offsets.isEmpty else {
        throw ProbeError.verificationFailed(
            "Kick75 D6 handle \(handle) readback differs at offsets "
                + offsets.map(String.init).joined(separator: ", ")
                + ": expected \(hexBytes(desired)); got \(hexBytes(readback))"
        )
    }
    return readback
}

private func kick75RestoreStates(_ probe: ProtocolProbe,
                                 originals: [Int: [UInt8]],
                                 handles: [Int] = [0, 1]) throws {
    for handle in handles {
        guard let original = originals[handle] else {
            throw ProbeError.verificationFailed("Kick75 restore is missing handle \(handle)")
        }
        _ = try kick75WriteState(probe, handle: handle, desired: original)
    }
    Thread.sleep(forTimeInterval: 0.25)
    for handle in handles {
        guard let original = originals[handle] else { continue }
        let readback = try kick75ReadState(probe, handle: handle)
        guard readback == original else {
            throw ProbeError.verificationFailed(
                "Kick75 final restore mismatch on handle \(handle)"
            )
        }
    }
}

private func kick75ReadAllColors(_ probe: ProtocolProbe, ledCount: Int) throws -> [UInt8] {
    guard ledCount > 0, ledCount <= 104 else {
        throw ProbeError.verificationFailed("Kick75 LED count is outside the safe range")
    }
    let byteCount = ledCount * 3
    var bytes: [UInt8] = []
    bytes.reserveCapacity(byteCount)
    var address = 0
    while address < byteCount {
        let chunk = min(54, byteCount - address)
        let response = try probe.transact(
            command: 0xD2,
            length: UInt8(chunk),
            address: UInt16(address),
            handle: 0
        )
        bytes.append(contentsOf: try ProtocolProbe.payload(from: response, expectedLength: chunk))
        address += chunk
    }
    return bytes
}

private func kick75ReadSignalLight(_ probe: ProtocolProbe, index: UInt8) throws -> Air75SignalLight {
    let response = try probe.transact(
        command: 0xD2,
        length: 3,
        address: UInt16(index) * 3,
        handle: 0
    )
    let raw = try ProtocolProbe.payload(from: response, expectedLength: 3)
    return Air75SignalLight(
        index: index,
        color: Air75RGBColor(red: raw[0], green: raw[1], blue: raw[2])
    )
}

@discardableResult
private func kick75WriteSignalLight(
    _ probe: ProtocolProbe,
    light: Air75SignalLight
) throws -> Air75SignalLight {
    let payload = light.encodedBytes
    let acknowledgement = try probe.transact(
        command: 0xD8,
        length: UInt8(payload.count),
        address: 0,
        handle: 0,
        payload: payload
    )
    let echoed = try ProtocolProbe.payload(from: acknowledgement, expectedLength: payload.count)
    guard echoed == payload else {
        throw ProbeError.verificationFailed("Kick75 D8 single-light ACK mismatch")
    }
    Thread.sleep(forTimeInterval: 0.18)
    let readback = try kick75ReadSignalLight(probe, index: light.index)
    guard readback == light else {
        throw ProbeError.verificationFailed(
            "Kick75 D2 index \(light.index) readback differs from D8 target"
        )
    }
    return readback
}

private func kick75ReadSleepConfiguration(_ probe: ProtocolProbe) throws -> KeyboardSleepConfiguration {
    let response = try probe.transact(
        command: 0xF3,
        length: 3,
        address: 0,
        handle: 0
    )
    return try KeyboardSleepConfiguration(
        raw: ProtocolProbe.payload(from: response, expectedLength: 3)
    )
}

@discardableResult
private func kick75WriteSleepConfiguration(
    _ probe: ProtocolProbe,
    desired: KeyboardSleepConfiguration
) throws -> KeyboardSleepConfiguration {
    let acknowledgement = try probe.transact(
        command: 0xF5,
        length: 3,
        address: 0,
        handle: 0,
        payload: desired.raw
    )
    let echoed = try ProtocolProbe.payload(from: acknowledgement, expectedLength: 3)
    guard echoed == desired.raw else {
        throw ProbeError.verificationFailed(
            "Kick75 F5 ACK differs: expected \(hexBytes(desired.raw)); got \(hexBytes(echoed))"
        )
    }
    Thread.sleep(forTimeInterval: 0.22)
    let readback = try kick75ReadSleepConfiguration(probe)
    guard readback == desired else {
        throw ProbeError.verificationFailed(
            "Kick75 F3 readback differs: expected \(hexBytes(desired.raw)); got \(hexBytes(readback.raw))"
        )
    }
    return readback
}

private func value(after flag: String, default defaultValue: Int) -> Int {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return defaultValue }
    let text = CommandLine.arguments[index + 1]
    return text.lowercased().hasPrefix("0x") ? Int(text.dropFirst(2), radix: 16) ?? defaultValue : Int(text) ?? defaultValue
}

private func text(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

let command = value(after: "--command", default: 0xD5)
let length = value(after: "--length", default: 17)
let address = value(after: "--address", default: 0)
let handle = value(after: "--handle", default: 0)
let targetProductID = text(after: "--connection").flatMap { value -> Int? in
    switch value.lowercased() {
    case "usb", "usb-c", "wired": return Air75V3LightingController.productID
    case "2.4g", "2.4ghz", "dongle", "receiver": return Air75V3LightingController.dongleProductID
    default: return nil
    }
} ?? text(after: "--product-id").flatMap { value in
    value.lowercased().hasPrefix("0x")
        ? Int(value.dropFirst(2), radix: 16)
        : Int(value)
}
let writeCurrentTest = CommandLine.arguments.contains("--write-current-test")
let controllerStaticTest = CommandLine.arguments.contains("--controller-static-test")
let controllerSidelightStatusTest = CommandLine.arguments.contains("--controller-sidelight-status-test")
let controllerBacklightBrightnessTest = CommandLine.arguments.contains("--controller-backlight-brightness-test")
let signalLightTest = CommandLine.arguments.contains("--signal-light-test")
let kick75D6Observe = CommandLine.arguments.contains("--kick75-d6-observe")
let kick75D6Validate = CommandLine.arguments.contains("--kick75-d6-validate")
let kick75SidelightLatency = CommandLine.arguments.contains("--kick75-sidelight-latency")
let kick75SleepValidate = CommandLine.arguments.contains("--kick75-sleep-validate")
let kick75QSignalValidate = CommandLine.arguments.contains("--kick75-q-signal-validate")
let keymapDryRun = CommandLine.arguments.contains("--keymap-dry-run")
let s4KeymapRead = CommandLine.arguments.contains("--s4-keymap-read")
let installBridgeProfile = CommandLine.arguments.contains("--install-bridge-profile")
let explicitPayload = text(after: "--payload-hex").map { value in
    value.split(whereSeparator: { $0 == "," || $0 == ":" || $0 == " " }).compactMap { UInt8($0, radix: 16) }
}

do {
    if kick75QSignalValidate {
        guard targetProductID == Kick75KeymapController.productID else {
            throw ProbeError.verificationFailed(
                "--kick75-q-signal-validate requires --product-id 0x1026"
            )
        }
        let expectedQIndex = 30
        guard SignalLightLayout.index(
            layoutID: "nuphy.kick75.ansi-d8",
            usagePage: 0x07,
            usage: 0x14
        ) == expectedQIndex else {
            throw ProbeError.verificationFailed("Kick75 official Q index is not 30")
        }
        let probe = ProtocolProbe(targetProductID: targetProductID)
        let index = UInt8(expectedQIndex)
        let original = try kick75ReadSignalLight(probe, index: index)
        let backupDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Air75AgentBridge/Backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupDirectory.appendingPathComponent(
            "\(stamp)-kick75-q-signal-light.json"
        )
        let backupObject: [String: Any] = [
            "schemaVersion": 1,
            "profileID": "nuphy.kick75",
            "index": Int(index),
            "red": Int(original.color.red),
            "green": Int(original.color.green),
            "blue": Int(original.color.blue),
            "note": "Kick75 官方布局 Q=30 的 D8/D2 实机验证前原色。",
        ]
        let backupData = try JSONSerialization.data(
            withJSONObject: backupObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try backupData.write(to: backupURL, options: [.atomic, .completeFileProtection])
        guard (try Data(contentsOf: backupURL)) == backupData else {
            throw ProbeError.verificationFailed("Kick75 Q color backup readback failed")
        }
        let testColor = original.color == Air75RGBColor(red: 0x16, green: 0x8B, blue: 0xFF)
            ? Air75RGBColor(red: 0xFF, green: 0x60, blue: 0x20)
            : Air75RGBColor(red: 0x16, green: 0x8B, blue: 0xFF)
        let testLight = Air75SignalLight(index: index, color: testColor)
        print("backup: \(backupURL.path)")
        print("Q candidate index: \(index); original: \(hexBytes([original.color.red, original.color.green, original.color.blue]))")

        var needsEmergencyRestore = true
        defer {
            if needsEmergencyRestore {
                do {
                    _ = try kick75WriteSignalLight(probe, light: original)
                    fputs("EMERGENCY RESTORE: verified\n", stderr)
                } catch {
                    fputs("EMERGENCY RESTORE FAILED: \(error.localizedDescription)\n", stderr)
                }
            }
        }
        _ = try kick75WriteSignalLight(probe, light: testLight)
        print("D8 Q test color ACK + D2 exact readback verified")
        _ = try kick75WriteSignalLight(probe, light: original)
        let final = try kick75ReadSignalLight(probe, index: index)
        guard final == original else {
            throw ProbeError.verificationFailed("Kick75 Q color final restore mismatch")
        }
        needsEmergencyRestore = false
        print("Kick75 Q index 30 validation PASS; original color restored")
        exit(0)
    }

    if kick75SleepValidate {
        guard targetProductID == Kick75KeymapController.productID else {
            throw ProbeError.verificationFailed(
                "--kick75-sleep-validate requires --product-id 0x1026"
            )
        }
        let probe = ProtocolProbe(targetProductID: targetProductID)
        let original = try kick75ReadSleepConfiguration(probe)
        let backupURL = try ConfigurationStore().createSleepBackup(
            configuration: original,
            note: "Kick75 F3/F5 休眠设置实机验证前读取的完整三字节原始配置。",
            profileID: "nuphy.kick75",
            deviceFingerprint: nil
        )
        print("backup: \(backupURL.path)")
        print("original: \(hexBytes(original.raw))")

        var needsEmergencyRestore = true
        defer {
            if needsEmergencyRestore {
                do {
                    _ = try kick75WriteSleepConfiguration(probe, desired: original)
                    fputs("EMERGENCY RESTORE: verified\n", stderr)
                } catch {
                    fputs("EMERGENCY RESTORE FAILED: \(error.localizedDescription)\n", stderr)
                }
            }
        }

        _ = try kick75WriteSleepConfiguration(probe, desired: original)
        print("F5 no-op ACK + F3 exact readback verified")

        let alwaysOn = try original.settingAutoSleep(afterMinutes: nil)
        _ = try kick75WriteSleepConfiguration(probe, desired: alwaysOn)
        print("temporary always-on: \(hexBytes(alwaysOn.raw)); exact readback verified")

        _ = try kick75WriteSleepConfiguration(probe, desired: original)
        let final = try kick75ReadSleepConfiguration(probe)
        guard final == original else {
            throw ProbeError.verificationFailed("Kick75 final sleep restore mismatch")
        }
        needsEmergencyRestore = false
        print("Kick75 F3/F5 validation PASS; final restore: \(hexBytes(final.raw))")
        exit(0)
    }

    if kick75SidelightLatency {
        guard targetProductID == Kick75KeymapController.productID else {
            throw ProbeError.verificationFailed(
                "--kick75-sidelight-latency requires --product-id 0x1026"
            )
        }
        let probe = ProtocolProbe(targetProductID: targetProductID)
        let original0 = try kick75ReadState(probe, handle: 0)
        let original1 = try kick75ReadState(probe, handle: 1)
        let parsedStates = try [
            Air75LightingState(handle: 0, raw: original0),
            Air75LightingState(handle: 1, raw: original1),
        ]
        let backupURL = try ConfigurationStore().createLightingBackup(
            states: parsedStates,
            note: "Kick75 官方侧灯 0–3 模式 D5 延迟采样前的完整双 handle 状态。",
            profileID: "nuphy.kick75",
            deviceFingerprint: nil
        )
        print("backup: \(backupURL.path)")
        print("original h0: \(hexBytes(original0))")
        print("original h1: \(hexBytes(original1))")

        var needsEmergencyRestore = true
        defer {
            if needsEmergencyRestore {
                do {
                    try kick75RestoreStates(probe, originals: [0: original0], handles: [0])
                    fputs("EMERGENCY RESTORE: verified\n", stderr)
                } catch {
                    fputs("EMERGENCY RESTORE FAILED: \(error.localizedDescription)\n", stderr)
                }
            }
        }

        let checkpoints: [TimeInterval] = [0, 0.05, 0.10, 0.18, 0.30, 0.50, 0.80]
        // Official Kick75 NuPhyIO exposes only 0...3. Mode 4 belongs to the
        // Air75 V3 lighting profile and can leave Kick75 in a firmware state
        // that ignores later D6 mode changes, so the probe must never send it.
        for mode in 0...3 {
            var desired = original0
            desired[9] = UInt8(mode)
            let acknowledgement = try probe.transact(
                command: 0xD6,
                length: 17,
                address: 0,
                handle: 0,
                payload: desired
            )
            let echoed = try ProtocolProbe.payload(from: acknowledgement, expectedLength: 17)
            guard echoed == desired else {
                throw ProbeError.verificationFailed("mode \(mode) ACK mismatch")
            }
            print("\nmode \(mode) ACK exact")
            var previous: TimeInterval = 0
            for checkpoint in checkpoints {
                if checkpoint > previous {
                    Thread.sleep(forTimeInterval: checkpoint - previous)
                }
                let readback = try kick75ReadState(probe, handle: 0)
                let differences = desired.indices.filter { desired[$0] != readback[$0] }
                print(String(
                    format: "%4dms mode=%02X diffs=%@ raw=%@",
                    Int(checkpoint * 1_000),
                    readback[9],
                    differences.map(String.init).joined(separator: ","),
                    hexBytes(readback)
                ))
                previous = checkpoint
            }
            try kick75RestoreStates(probe, originals: [0: original0], handles: [0])
            print("mode \(mode) restore exact")
            Thread.sleep(forTimeInterval: 0.35)
        }

        let final0 = try kick75ReadState(probe, handle: 0)
        let final1 = try kick75ReadState(probe, handle: 1)
        guard final0 == original0, final1 == original1 else {
            throw ProbeError.verificationFailed("final dual-handle state mismatch")
        }
        needsEmergencyRestore = false
        print("\nKick75 official sidelight modes 0...3 PASS; exact restore verified")
        exit(0)
    }

    if kick75D6Validate {
        guard targetProductID == Kick75KeymapController.productID else {
            throw ProbeError.verificationFailed(
                "--kick75-d6-validate requires --product-id 0x1026"
            )
        }
        let probe = ProtocolProbe(targetProductID: targetProductID)
        var originals: [Int: [UInt8]] = [:]
        for profileHandle in 0...1 {
            originals[profileHandle] = try kick75ReadState(probe, handle: profileHandle)
        }
        let parsedStates = try (0...1).map { profileHandle -> Air75LightingState in
            guard let raw = originals[profileHandle] else {
                throw ProbeError.verificationFailed("missing Kick75 handle \(profileHandle)")
            }
            return try Air75LightingState(handle: profileHandle, raw: raw)
        }
        let backupURL = try ConfigurationStore().createLightingBackup(
            states: parsedStates,
            note: "Kick75 D6 字段逐项实机验证前读取的两组完整 17-byte 原始状态。",
            profileID: "nuphy.kick75",
            deviceFingerprint: nil
        )
        print("backup: \(backupURL.path)")
        for profileHandle in 0...1 {
            print("original h\(profileHandle): \(hexBytes(originals[profileHandle] ?? []))")
        }

        var needsEmergencyRestore = true
        defer {
            if needsEmergencyRestore {
                do {
                    try kick75RestoreStates(probe, originals: originals, handles: [0])
                    fputs("EMERGENCY RESTORE: verified\n", stderr)
                } catch {
                    fputs("EMERGENCY RESTORE FAILED: \(error.localizedDescription)\n", stderr)
                }
            }
        }

        func runTest(_ name: String,
                     toleratedDeltas: [Int: Int] = [:],
                     mutate: (inout [UInt8]) -> Void) throws {
            print("\n== \(name) ==")
            do {
                for profileHandle in [0] {
                    guard var desired = originals[profileHandle] else {
                        throw ProbeError.verificationFailed("missing Kick75 original state")
                    }
                    mutate(&desired)
                    let verified = try kick75WriteState(
                        probe,
                        handle: profileHandle,
                        desired: desired,
                        toleratedDeltas: toleratedDeltas
                    )
                    print("h\(profileHandle) verified: \(hexBytes(verified))")
                }
                Thread.sleep(forTimeInterval: 0.8)
                try kick75RestoreStates(probe, originals: originals, handles: [0])
                print("\(name) restore: exact readback verified")
            } catch {
                try? kick75RestoreStates(probe, originals: originals, handles: [0])
                throw error
            }
        }

        print("\n== D6 no-op round trip ==")
        for profileHandle in [0] {
            guard let original = originals[profileHandle] else { continue }
            _ = try kick75WriteState(probe, handle: profileHandle, desired: original)
            print("h\(profileHandle) no-op ACK + exact D5 readback verified")
        }
        try kick75RestoreStates(probe, originals: originals, handles: [0])

        try runTest("backlight mode byte 0") { raw in
            raw[0] = UInt8(Air75BacklightMode.staticColor.rawValue)
        }
        try runTest(
            "backlight static color bytes 0,4...8",
            toleratedDeltas: [6: 1, 7: 1, 8: 1]
        ) { raw in
            raw[0] = UInt8(Air75BacklightMode.staticColor.rawValue)
            raw[4] = 0
            raw[5] = 0
            raw[6] = 0x16
            raw[7] = 0x8B
            raw[8] = 0xFF
        }
        let backlightColors = try kick75ReadAllColors(probe, ledCount: 85)
        print("D2 after backlight restore: \(backlightColors.count) RGB bytes readable")

        try runTest("sidelight mode byte 9") { raw in
            raw[9] = UInt8(Air75SidelightMode.staticColor.rawValue)
        }
        try runTest(
            "sidelight static color bytes 9,12...16",
            toleratedDeltas: [14: 1, 15: 1, 16: 1]
        ) { raw in
            raw[9] = UInt8(Air75SidelightMode.staticColor.rawValue)
            raw[12] = 0
            raw[13] = 0
            raw[14] = 0xFF
            raw[15] = 0x9F
            raw[16] = 0x0A
        }

        try kick75RestoreStates(probe, originals: originals, handles: [0])
        for profileHandle in 0...1 {
            guard let original = originals[profileHandle] else { continue }
            let final = try kick75ReadState(probe, handle: profileHandle)
            guard final == original else {
                throw ProbeError.verificationFailed(
                    "Kick75 final state changed unexpectedly on handle \(profileHandle)"
                )
            }
        }
        needsEmergencyRestore = false
        print("\nKick75 D6 validation PASS: backlight, sidelight, colors, and exact restore")
        exit(0)
    }

    if kick75D6Observe {
        guard targetProductID == Kick75KeymapController.productID else {
            throw ProbeError.verificationFailed(
                "--kick75-d6-observe requires --product-id 0x1026"
            )
        }
        let probe = ProtocolProbe(targetProductID: targetProductID)
        var samples: [[Int: [UInt8]]] = []
        for iteration in 0..<8 {
            var sample: [Int: [UInt8]] = [:]
            for profileHandle in 0...1 {
                let response = try probe.transact(
                    command: 0xD5,
                    length: 17,
                    address: 0,
                    handle: UInt8(profileHandle)
                )
                sample[profileHandle] = try ProtocolProbe.payload(
                    from: response,
                    expectedLength: 17
                )
            }
            samples.append(sample)
            let rendered = (0...1).compactMap { profileHandle -> String? in
                guard let bytes = sample[profileHandle] else { return nil }
                return "h\(profileHandle)=" + bytes.map {
                    String(format: "%02X", $0)
                }.joined(separator: " ")
            }.joined(separator: " | ")
            print("sample \(iteration + 1): \(rendered)")
            if iteration < 7 { Thread.sleep(forTimeInterval: 0.5) }
        }
        for profileHandle in 0...1 {
            guard let baseline = samples.first?[profileHandle] else { continue }
            let changing = baseline.indices.filter { byteIndex in
                samples.contains { $0[profileHandle]?[byteIndex] != baseline[byteIndex] }
            }
            print(
                "handle \(profileHandle) changing byte offsets: "
                    + (changing.isEmpty ? "none" : changing.map(String.init).joined(separator: ", "))
            )
        }
        print("read-only observation complete; no D6 frame was sent")
        exit(0)
    }

    if s4KeymapRead {
        guard let productID = targetProductID else {
            print("--s4-keymap-read requires --product-id 0xNNNN")
            exit(2)
        }
        let snapshot = try NuPhyS4ReadOnlyKeymapInspector(productID: productID).readSnapshot()
        let geometry = snapshot.geometry
        print("S4 keymap: product=0x\(String(format: "%04X", productID)) "
              + "layers=\(geometry.layerCount) matrix=\(geometry.rows)x\(geometry.columns) "
              + "extra=\(geometry.extraKeyCount) bytes=\(snapshot.bytes.count)")
        for layer in 0..<geometry.layerCount {
            let top = (1...12).compactMap { snapshot.keycode(layer: layer, entry: $0) }
                .map { String(format: "%04X", $0) }.joined(separator: " ")
            let knobEntries = [74, 90, 91].compactMap { entry -> String? in
                guard entry < geometry.entriesPerLayer,
                      let value = snapshot.keycode(layer: layer, entry: entry) else { return nil }
                return "\(entry):\(String(format: "%04X", value))"
            }.joined(separator: " ")
            print("L\(layer) top=[\(top)] knob=[\(knobEntries)]")
        }
        exit(0)
    }
    if CommandLine.arguments.contains("--wireless-enumerate") {
        // 只读枚举：列出所有 NuPhy (VID 0x19F5) HID 接口及其 transport，
        // 用于蓝牙/2.4G 验收。不发送任何报文。
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDVendorIDKey: 0x19F5],
            [kIOHIDVendorIDKey: 0x07D7]
        ] as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        if devices.isEmpty {
            print("未发现 NuPhy HID 接口（VID 0x19F5 / 0x07D7）")
            exit(0)
        }
        func property(_ device: IOHIDDevice, _ key: String) -> Any? {
            IOHIDDeviceGetProperty(device, key as CFString)
        }
        print("发现 \(devices.count) 个 NuPhy HID 接口：")
        for device in devices {
            let vendor = (property(device, kIOHIDVendorIDKey) as? Int) ?? 0
            let product = (property(device, kIOHIDProductIDKey) as? Int) ?? 0
            let name = (property(device, kIOHIDProductKey) as? String) ?? "?"
            let manufacturer = (property(device, kIOHIDManufacturerKey) as? String) ?? "?"
            let transport = (property(device, kIOHIDTransportKey) as? String) ?? "?"
            let usagePage = (property(device, kIOHIDPrimaryUsagePageKey) as? Int) ?? -1
            let usage = (property(device, kIOHIDPrimaryUsageKey) as? Int) ?? -1
            let maxInput = (property(device, kIOHIDMaxInputReportSizeKey) as? Int) ?? 0
            let maxOutput = (property(device, kIOHIDMaxOutputReportSizeKey) as? Int) ?? 0
            let isVendorChannel = usagePage == 1 && usage == 0 && maxInput >= 64 && maxOutput >= 64
            print(String(format: "  %04X:%04X usage %d:%d in/out %d/%d [%@] \"%@\" (%@)%@",
                         vendor, product, usagePage, usage, maxInput, maxOutput,
                         transport, name, manufacturer,
                         isVendorChannel ? "  ← 疑似 64-byte 配置通道" : ""))
        }
        print("")
        print("判定：蓝牙/2.4G 下若出现 usage 1:0 且 64-byte 的接口，说明该 transport 暴露配置通道。")
        exit(0)
    }

    if signalLightTest {
        let probe = ProtocolProbe(targetProductID: targetProductID)
        let indices = Air75V3LightingController.taskSignalLightIndices
        let beforeReport = try probe.transact(command: 0xD2, length: 18, address: 3, handle: 0)
        guard beforeReport.count == 64, beforeReport[0] == 0xAA, beforeReport[1] == 0xD2,
              beforeReport[4] >= 18 else {
            throw ProbeError.verificationFailed("无法读取测试前的 F1–F6 RGB")
        }
        let originalColors = indices.map { index -> Air75SignalLight in
            let offset = 8 + (Int(index) - 1) * 3
            return Air75SignalLight(
                index: index,
                color: Air75RGBColor(
                    red: beforeReport[offset],
                    green: beforeReport[offset + 1],
                    blue: beforeReport[offset + 2]
                )
            )
        }
        let patternColors = [
            Air75RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF), // idle
            Air75RGBColor(red: 0x00, green: 0x80, blue: 0xFF), // reasoning
            Air75RGBColor(red: 0x20, green: 0xD0, blue: 0x60), // complete
            Air75RGBColor(red: 0xFF, green: 0x90, blue: 0x00), // confirmation
            Air75RGBColor(red: 0xFF, green: 0x30, blue: 0x30), // error
            Air75RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF)  // idle
        ]
        let testLights = zip(indices, patternColors).map {
            Air75SignalLight(index: $0.0, color: $0.1)
        }
        let testPayload = testLights.flatMap(\.encodedBytes)
        let restorePayload = originalColors.flatMap(\.encodedBytes)
        var testWasWritten = false
        defer {
            if testWasWritten {
                _ = try? probe.transact(command: 0xD8, length: UInt8(restorePayload.count),
                                         address: 0, handle: 0, payload: restorePayload)
                print("F1–F6 测试前颜色已恢复")
            }
        }

        let acknowledgement = try probe.transact(
            command: 0xD8,
            length: UInt8(testPayload.count),
            address: 0,
            handle: 0,
            payload: testPayload
        )
        testWasWritten = true
        guard acknowledgement.count == 64, acknowledgement[0] == 0xAA,
              acknowledgement[1] == 0xD8 else {
            throw ProbeError.verificationFailed("0xD8 没有返回有效 ACK")
        }
        let checksum = UInt8(acknowledgement[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        guard checksum == acknowledgement[3] else {
            throw ProbeError.verificationFailed("0xD8 ACK 校验和不正确")
        }
        let ackLength = Int(acknowledgement[4])
        let ackPayload = ackLength > 0 && acknowledgement.count >= 8 + ackLength
            ? Array(acknowledgement[8..<(8 + ackLength)]) : []
        let ackPayloadText = ackPayload.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("0xD8 ACK length=\(ackLength) payload=\(ackPayloadText)")
        print(ackPayload.prefix(testPayload.count) == testPayload[...]
              ? "0xD8 完整回显验证通过" : "0xD8 ACK 未完整回显；保留原始响应供适配")
        Thread.sleep(forTimeInterval: 2.0)
    }
    if signalLightTest { exit(0) }

    if CommandLine.arguments.contains("--keylight-read") {
        // 只读探测：官方命令 0xD1 GetLightCount 与 0xD2 GetKeyLightColor。
        // NuPhyIO 对 Air75 V3 ANSI 的用法：3*(84+20)=312 字节 RGB，分块 ≤54。
        print("== GetLightCount (0xD1) ==")
        do {
            let countReport = try ProtocolProbe().transact(command: 0xD1, length: 4, address: 0, handle: 0)
            let payloadLength = Int(countReport[4])
            let end = min(8 + payloadLength, countReport.count)
            print("payload(\(payloadLength)):", countReport[8..<end].map { String(format: "%02X", $0) }.joined(separator: " "))
        } catch {
            print("GetLightCount 失败：\(error.localizedDescription)")
        }

        print("== GetKeyLightColor (0xD2) ==")
        let totalBytes = 3 * (84 + 20)
        var colors: [UInt8] = []
        colors.reserveCapacity(totalBytes)
        var offset = 0
        while offset < totalBytes {
            let chunk = min(54, totalBytes - offset)
            let report = try ProtocolProbe().transact(command: 0xD2, length: UInt8(chunk),
                                                      address: UInt16(offset), handle: 0)
            let received = Int(report[4])
            guard received >= chunk, report.count >= 8 + chunk else {
                throw ProbeError.verificationFailed("0xD2 响应长度 \(received) < 请求 \(chunk)")
            }
            colors.append(contentsOf: report[8..<(8 + chunk)])
            offset += chunk
        }
        print("读取 \(colors.count) 字节（\(colors.count / 3) 个 LED 的 RGB）：")
        for ledIndex in stride(from: 0, to: colors.count / 3, by: 1) {
            let r = colors[ledIndex * 3], g = colors[ledIndex * 3 + 1], b = colors[ledIndex * 3 + 2]
            let marker = ledIndex < 20 ? "  // 前两排候选" : ""
            print(String(format: "  LED %3d: #%02X%02X%02X%@", ledIndex, r, g, b, marker))
        }
        print("")
        print("说明：D2 是只读颜色查询；新固件的单个指示灯写入使用 D8。")
        exit(0)
    }

    if keymapDryRun || installBridgeProfile {
        let controller = Air75V3KeymapController()
        let original = try controller.readKeymap()
        let candidate = try controller.makeBridgeProfile(from: original)
        let changedBytes = zip(original, candidate).filter(!=).count
        print("Air75 V3 keymap read: \(original.count) bytes")
        print("verified bridge profile delta: \(changedBytes) bytes")
        if keymapDryRun {
            print("dry run only: keyboard was not modified")
            exit(0)
        }

        let store = ConfigurationStore()
        var configuration = store.load()
        let backupURL: URL
        if Air75V3KeymapController.hasBridgeProfile(original) {
            guard let recovered = store.loadOriginalKeymapBackup(
                preferredName: configuration.hardwareProfileBackupName
            ) else { throw Air75KeymapError.originalBackupNotFound }
            backupURL = recovered.url
        } else {
            backupURL = try store.createKeymapBackup(
                data: original,
                note: "Air75ProtocolProbe 写入专用层前逐字节读取的完整原始键位表。"
            )
        }
        let result = try controller.installBridgeProfile(expectedOriginal: original)
        configuration.schemaVersion = 7
        configuration.enabled = true
        configuration.codexModeEnabled = true
        configuration.mappingPausedByUser = false
        configuration.mappingMode = .hardwareProfile
        configuration.hardwareProfileInstalled = true
        configuration.hardwareProfileID = "nuphy.air75-v3"
        configuration.hardwareProfileBackupName = backupURL.lastPathComponent
        configuration.keyBindings = BridgeConfiguration.bindingsForInstalledHardwareProfile(
            configuration.keyBindings
        )
        try store.save(configuration)
        print("backup: \(backupURL.path)")
        print("written chunks: \(result.changedChunkAddresses.map(String.init).joined(separator: ", "))")
        print("install: full readback verified")
        exit(0)
    }

    if controllerStaticTest {
        let controller = Air75V3LightingController()
        let original = try controller.readStates()
        do {
            let changed = try controller.setStaticColor(Air75RGBColor(red: 0x16, green: 0x8B, blue: 0xFF))
            let target = Air75RGBColor(red: 0x16, green: 0x8B, blue: 0xFF)
            func closeToTarget(_ color: Air75RGBColor) -> Bool {
                abs(Int(color.red) - Int(target.red)) <= 1
                    && abs(Int(color.green) - Int(target.green)) <= 1
                    && abs(Int(color.blue) - Int(target.blue)) <= 1
            }
            let verified = changed.allSatisfy {
                $0.backlight.mode == Air75BacklightMode.staticColor.rawValue
                    && closeToTarget($0.backlight.color)
                    && $0.sidelight.mode == Air75SidelightMode.staticColor.rawValue
                    && closeToTarget($0.sidelight.color)
            }
            for state in changed {
                print("handle \(state.handle):", state.raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                print("  backlight mode=\(state.backlight.mode) color=\(state.backlight.color.hex) side mode=\(state.sidelight.mode) color=\(state.sidelight.color.hex)")
            }
            print("controller static blue readback:", verified ? "verified" : "FAILED")
            _ = try controller.restore(original)
            print("controller restore: sent and read back")
            if !verified { exit(3) }
        } catch {
            _ = try? controller.restore(original)
            throw error
        }
        exit(0)
    }

    if controllerBacklightBrightnessTest {
        let controller = Air75V3LightingController()
        let original = try controller.readStates()
        let targetBrightness = original.allSatisfy { $0.backlight.brightness == 20 } ? 70 : 20
        let store = ConfigurationStore()
        let backupURL = try store.createLightingBackup(
            states: original,
            note: "背光亮度实机验证前读取的两个完整 17-byte 灯光 Profile。",
            profileID: "nuphy.air75-v3",
            deviceFingerprint: nil
        )
        do {
            let changed = try controller.setBacklight(
                mode: nil,
                brightness: targetBrightness,
                color: nil
            )
            let changedVerified = changed.allSatisfy { state in
                guard let before = original.first(where: { $0.handle == state.handle }) else { return false }
                var expected = before.raw
                expected[1] = UInt8(targetBrightness)
                let beforeBacklight = Array(before.raw[0...8])
                let afterBacklight = Array(state.raw[0...8])
                let expectedBacklight = Array(expected[0...8])
                print(
                    "  handle \(state.handle):",
                    beforeBacklight.map { String(format: "%02X", $0) }.joined(separator: " "),
                    "→",
                    afterBacklight.map { String(format: "%02X", $0) }.joined(separator: " ")
                )
                return afterBacklight == expectedBacklight
            }
            print("backlight brightness \(targetBrightness)%:", changedVerified ? "verified" : "FAILED")
            guard changedVerified else {
                throw ProbeError.verificationFailed("backlight brightness write/readback")
            }

            let restored = try controller.restore(original)
            let restoredVerified = restored.allSatisfy { state in
                guard let before = original.first(where: { $0.handle == state.handle }) else { return false }
                return Array(state.raw[0...8]) == Array(before.raw[0...8])
            }
            print("backlight brightness restore:", restoredVerified ? "verified" : "FAILED")
            print("backup:", backupURL.path)
            guard restoredVerified else {
                throw ProbeError.verificationFailed("backlight brightness restore")
            }
        } catch {
            _ = try? controller.restore(original)
            throw error
        }
        exit(0)
    }

    if controllerSidelightStatusTest {
        let controller = Air75V3LightingController()
        let original = try controller.readStates()
        let statusColors: [(String, Air75RGBColor)] = [
            ("idle-white", .init(red: 0xFF, green: 0xFF, blue: 0xFF)),
            ("reasoning-blue", .init(red: 0x16, green: 0x8B, blue: 0xFF)),
            ("complete-green", .init(red: 0x30, green: 0xD1, blue: 0x58)),
            ("confirmation-orange", .init(red: 0xFF, green: 0x9F, blue: 0x0A)),
            ("error-red", .init(red: 0xFF, green: 0x45, blue: 0x3A))
        ]
        do {
            for (name, color) in statusColors {
                let changed = try controller.setSidelight(mode: .staticColor, brightness: 100, color: color)
                let verified = changed.allSatisfy { state in
                    guard let before = original.first(where: { $0.handle == state.handle }) else { return false }
                    let sideColorMatches = abs(Int(state.sidelight.color.red) - Int(color.red)) <= 1
                        && abs(Int(state.sidelight.color.green) - Int(color.green)) <= 1
                        && abs(Int(state.sidelight.color.blue) - Int(color.blue)) <= 1
                    let sideMatches = state.sidelight.mode == Air75SidelightMode.staticColor.rawValue
                        && sideColorMatches
                    let backlightUnchanged = Array(state.raw[0...8]) == Array(before.raw[0...8])
                    if !sideMatches || !backlightUnchanged {
                        let beforeBytes = before.raw[0...8].map { String(format: "%02X", $0) }.joined(separator: " ")
                        let afterBytes = state.raw[0...8].map { String(format: "%02X", $0) }.joined(separator: " ")
                        print("  handle \(state.handle): side mode=\(state.sidelight.mode) color=\(state.sidelight.color.hex) expected=\(color.hex)")
                        print("  backlight before=\(beforeBytes)")
                        print("  backlight after =\(afterBytes)")
                    }
                    return sideMatches && backlightUnchanged
                }
                print("sidelight \(name):", verified ? "verified; backlight unchanged" : "FAILED")
                if !verified { throw ProbeError.verificationFailed(name) }
            }
            _ = try controller.restore(original)
            print("five-state sidelight restore: verified")
        } catch {
            _ = try? controller.restore(original)
            throw error
        }
        exit(0)
    }

    if writeCurrentTest {
        let before = try ProtocolProbe(targetProductID: targetProductID).transact(command: 0xD5, length: 17, address: 0,
                                                  handle: UInt8(handle))
        let current = Array(before[8..<min(25, before.count)])
        guard current.count == 17 else { throw ProbeError.timeout }
        let acknowledgement = try ProtocolProbe(targetProductID: targetProductID).transact(command: 0xD6, length: 17, address: 0,
                                                           handle: UInt8(handle), payload: current)
        let after = try ProtocolProbe(targetProductID: targetProductID).transact(command: 0xD5, length: 17, address: 0,
                                                 handle: UInt8(handle))
        let readback = Array(after[8..<min(25, after.count)])
        print("no-op SetLightState handle=\(handle)")
        print("before:  ", current.map { String(format: "%02X", $0) }.joined(separator: " "))
        print("ack:     ", acknowledgement.map { String(format: "%02X", $0) }.joined(separator: " "))
        print("readback:", readback.map { String(format: "%02X", $0) }.joined(separator: " "))
        guard readback == current else {
            fputs("ERROR: readback differs after no-op write\n", stderr)
            exit(2)
        }
        print("verified: unchanged")
        exit(0)
    }

    let report = try ProtocolProbe(targetProductID: targetProductID).transact(command: UInt8(command), length: UInt8(length),
                                              address: UInt16(address), handle: UInt8(handle),
                                              payload: explicitPayload ?? [])
    print("command=0x\(String(command, radix: 16)) length=\(length) address=\(address) handle=\(handle)")
    print(report.enumerated().map { String(format: "%02X", $0.element) }.joined(separator: " "))
    if report.count >= 8 {
        let payloadLength = Int(report[4])
        let end = min(8 + payloadLength, report.count)
        print("payload:", report[8..<end].map { String(format: "%02X", $0) }.joined(separator: " "))
    }
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
