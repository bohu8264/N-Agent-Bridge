import Foundation
import ServiceManagement

@available(macOS 13.0, *)
public enum LaunchAtLoginManager {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
