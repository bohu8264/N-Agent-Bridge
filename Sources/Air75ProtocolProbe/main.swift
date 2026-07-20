import Air75AgentBridgeCore
import Foundation
import IOKit.hid

private final class ProtocolProbe {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var response: [UInt8]?
    private let targetProductID: Int?

    init(targetProductID: Int? = nil) {
        self.targetProductID = targetProductID
    }

    deinit { inputBuffer.deallocate() }

    func transact(command: UInt8, length: UInt8, address: UInt16, handle: UInt8,
                  payload: [UInt8] = []) throws -> [UInt8] {
        // 匹配有线键盘 (0x1028) 与官方 U1 2.4G 接收器 (0x2620)，二者说同一协议。
        let allMatches: [[String: Int]] = [
            [
                kIOHIDVendorIDKey: 0x19F5,
                kIOHIDProductIDKey: 0x1028,
                kIOHIDPrimaryUsagePageKey: 1,
                kIOHIDPrimaryUsageKey: 0
            ],
            [
                kIOHIDVendorIDKey: 0x19F5,
                kIOHIDProductIDKey: 0x2620,
                kIOHIDPrimaryUsagePageKey: 1,
                kIOHIDPrimaryUsageKey: 0
            ]
        ]
        let matches = targetProductID.map { target in
            allMatches.filter { $0[kIOHIDProductIDKey] == target }
        } ?? allMatches
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw ProbeError.managerOpen(openResult) }
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        let candidates = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        func rank(_ device: IOHIDDevice) -> Int {
            (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) == 0x1028 ? 0 : 1
        }
        guard let device = candidates.sorted(by: { rank($0) < rank($1) }).first else {
            throw ProbeError.deviceNotFound
        }

        inputBuffer.initialize(repeating: 0, count: 64)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, Self.inputReport, context)

        response = nil
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
        return response
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
        probe.response = Array(UnsafeBufferPointer(start: report, count: length))
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
}
let writeCurrentTest = CommandLine.arguments.contains("--write-current-test")
let controllerStaticTest = CommandLine.arguments.contains("--controller-static-test")
let controllerSidelightStatusTest = CommandLine.arguments.contains("--controller-sidelight-status-test")
let controllerBacklightBrightnessTest = CommandLine.arguments.contains("--controller-backlight-brightness-test")
let signalLightTest = CommandLine.arguments.contains("--signal-light-test")
let keymapDryRun = CommandLine.arguments.contains("--keymap-dry-run")
let installBridgeProfile = CommandLine.arguments.contains("--install-bridge-profile")
let explicitPayload = text(after: "--payload-hex").map { value in
    value.split(whereSeparator: { $0 == "," || $0 == ":" || $0 == " " }).compactMap { UInt8($0, radix: 16) }
}

do {
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
