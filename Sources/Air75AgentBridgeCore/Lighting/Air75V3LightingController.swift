import Foundation
import IOKit.hid

public struct Air75RGBColor: Codable, Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        red = UInt8((number >> 16) & 0xFF)
        green = UInt8((number >> 8) & 0xFF)
        blue = UInt8(number & 0xFF)
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// One logical status LED exposed by the Air75 V3 firmware's 0xD8 command.
/// Firmware indexes 1...6 are the six F-row task indicators (F1...F6).
/// Index 0 is the Escape key on the Air75 V3 ANSI layout.
public struct Air75SignalLight: Codable, Equatable, Sendable {
    public var index: UInt8
    public var color: Air75RGBColor

    public init(index: UInt8, color: Air75RGBColor) {
        self.index = index
        self.color = color
    }

    public var encodedBytes: [UInt8] {
        [index, color.red, color.green, color.blue]
    }
}

public struct Air75LightingZoneState: Codable, Equatable, Sendable {
    public var mode: Int
    public var brightness: Int
    public var speed: Int
    public var direction: Int?
    public var isRGB: Bool
    public var colorIndex: Int
    public var color: Air75RGBColor
}

public struct Air75LightingState: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { handle }
    public var handle: Int
    public var raw: [UInt8]

    public init(handle: Int, raw: [UInt8]) throws {
        guard (0...1).contains(handle), raw.count == 17,
              (0...21).contains(Int(raw[0])), raw[1] <= 100,
              raw[3] <= 1, raw[4] <= 1,
              (0...4).contains(Int(raw[9])), raw[12] <= 1 else {
            throw Air75LightingError.invalidStatePayload(raw)
        }
        self.handle = handle
        self.raw = raw
    }

    public var backlight: Air75LightingZoneState {
        Air75LightingZoneState(
            mode: Int(raw[0]), brightness: Int(raw[1]), speed: Int(raw[2]),
            direction: Int(raw[3]), isRGB: raw[4] != 0, colorIndex: Int(raw[5]),
            color: Air75RGBColor(red: raw[6], green: raw[7], blue: raw[8])
        )
    }

    public var sidelight: Air75LightingZoneState {
        Air75LightingZoneState(
            mode: Int(raw[9]), brightness: Self.sidelightPercent(from: raw[10]), speed: Int(raw[11]),
            direction: nil, isRGB: raw[12] != 0, colorIndex: Int(raw[13]),
            color: Air75RGBColor(red: raw[14], green: raw[15], blue: raw[16])
        )
    }

    public static func sidelightPercent(from rawValue: UInt8) -> Int {
        (Int(rawValue) * 100 + 127) / 255
    }

    public static func sidelightRawValue(fromPercent percent: Int) -> UInt8 {
        let clamped = min(max(percent, 0), 100)
        return UInt8((clamped * 255 + 50) / 100)
    }
}

public enum Air75BacklightMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case spectrum = 1, gradient, staticColor, breathing, flowers, wave, verticalWave
    case fountain, galaxy, rotation, ripple, singlePoint, grid, flowing, rain, waveBand
    case gaming, identify, windmill, diagonal, signalIndicator

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .spectrum: return "光谱"
        case .gradient: return "渐变"
        case .staticColor: return "常亮"
        case .breathing: return "呼吸"
        case .flowers: return "百花"
        case .wave: return "波浪"
        case .verticalWave: return "上下波浪"
        case .fountain: return "喷泉"
        case .galaxy: return "星河"
        case .rotation: return "旋转"
        case .ripple: return "涟漪"
        case .singlePoint: return "单点触发"
        case .grid: return "网格"
        case .flowing: return "流光"
        case .rain: return "落雨"
        case .waveBand: return "光带"
        case .gaming: return "游戏"
        case .identify: return "识别"
        case .windmill: return "风车"
        case .diagonal: return "斜向"
        case .signalIndicator: return "指示灯"
        }
    }
}

public enum Air75SidelightMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case flowing = 0, neon = 1, staticColor = 2, breathing = 3, rhythm = 4

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .flowing: return "流光"
        case .neon: return "霓虹"
        case .staticColor: return "常亮"
        case .breathing: return "呼吸"
        case .rhythm: return "律动"
        }
    }
}

public enum Air75LightingError: LocalizedError {
    case deviceNotFound
    case managerOpen(IOReturn)
    case writeFailed(IOReturn)
    case timeout(command: UInt8)
    case invalidResponse
    case invalidChecksum
    case invalidState
    case invalidStatePayload([UInt8])
    case sessionKeyConflict(UInt8)
    case sleepVerificationFailed(expected: [UInt8], actual: [UInt8])
    case invalidSignalLights
    case unsupportedBacklightMode(model: String, mode: Air75BacklightMode)
    case unsupportedSidelightMode(model: String, mode: Air75SidelightMode)
    case stateWritesNotVerified(String)
    case stateReadbackMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "未找到 Air75 V3 的配置接口；请使用 USB-C 数据线连接，或插入 2.4G 接收器"
        case .managerOpen(let code): return "无法打开 Air75 V3 灯光接口（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .writeFailed(let code): return "Air75 V3 HID 指令发送失败（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .timeout(let command): return "等待 Air75 V3 响应超时（命令 0x\(String(command, radix: 16))）"
        case .invalidResponse: return "Air75 V3 返回了无效协议帧"
        case .invalidChecksum: return "Air75 V3 返回帧校验失败"
        case .invalidState: return "Air75 V3 灯光状态无效"
        case .invalidStatePayload(let raw):
            let bytes = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Air75 V3 灯光状态无效：\(bytes)"
        case .sessionKeyConflict(let key):
            return "键盘正处于另一个配置器的加密会话（会话密钥 0x\(String(format: "%02X", key))）。请关闭 NuPhyIO 等配置页面，然后重新插拔键盘"
        case .sleepVerificationFailed(let expected, let actual):
            let expectedBytes = expected.map { String(format: "%02X", $0) }.joined(separator: " ")
            let actualBytes = actual.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "键盘休眠时间回读不一致（期望 \(expectedBytes)，实际 \(actualBytes)）；已尝试恢复修改前设置"
        case .invalidSignalLights:
            return "F1–F6 指示灯数据无效"
        case .unsupportedBacklightMode(let model, let mode):
            return "\(model) 不支持背光效果“\(mode.displayName)”"
        case .unsupportedSidelightMode(let model, let mode):
            return "\(model) 不支持侧灯效果“\(mode.displayName)”"
        case .stateWritesNotVerified(let model):
            return "\(model) 的普通背光与侧灯写入尚未通过完整回读验证；当前仅启用 Agent 单键状态灯"
        case .stateReadbackMismatch(let model):
            return "\(model) 灯光写入后的 D5 回读与目标状态不一致；已尝试恢复修改前设置"
        }
    }
}

/// Implements the protocol used by the official NuPhyIO Air75 V3 configurator.
/// It matches the wired keyboard (0x1028) or the official U1 2.4G receiver
/// (0x2620) on usage 1:0, and never writes key maps or firmware.
public final class Air75V3LightingController: @unchecked Sendable {
    public static let vendorID = 0x19F5
    public static let productID = 0x1028
    /// NuPhy U1 dongle. NuPhyIO configures the keyboard through it with the
    /// same S4 frames, so lighting keeps working in 2.4G wireless mode.
    public static let dongleProductID = 0x2620
    /// Firmware index 0 is Esc; F1-F6 are logical indicator indexes 1...6.
    public static let escapeSignalLightIndex: UInt8 = 0
    public static let taskSignalLightIndices: [UInt8] = Array(1...6)
    private static let getFirmwareInfo: UInt8 = 0xA1
    private static let getLightState: UInt8 = 0xD5
    private static let setLightState: UInt8 = 0xD6
    private static let getKeyLightColor: UInt8 = 0xD2
    private static let setSignalLights: UInt8 = 0xD8
    private static let getSleepInfo: UInt8 = 0xF3
    private static let setSleepConfiguration: UInt8 = 0xF5
    private let requestedConnection: KeyboardLightingConnection?
    private let wiredProductID: Int
    private let receiverProductID: Int?
    private let deviceDisplayName: String
    public let profileID: String
    public let supportsFullLightingControl: Bool
    public let supportedBacklightModes: [Air75BacklightMode]
    public let supportedSidelightModes: [Air75SidelightMode]
    /// D5 exposes separate Mac and Windows lighting profiles as handles 0
    /// and 1. Only handles that passed a hardware round trip may be written.
    public let writableLightingHandles: Set<Int>

    public init(preferredConnection: KeyboardLightingConnection? = nil) {
        self.requestedConnection = preferredConnection
        self.wiredProductID = Self.productID
        self.receiverProductID = Self.dongleProductID
        self.deviceDisplayName = "Air75 V3"
        self.profileID = "nuphy.air75-v3"
        self.supportsFullLightingControl = true
        self.supportedBacklightModes = Air75BacklightMode.allCases
        self.supportedSidelightModes = Air75SidelightMode.allCases
        self.writableLightingHandles = [0, 1]
    }

    /// Creates a narrowly scoped S4 lighting route for another model after
    /// its USB identity and commands have been verified on hardware. Setting
    /// `supportsFullLightingControl` to false keeps D5/D2 reads and D8 Agent
    /// indicators available while rejecting unverified D6 zone writes.
    public init(
        profileID: String,
        deviceDisplayName: String,
        wiredProductID: Int,
        receiverProductID: Int? = nil,
        supportsFullLightingControl: Bool,
        writableLightingHandles: Set<Int> = [0, 1],
        supportedBacklightModes: [Air75BacklightMode] = Air75BacklightMode.allCases,
        supportedSidelightModes: [Air75SidelightMode] = Air75SidelightMode.allCases,
        preferredConnection: KeyboardLightingConnection? = nil
    ) {
        self.requestedConnection = preferredConnection
        self.wiredProductID = wiredProductID
        self.receiverProductID = receiverProductID
        self.deviceDisplayName = deviceDisplayName
        self.profileID = profileID
        self.supportsFullLightingControl = supportsFullLightingControl
        self.supportedBacklightModes = supportedBacklightModes
        self.supportedSidelightModes = supportedSidelightModes
        self.writableLightingHandles = writableLightingHandles.intersection([0, 1])
    }

    public func detectedConnection() -> KeyboardLightingConnection? {
        ProtocolSession.detectedConnection(
            preferredConnection: requestedConnection,
            wiredProductID: wiredProductID,
            receiverProductID: receiverProductID
        )
    }

    public func preferConnection(_ connection: KeyboardLightingConnection) {
        ProtocolRouteMemory.shared.record(connection)
    }

    /// Kept public and pure so connection priority can be regression-tested
    /// without requiring a physical HID device in software-only CI.
    public static func preferredConnection(
        forProductIDs productIDs: some Sequence<Int>
    ) -> KeyboardLightingConnection? {
        let values = Set(productIDs)
        if values.contains(productID) { return .usbCable }
        if values.contains(dongleProductID) { return .twoPointFourGHzReceiver }
        return nil
    }

    public func firmwareDescription() throws -> String {
        let response = try transact(command: Self.getFirmwareInfo, length: 8, address: 0, handle: 0)
        let bytes = payload(from: response, expectedLength: 8)
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public func readStates() throws -> [Air75LightingState] {
        try (0...1).map(readStateWithRetry)
    }

    /// Reads the RGB values currently stored for the requested logical LED
    /// indexes. D2 addresses RGB bytes, so a contiguous range is fetched in a
    /// single transaction and then reduced back to the caller's order.
    public func readSignalLights(indices: [UInt8]) throws -> [Air75SignalLight] {
        guard !indices.isEmpty, Set(indices).count == indices.count,
              let minimum = indices.min(), let maximum = indices.max() else {
            throw Air75LightingError.invalidSignalLights
        }
        let byteCount = (Int(maximum) - Int(minimum) + 1) * 3
        guard byteCount <= 54 else { throw Air75LightingError.invalidSignalLights }
        let address = UInt16(Int(minimum) * 3)
        let response = try transact(
            command: Self.getKeyLightColor,
            length: UInt8(byteCount),
            address: address,
            handle: 0
        )
        let bytes = payload(from: response, expectedLength: byteCount)
        return indices.map { index in
            let offset = (Int(index) - Int(minimum)) * 3
            return Air75SignalLight(
                index: index,
                color: Air75RGBColor(
                    red: bytes[offset],
                    green: bytes[offset + 1],
                    blue: bytes[offset + 2]
                )
            )
        }
    }

    /// Writes one or more logical indicator LEDs with the firmware's D8
    /// `index, red, green, blue` payload. The S4 acknowledgement must echo the
    /// complete payload; this gives us protocol-level verification without
    /// guessing about the currently selected backlight animation.
    @discardableResult
    public func setSignalLights(_ lights: [Air75SignalLight]) throws -> [Air75SignalLight] {
        guard !lights.isEmpty, lights.count <= 14,
              Set(lights.map(\.index)).count == lights.count else {
            throw Air75LightingError.invalidSignalLights
        }
        let bytes = lights.flatMap(\.encodedBytes)
        let acknowledgement = try transact(
            command: Self.setSignalLights,
            length: UInt8(bytes.count),
            address: 0,
            handle: 0,
            payload: bytes
        )
        let echoed = payload(from: acknowledgement, expectedLength: bytes.count)
        guard echoed == bytes else { throw Air75LightingError.invalidResponse }
        return lights
    }

    public func readSleepConfiguration() throws -> KeyboardSleepConfiguration {
        let response = try transact(command: Self.getSleepInfo, length: 3, address: 0, handle: 0)
        return try KeyboardSleepConfiguration(raw: payload(from: response, expectedLength: 3))
    }

    @discardableResult
    public func setAutoSleep(afterMinutes minutes: Int?) throws -> KeyboardSleepConfiguration {
        let before = try readSleepConfiguration()
        let desired = try before.settingAutoSleep(afterMinutes: minutes)
        guard desired != before else { return before }

        do {
            let acknowledgement = try transact(
                command: Self.setSleepConfiguration,
                length: 3,
                address: 0,
                handle: 0,
                payload: desired.raw
            )
            let echoed = payload(from: acknowledgement, expectedLength: 3)
            guard echoed == desired.raw else { throw Air75LightingError.invalidResponse }
            Thread.sleep(forTimeInterval: 0.18)
            let verified = try readSleepConfiguration()
            guard verified == desired else {
                throw Air75LightingError.sleepVerificationFailed(
                    expected: desired.raw,
                    actual: verified.raw
                )
            }
            return verified
        } catch {
            // The original three bytes were read immediately before writing.
            // Restore and re-read them if the post-write verification fails.
            _ = try? transact(
                command: Self.setSleepConfiguration,
                length: 3,
                address: 0,
                handle: 0,
                payload: before.raw
            )
            Thread.sleep(forTimeInterval: 0.18)
            _ = try? readSleepConfiguration()
            throw error
        }
    }

    @discardableResult
    public func setBacklight(mode: Air75BacklightMode? = nil, brightness: Int? = nil,
                             color: Air75RGBColor? = nil) throws -> [Air75LightingState] {
        try requireFullLightingControl()
        if let mode, !supportedBacklightModes.contains(mode) {
            throw Air75LightingError.unsupportedBacklightMode(
                model: deviceDisplayName,
                mode: mode
            )
        }
        return try updateAllStates { raw in
            if let mode { raw[0] = UInt8(mode.rawValue) }
            if let brightness { raw[1] = UInt8(min(max(brightness, 0), 100)) }
            if let color {
                raw[4] = 0
                raw[5] = 0
                raw[6] = color.red
                raw[7] = color.green
                raw[8] = color.blue
            }
        }
    }

    @discardableResult
    public func setSidelight(mode: Air75SidelightMode? = nil, brightness: Int? = nil,
                            color: Air75RGBColor? = nil) throws -> [Air75LightingState] {
        try requireFullLightingControl()
        if let mode, !supportedSidelightModes.contains(mode) {
            throw Air75LightingError.unsupportedSidelightMode(model: deviceDisplayName, mode: mode)
        }
        return try updateAllStates { raw in
            if let mode { raw[9] = UInt8(mode.rawValue) }
            if let brightness { raw[10] = Air75LightingState.sidelightRawValue(fromPercent: brightness) }
            if let color {
                raw[12] = 0
                raw[13] = 0
                raw[14] = color.red
                raw[15] = color.green
                raw[16] = color.blue
            }
        }
    }

    @discardableResult
    public func setStaticColor(_ color: Air75RGBColor, brightness: Int? = nil) throws -> [Air75LightingState] {
        try requireFullLightingControl()
        guard supportedBacklightModes.contains(.staticColor) else {
            throw Air75LightingError.unsupportedBacklightMode(
                model: deviceDisplayName,
                mode: .staticColor
            )
        }
        guard supportedSidelightModes.contains(.staticColor) else {
            throw Air75LightingError.unsupportedSidelightMode(
                model: deviceDisplayName,
                mode: .staticColor
            )
        }
        return try updateAllStates { raw in
            raw[0] = UInt8(Air75BacklightMode.staticColor.rawValue)
            if let brightness { raw[1] = UInt8(min(max(brightness, 0), 100)) }
            raw[4] = 0
            raw[5] = 0
            raw[6] = color.red
            raw[7] = color.green
            raw[8] = color.blue
            raw[9] = UInt8(Air75SidelightMode.staticColor.rawValue)
            if let brightness { raw[10] = Air75LightingState.sidelightRawValue(fromPercent: brightness) }
            raw[12] = 0
            raw[13] = 0
            raw[14] = color.red
            raw[15] = color.green
            raw[16] = color.blue
        }
    }

    @discardableResult
    public func restore(_ states: [Air75LightingState]) throws -> [Air75LightingState] {
        try requireFullLightingControl()
        guard Set(states.map(\.handle)) == Set([0, 1]) else { throw Air75LightingError.invalidState }
        try validateSupportedSidelightModes(in: states)
        let before = try readStates()
        return try writeVerified(states, rollbackStates: before, permitsRGBQuantization: false)
    }

    /// Restores only bytes 9...16 (the sidelight zone), leaving the user's
    /// current backlight mode, brightness, speed and color untouched.
    @discardableResult
    public func restoreSidelight(from savedStates: [Air75LightingState]) throws -> [Air75LightingState] {
        try requireFullLightingControl()
        guard Set(savedStates.map(\.handle)) == Set([0, 1]) else { throw Air75LightingError.invalidState }
        try validateSupportedSidelightModes(in: savedStates)
        let currentStates = try readStates()
        var desiredStates = currentStates
        for index in desiredStates.indices where writableLightingHandles.contains(desiredStates[index].handle) {
            let current = desiredStates[index]
            guard let saved = savedStates.first(where: { $0.handle == current.handle }) else {
                throw Air75LightingError.invalidState
            }
            var raw = current.raw
            raw.replaceSubrange(9...16, with: saved.raw[9...16])
            desiredStates[index] = try Air75LightingState(handle: current.handle, raw: raw)
        }
        return try writeVerified(
            desiredStates,
            rollbackStates: currentStates,
            permitsRGBQuantization: false
        )
    }

    private func updateAllStates(_ body: (inout [UInt8]) -> Void) throws -> [Air75LightingState] {
        try update(states: readStates(), body)
    }

    private func update(states: [Air75LightingState], _ body: (inout [UInt8]) -> Void) throws -> [Air75LightingState] {
        guard Set(states.map(\.handle)) == Set([0, 1]) else { throw Air75LightingError.invalidState }
        var desiredStates = states
        for index in desiredStates.indices where writableLightingHandles.contains(desiredStates[index].handle) {
            var raw = desiredStates[index].raw
            body(&raw)
            desiredStates[index] = try Air75LightingState(handle: desiredStates[index].handle, raw: raw)
        }
        return try writeVerified(
            desiredStates,
            rollbackStates: states,
            permitsRGBQuantization: true
        )
    }

    private func writeVerified(
        _ desiredStates: [Air75LightingState],
        rollbackStates: [Air75LightingState],
        permitsRGBQuantization: Bool
    ) throws -> [Air75LightingState] {
        let targets = desiredStates
            .filter { writableLightingHandles.contains($0.handle) }
            .sorted(by: { $0.handle < $1.handle })
        guard !targets.isEmpty else { throw Air75LightingError.invalidState }

        do {
            for state in targets {
                let acknowledgement = try transact(
                    command: Self.setLightState,
                    length: 17,
                    address: 0,
                    handle: UInt8(state.handle),
                    payload: state.raw
                )
                let echoed = payload(from: acknowledgement, expectedLength: 17)
                guard echoed == state.raw else { throw Air75LightingError.invalidResponse }
                Thread.sleep(forTimeInterval: 0.08)
            }
            Thread.sleep(forTimeInterval: 0.18)
            return try readBackUntilVerified(
                targets: targets,
                permitsRGBQuantization: permitsRGBQuantization
            )
        } catch {
            restoreBestEffort(rollbackStates)
            throw error
        }
    }

    private func restoreBestEffort(_ states: [Air75LightingState]) {
        for state in states
            .filter({ writableLightingHandles.contains($0.handle) })
            .sorted(by: { $0.handle < $1.handle }) {
            _ = try? transact(
                command: Self.setLightState,
                length: 17,
                address: 0,
                handle: UInt8(state.handle),
                payload: state.raw
            )
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    /// Some S4 firmwares publish the D6 acknowledgement before D5 has moved
    /// to the new state. Retry only the readback; never resend the write while
    /// its result is uncertain. A genuinely rejected mode still fails after
    /// the bounded window and follows the existing rollback path.
    private func readBackUntilVerified(
        targets: [Air75LightingState],
        permitsRGBQuantization: Bool
    ) throws -> [Air75LightingState] {
        for attempt in 0..<5 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.12) }
            let states = try readStates()
            let matches = targets.allSatisfy { expected in
                guard let actual = states.first(where: { $0.handle == expected.handle }) else {
                    return false
                }
                return Self.matchesReadback(
                    expected: expected.raw,
                    actual: actual.raw,
                    permitsRGBQuantization: permitsRGBQuantization
                )
            }
            if matches { return states }
        }
        throw Air75LightingError.stateReadbackMismatch(deviceDisplayName)
    }

    private func validateSupportedSidelightModes(in states: [Air75LightingState]) throws {
        for state in states where writableLightingHandles.contains(state.handle) {
            guard let mode = Air75SidelightMode(rawValue: state.sidelight.mode) else {
                throw Air75LightingError.invalidState
            }
            guard supportedSidelightModes.contains(mode) else {
                throw Air75LightingError.unsupportedSidelightMode(
                    model: deviceDisplayName,
                    mode: mode
                )
            }
        }
    }

    private static func matchesReadback(
        expected: [UInt8],
        actual: [UInt8],
        permitsRGBQuantization: Bool
    ) -> Bool {
        guard expected.count == 17, actual.count == 17 else { return false }
        let rgbOffsets: Set<Int> = [6, 7, 8, 14, 15, 16]
        return expected.indices.allSatisfy { index in
            if permitsRGBQuantization, rgbOffsets.contains(index) {
                return abs(Int(expected[index]) - Int(actual[index])) <= 1
            }
            return expected[index] == actual[index]
        }
    }

    private func readStateWithRetry(handle: Int) throws -> Air75LightingState {
        var lastError: Error = Air75LightingError.invalidState
        for attempt in 0..<5 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.12) }
            do {
                let response = try transact(command: Self.getLightState, length: 17, address: 0,
                                            handle: UInt8(handle))
                return try Air75LightingState(handle: handle,
                                              raw: payload(from: response, expectedLength: 17))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func requireFullLightingControl() throws {
        guard supportsFullLightingControl else {
            throw Air75LightingError.stateWritesNotVerified(deviceDisplayName)
        }
    }

    private func payload(from response: [UInt8], expectedLength: Int) -> [UInt8] {
        Array(response[8..<(8 + expectedLength)])
    }

    private func transact(command: UInt8, length: UInt8, address: UInt16, handle: UInt8,
                          payload: [UInt8] = []) throws -> [UInt8] {
        let session = ProtocolSession(
            expectedCommand: command,
            preferredConnection: requestedConnection,
            wiredProductID: wiredProductID,
            receiverProductID: receiverProductID
        )
        return try session.transact(command: command, length: length, address: address,
                                    handle: handle, payload: payload)
    }
}

private final class ProtocolRouteMemory: @unchecked Sendable {
    static let shared = ProtocolRouteMemory()

    private let lock = NSLock()
    private var value: KeyboardLightingConnection?

    func record(_ connection: KeyboardLightingConnection) {
        lock.lock()
        value = connection
        lock.unlock()
    }

    func current() -> KeyboardLightingConnection? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class ProtocolSession {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let expectedCommand: UInt8
    private let preferredConnection: KeyboardLightingConnection?
    private let wiredProductID: Int
    private let receiverProductID: Int?
    private var response: [UInt8]?

    init(expectedCommand: UInt8, preferredConnection: KeyboardLightingConnection?,
         wiredProductID: Int, receiverProductID: Int?) {
        self.expectedCommand = expectedCommand
        self.preferredConnection = preferredConnection
        self.wiredProductID = wiredProductID
        self.receiverProductID = receiverProductID
    }
    deinit { inputBuffer.deallocate() }

    static func detectedConnection(
        preferredConnection: KeyboardLightingConnection?,
        wiredProductID: Int,
        receiverProductID: Int?
    ) -> KeyboardLightingConnection? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            matchingDictionaries(
                wiredProductID: wiredProductID,
                receiverProductID: receiverProductID
            ) as CFArray
        )
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { return nil }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let productIDs = devices.compactMap {
            (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        }
        let available = Set(productIDs)
        let remembered = preferredConnection ?? ProtocolRouteMemory.shared.current()
        if let remembered,
           let rememberedProductID = productID(
               for: remembered,
               wiredProductID: wiredProductID,
               receiverProductID: receiverProductID
           ), available.contains(rememberedProductID) { return remembered }
        if available.contains(wiredProductID) { return .usbCable }
        if let receiverProductID, available.contains(receiverProductID) {
            return .twoPointFourGHzReceiver
        }
        return nil
    }

    func transact(command: UInt8, length: UInt8, address: UInt16, handle: UInt8,
                  payload: [UInt8]) throws -> [UInt8] {
        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            Self.matchingDictionaries(
                wiredProductID: wiredProductID,
                receiverProductID: receiverProductID
            ) as CFArray
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw Air75LightingError.managerOpen(openResult) }
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        // A charging cable and the U1 receiver can both stay enumerated. Route
        // to the interface that produced the latest input, then safely fall
        // back to the other verified interface if the keyboard changed mode.
        let route = preferredConnection ?? ProtocolRouteMemory.shared.current()
        let ordered = devices.sorted {
            priority(of: $0, preferredConnection: route)
                < priority(of: $1, preferredConnection: route)
        }
        guard !ordered.isEmpty else { throw Air75LightingError.deviceNotFound }

        var lastError: Error = Air75LightingError.deviceNotFound
        for device in ordered {
            do {
                let result = try attempt(on: device, command: command, length: length,
                                         address: address, handle: handle, payload: payload)
                if let connection = connection(of: device) {
                    ProtocolRouteMemory.shared.record(connection)
                }
                return result
            } catch let error as Air75LightingError {
                // 会话密钥属于键盘固件本身，换接口不会消除冲突。
                if case .sessionKeyConflict = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func attempt(on device: IOHIDDevice, command: UInt8, length: UInt8,
                         address: UInt16, handle: UInt8, payload: [UInt8]) throws -> [UInt8] {
        response = nil
        inputBuffer.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, Self.inputReport,
                                               Unmanaged.passUnretained(self).toOpaque())
        var report = Self.makeReport(command: command, length: length, address: address,
                                     handle: handle, payload: payload)
        let reportCount = report.count
        let writeResult = report.withUnsafeMutableBytes { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0,
                                 bytes.bindMemory(to: UInt8.self).baseAddress!, reportCount)
        }
        guard writeResult == kIOReturnSuccess else { throw Air75LightingError.writeFailed(writeResult) }

        let deadline = Date().addingTimeInterval(1.5)
        while response == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard let response else { throw Air75LightingError.timeout(command: command) }
        guard response.count == 64, response[0] == 0xAA, response[1] == command else {
            throw Air75LightingError.invalidResponse
        }
        let checksum = UInt8(response[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        guard checksum == response[3] else { throw Air75LightingError.invalidChecksum }
        // NuPhyIO 的 SetSecretKey (0xEE) 会让固件对帧头 4-7 字节和 payload 做
        // XOR。四个字段一致地异或出同一个非零密钥时，说明键盘仍处于其他配置
        // 器协商的加密会话，直接解析只会得到乱码。
        let keyCandidates: Set<UInt8> = [
            response[4] ^ length,
            response[5] ^ UInt8(address & 0xFF),
            response[6] ^ UInt8((address >> 8) & 0xFF),
            response[7] ^ handle
        ]
        if keyCandidates.count == 1, let key = keyCandidates.first, key != 0 {
            throw Air75LightingError.sessionKeyConflict(key)
        }
        guard Int(response[4]) >= Int(length), response.count >= 8 + Int(length) else {
            throw Air75LightingError.invalidResponse
        }
        return response
    }

    private func priority(
        of device: IOHIDDevice,
        preferredConnection: KeyboardLightingConnection?
    ) -> Int {
        if let preferredConnection,
           connection(of: device) == preferredConnection { return 0 }
        if preferredConnection != nil, connection(of: device) != nil { return 1 }
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? -1
        if productID == wiredProductID { return 0 }
        if productID == receiverProductID { return 1 }
        return 2
    }

    private func connection(of device: IOHIDDevice) -> KeyboardLightingConnection? {
        let productID = (IOHIDDeviceGetProperty(
            device,
            kIOHIDProductIDKey as CFString
        ) as? NSNumber)?.intValue
        if productID == wiredProductID { return .usbCable }
        if productID == receiverProductID { return .twoPointFourGHzReceiver }
        return nil
    }

    private static func productID(
        for connection: KeyboardLightingConnection,
        wiredProductID: Int,
        receiverProductID: Int?
    ) -> Int? {
        switch connection {
        case .usbCable: return wiredProductID
        case .twoPointFourGHzReceiver: return receiverProductID
        }
    }

    private static func matchingDictionaries(
        wiredProductID: Int,
        receiverProductID: Int?
    ) -> [[String: Int]] {
        let productIDs = [wiredProductID] + (receiverProductID.map { [$0] } ?? [])
        return productIDs.map { productID in
            [
                kIOHIDVendorIDKey: Air75V3LightingController.vendorID,
                kIOHIDProductIDKey: productID,
                kIOHIDPrimaryUsagePageKey: 1,
                kIOHIDPrimaryUsageKey: 0
            ]
        }
    }

    private static func makeReport(command: UInt8, length: UInt8, address: UInt16,
                                   handle: UInt8, payload: [UInt8]) -> [UInt8] {
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
        guard result == kIOReturnSuccess, let context, length == 64 else { return }
        let session = Unmanaged<ProtocolSession>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard bytes.count >= 2, bytes[0] == 0xAA, bytes[1] == session.expectedCommand else { return }
        session.response = bytes
    }
}
