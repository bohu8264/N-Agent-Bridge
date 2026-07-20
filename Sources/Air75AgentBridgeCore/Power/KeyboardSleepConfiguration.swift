import Foundation

public enum KeyboardSleepConfigurationError: LocalizedError, Equatable {
    case invalidPayload([UInt8])
    case invalidIdleMinutes(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let payload):
            let bytes = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "键盘休眠配置无效：\(bytes)"
        case .invalidIdleMinutes(let minutes):
            return "键盘休眠时间必须在 1–127 分钟之间（当前为 \(minutes)）"
        }
    }
}

/// The three-byte NuPhy S4 sleep payload used by GetSleepInfo (0xF3) and
/// SetSleepCfg (0xF5): enabled flag, idle minutes, and the firmware-owned
/// deep-sleep value. The third byte is preserved because this product only
/// changes how long the lights stay on before the keyboard sleeps.
public struct KeyboardSleepConfiguration: Codable, Equatable, Sendable {
    public static let validIdleMinutes = 1...127

    public var autoSleepEnabled: Bool
    public var idleMinutes: Int
    public var deepSleepRawValue: UInt8

    public init(autoSleepEnabled: Bool, idleMinutes: Int, deepSleepRawValue: UInt8) throws {
        guard Self.validIdleMinutes.contains(idleMinutes) else {
            throw KeyboardSleepConfigurationError.invalidIdleMinutes(idleMinutes)
        }
        self.autoSleepEnabled = autoSleepEnabled
        self.idleMinutes = idleMinutes
        self.deepSleepRawValue = deepSleepRawValue
    }

    public init(raw: [UInt8]) throws {
        guard raw.count == 3, (0...1).contains(raw[0]),
              Self.validIdleMinutes.contains(Int(raw[1])) else {
            throw KeyboardSleepConfigurationError.invalidPayload(raw)
        }
        autoSleepEnabled = raw[0] == 1
        idleMinutes = Int(raw[1])
        deepSleepRawValue = raw[2]
    }

    public var raw: [UInt8] {
        [autoSleepEnabled ? 1 : 0, UInt8(idleMinutes), deepSleepRawValue]
    }

    public var autoSleepAfterMinutes: Int? {
        autoSleepEnabled ? idleMinutes : nil
    }

    public func settingAutoSleep(afterMinutes minutes: Int?) throws -> Self {
        try Self(
            autoSleepEnabled: minutes != nil,
            idleMinutes: minutes ?? idleMinutes,
            deepSleepRawValue: deepSleepRawValue
        )
    }
}
