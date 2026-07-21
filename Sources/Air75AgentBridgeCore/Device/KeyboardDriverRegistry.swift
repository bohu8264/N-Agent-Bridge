import Foundation

public typealias KeyboardRGBColor = Air75RGBColor
public typealias KeyboardLightingState = Air75LightingState
public typealias KeyboardSignalLight = Air75SignalLight
public typealias KeyboardBacklightMode = Air75BacklightMode
public typealias KeyboardSidelightMode = Air75SidelightMode
public typealias KeyboardKeymapInstallResult = Air75KeymapInstallResult

/// Physical path currently capable of carrying verified lighting commands.
/// Bluetooth input by itself is intentionally not listed: a keyboard must
/// expose a separately verified configuration channel before it can appear
/// here.
public enum KeyboardLightingConnection: String, Equatable, Sendable {
    case usbCable
    case twoPointFourGHzReceiver

    public var displayName: String {
        switch self {
        case .usbCable: return "USB-C"
        case .twoPointFourGHzReceiver: return "2.4G 接收器"
        }
    }

    public var isWireless: Bool { self == .twoPointFourGHzReceiver }
}

public protocol KeyboardKeymapDriver: AnyObject, Sendable {
    var profileID: String { get }
    var keymapSize: Int { get }
    func readKeymap() throws -> [UInt8]
    func makeBridgeProfile(from original: [UInt8]) throws -> [UInt8]
    func isPlausibleKeymap(_ bytes: [UInt8]) -> Bool
    func containsBridgeProfile(_ bytes: [UInt8]) -> Bool
    func installBridgeProfile(expectedOriginal: [UInt8]?) throws -> KeyboardKeymapInstallResult
    func restore(_ bytes: [UInt8]) throws -> [UInt8]
}

public protocol KeyboardLightingDriver: AnyObject, Sendable {
    var profileID: String { get }
    /// True only after D6 zone writes and readback have been validated for
    /// this exact model. D8-only models can still expose Agent status lights.
    var supportsFullLightingControl: Bool { get }
    /// Exact backlight modes accepted by this model's verified D6 path.
    var supportedBacklightModes: [KeyboardBacklightMode] { get }
    /// Exact sidelight modes exposed by the official configurator for this
    /// model. Models in the same S4 family do not necessarily share modes.
    var supportedSidelightModes: [KeyboardSidelightMode] { get }
    /// Returns a channel that is present on this Mac. A successful protocol
    /// read is still required before the UI marks lighting as available.
    func detectedConnection() -> KeyboardLightingConnection?
    /// Records which verified hardware path produced the latest keyboard
    /// input. Receivers and a charging USB cable can remain enumerated at the
    /// same time, so presence alone cannot identify the active radio path.
    func preferConnection(_ connection: KeyboardLightingConnection)
    func firmwareDescription() throws -> String
    func readStates() throws -> [KeyboardLightingState]
    func setBacklight(mode: KeyboardBacklightMode?, brightness: Int?,
                      color: KeyboardRGBColor?) throws -> [KeyboardLightingState]
    func setSidelight(mode: KeyboardSidelightMode?, brightness: Int?,
                      color: KeyboardRGBColor?) throws -> [KeyboardLightingState]
    func setStaticColor(_ color: KeyboardRGBColor, brightness: Int?) throws -> [KeyboardLightingState]
    func restore(_ states: [KeyboardLightingState]) throws -> [KeyboardLightingState]
    func restoreSidelight(from states: [KeyboardLightingState]) throws -> [KeyboardLightingState]
    func readSignalLights(indices: [UInt8]) throws -> [KeyboardSignalLight]
    @discardableResult
    func setSignalLights(_ lights: [KeyboardSignalLight]) throws -> [KeyboardSignalLight]
}

public protocol KeyboardSleepDriver: AnyObject, Sendable {
    var profileID: String { get }
    func readSleepConfiguration() throws -> KeyboardSleepConfiguration
    /// A nil duration disables automatic sleep and keeps the keyboard lights
    /// on until the keyboard is switched off or the user changes this setting.
    func setAutoSleep(afterMinutes minutes: Int?) throws -> KeyboardSleepConfiguration
}

extension Air75V3KeymapController: KeyboardKeymapDriver {
    public var profileID: String { "nuphy.air75-v3" }
    public var keymapSize: Int { Self.keymapByteCount }
    public func isPlausibleKeymap(_ bytes: [UInt8]) -> Bool { Self.isPlausibleKeymap(bytes) }
    public func containsBridgeProfile(_ bytes: [UInt8]) -> Bool { Self.hasBridgeProfile(bytes) }
}

extension Air75V3LightingController: KeyboardLightingDriver {}

extension Air75V3LightingController: KeyboardSleepDriver {}

/// The registry is the only place where a declarative profile gains write
/// capability. A JSON file alone can enable safe software recognition, but it
/// cannot authorize a vendor HID write path.
public enum KeyboardDriverRegistry {
    public static func keymapDriver(for profile: DeviceProfile?) -> (any KeyboardKeymapDriver)? {
        switch profile?.capabilities?.keymapDriverID {
        case "nuphy.s4.air75v3-keymap": return Air75V3KeymapController()
        default: return nil
        }
    }

    public static func lightingDriver(for profile: DeviceProfile?) -> (any KeyboardLightingDriver)? {
        switch profile?.capabilities?.lightingDriverID {
        case "nuphy.s4.17byte-lighting": return Air75V3LightingController()
        default: return nil
        }
    }

    public static func sleepDriver(for profile: DeviceProfile?) -> (any KeyboardSleepDriver)? {
        switch profile?.capabilities?.sleepDriverID {
        case "nuphy.s4.air75v3-sleep": return Air75V3LightingController()
        default: return nil
        }
    }
}
