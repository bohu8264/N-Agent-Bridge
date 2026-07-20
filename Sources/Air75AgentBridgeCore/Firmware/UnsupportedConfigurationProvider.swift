import Foundation

public final class UnsupportedConfigurationProvider: KeyboardConfigurationProvider, @unchecked Sendable {
    public enum ConfigurationError: LocalizedError {
        case protocolUnavailable
        public var errorDescription: String? { "NuPhyIO 板载 Profile 协议尚未公开；没有修改键盘" }
    }

    public init() {}
    public func readCurrentProfile(for device: DeviceSnapshot) async throws -> Data { throw ConfigurationError.protocolUnavailable }
    public func writeProfile(_ data: Data, to device: DeviceSnapshot) async throws { throw ConfigurationError.protocolUnavailable }
}
