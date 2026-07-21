import Air75AgentBridgeCore
import Foundation
import IOKit.hid

private struct SignalLightBackup: Codable {
    var schemaVersion = 1
    var createdAt: Date
    var profileID: String
    var lights: [Air75SignalLight]
    var note: String
}

private enum ProbeError: LocalizedError {
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let detail): return "Air75 V3 验证失败：\(detail)"
        }
    }
}

private func hexBytes(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func saveSignalLightBackup(_ lights: [Air75SignalLight]) throws -> URL {
    let store = ConfigurationStore()
    try store.prepareDirectories()
    let stamp = ISO8601DateFormatter()
        .string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    let url = store.backupsURL.appendingPathComponent("\(stamp)-hardware-signal-lights.json")
    let backup = SignalLightBackup(
        createdAt: Date(),
        profileID: "nuphy.air75-v3",
        lights: lights,
        note: "Air75 V3 1.0.16.6 D8/D2 验证前的 Esc 与 F1–F6 原色。"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(backup)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    guard (try Data(contentsOf: url)) == data else {
        throw ProbeError.verificationFailed("指示灯备份写入后无法读回")
    }
    return url
}

private func enumerateNuPhyInterfaces() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
        manager,
        [kIOHIDVendorIDKey: Air75V3KeymapController.vendorID] as CFDictionary
    )
    _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []

    func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    for device in devices.sorted(by: {
        ((property($0, kIOHIDProductIDKey) as? Int) ?? 0)
            < ((property($1, kIOHIDProductIDKey) as? Int) ?? 0)
    }) {
        let productID = (property(device, kIOHIDProductIDKey) as? Int) ?? 0
        let name = (property(device, kIOHIDProductKey) as? String) ?? "?"
        let transport = (property(device, kIOHIDTransportKey) as? String) ?? "?"
        let page = (property(device, kIOHIDPrimaryUsagePageKey) as? Int) ?? -1
        let usage = (property(device, kIOHIDPrimaryUsageKey) as? Int) ?? -1
        let input = (property(device, kIOHIDMaxInputReportSizeKey) as? Int) ?? 0
        let output = (property(device, kIOHIDMaxOutputReportSizeKey) as? Int) ?? 0
        print(String(
            format: "PID=%04X transport=%@ usage=%d:%d in=%d out=%d name=%@",
            productID, transport, page, usage, input, output, name
        ))
    }
}

private func validateHardware() throws {
    let controller = Air75V3LightingController(preferredConnection: .usbCable)
    guard controller.detectedConnection() == .usbCable else {
        throw ProbeError.verificationFailed("未发现 Air75 V3 USB-C 配置通道")
    }

    let firmware = try controller.firmwareDescription()
    let originalStates = try controller.readStates()
    let lightingBackup = try ConfigurationStore().createLightingBackup(
        states: originalStates,
        note: "Air75 V3 1.0.16.6 D5/D6 原值写回验证前的完整双 handle 状态。",
        profileID: "nuphy.air75-v3",
        deviceFingerprint: nil
    )
    print("firmware: \(firmware)")
    print("lighting backup: \(lightingBackup.path)")
    for state in originalStates.sorted(by: { $0.handle < $1.handle }) {
        print("D5 h\(state.handle): \(hexBytes(state.raw))")
    }

    // D6 validation uses an exact no-op. The controller requires full ACK,
    // bounded D5 readback and rollback on any mismatch.
    let d6Verified = try controller.restore(originalStates)
    guard d6Verified == originalStates else {
        throw ProbeError.verificationFailed("D6 原值写回后的 D5 双 handle 回读不一致")
    }
    print("D6 no-op ACK + D5 exact readback: PASS")

    guard let originalMacState = originalStates.first(where: { $0.handle == 0 }) else {
        throw ProbeError.verificationFailed("D5 未返回 macOS handle 0")
    }
    let temporaryBrightness = originalMacState.backlight.brightness == 99
        ? 98 : 99
    let changedStates = try controller.setBacklight(brightness: temporaryBrightness)
    guard changedStates.first(where: { $0.handle == 0 })?.backlight.brightness
            == temporaryBrightness else {
        throw ProbeError.verificationFailed("D6 临时亮度写入没有通过 D5 回读")
    }
    let restoredStates = try controller.restore(originalStates)
    guard restoredStates == originalStates else {
        throw ProbeError.verificationFailed("D6 临时亮度测试后未精确恢复")
    }
    print("D6 changed value + exact restore: PASS")

    let indexes = Array(UInt8(0)...UInt8(6))
    let originalLights = try controller.readSignalLights(indices: indexes)
    let signalBackup = try saveSignalLightBackup(originalLights)
    print("signal backup: \(signalBackup.path)")

    // D8 validation is also a no-op. setSignalLights now performs D2 exact
    // readback itself and restores the pre-write colors on any failure.
    let d8Verified = try controller.setSignalLights(originalLights)
    guard d8Verified.sorted(by: { $0.index < $1.index })
            == originalLights.sorted(by: { $0.index < $1.index }) else {
        throw ProbeError.verificationFailed("D8 原值写回后的 D2 回读不一致")
    }
    print("D8 no-op ACK + D2 exact readback: PASS")

    guard let originalF1 = originalLights.first(where: { $0.index == 1 }) else {
        throw ProbeError.verificationFailed("D2 未返回 F1 指示灯")
    }
    let temporaryColor = originalF1.color == Air75RGBColor(red: 0x12, green: 0x34, blue: 0x56)
        ? Air75RGBColor(red: 0x65, green: 0x43, blue: 0x21)
        : Air75RGBColor(red: 0x12, green: 0x34, blue: 0x56)
    let changedLights = try controller.setSignalLights([
        Air75SignalLight(index: 1, color: temporaryColor)
    ])
    guard changedLights == [Air75SignalLight(index: 1, color: temporaryColor)] else {
        throw ProbeError.verificationFailed("D8 临时 F1 颜色没有通过 D2 回读")
    }
    let restoredLights = try controller.setSignalLights(originalLights)
    guard restoredLights.sorted(by: { $0.index < $1.index })
            == originalLights.sorted(by: { $0.index < $1.index }) else {
        throw ProbeError.verificationFailed("D8 临时颜色测试后未精确恢复")
    }
    print("D8 changed value + exact restore: PASS")

    let keymapController = Air75V3KeymapController()
    let keymap = try keymapController.readKeymap()
    guard keymap.count == Air75V3KeymapController.keymapByteCount,
          Air75V3KeymapController.isPlausibleKeymap(keymap) else {
        throw ProbeError.verificationFailed("1568-byte 键位表不符合 Air75 V3 ANSI 安全布局")
    }
    print("B2 full keymap readback: PASS")
    print("Bridge F13–F24 profile installed: \(Air75V3KeymapController.hasBridgeProfile(keymap))")

    let finalStates = try controller.readStates()
    let finalLights = try controller.readSignalLights(indices: indexes)
    guard finalStates == originalStates, finalLights == originalLights else {
        throw ProbeError.verificationFailed("最终状态与验证前备份不一致")
    }
    print("FINAL RESTORE CHECK: PASS")
}

do {
    if CommandLine.arguments.contains("--enumerate") {
        enumerateNuPhyInterfaces()
    } else if CommandLine.arguments.contains("--hardware-validate") {
        try validateHardware()
    } else {
        print("用法：")
        print("  Air75ProtocolProbe --enumerate")
        print("  Air75ProtocolProbe --hardware-validate")
        print("运行硬件验证前必须先退出 N Agent Bridge 和 NuPhyIO。")
    }
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
