import Foundation

public struct DeviceProfileMatch: Sendable {
    public var profile: DeviceProfile
    public var recognition: RecognitionResult
    public var confidence: Int
}

/// Loads every bundled keyboard profile. New models are added as independent
/// JSON files and do not require widening Air75-specific name checks.
public struct DeviceProfileRegistry: Sendable {
    public let profiles: [DeviceProfile]

    public init(profiles: [DeviceProfile]) {
        self.profiles = profiles
    }

    public func profile(id: String?) -> DeviceProfile? {
        guard let id else { return nil }
        return profiles.first { $0.profileID == id }
    }

    public func bestMatch(
        vendorID: Int,
        productID: Int,
        product: String,
        manufacturer: String?,
        transport: ConnectionTransport,
        usagePage: Int,
        usage: Int,
        confirmedFingerprint: DeviceFingerprint?
    ) -> DeviceProfileMatch? {
        profiles.compactMap { profile -> DeviceProfileMatch? in
            let result = DeviceFingerprintMatcher.classify(
                vendorID: vendorID, productID: productID, product: product,
                manufacturer: manufacturer, transport: transport,
                usagePage: usagePage, usage: usage, profile: profile,
                confirmedFingerprint: confirmedFingerprint
            )
            let confidence: Int
            switch result {
            case .recognized(let value), .bluetoothCandidate(let value): confidence = value
            case .rejected: return nil
            }
            return DeviceProfileMatch(profile: profile, recognition: result, confidence: confidence)
        }.max { $0.confidence < $1.confidence }
    }

    public static func loadBundled(applicationBundle: Bundle = .main) -> DeviceProfileRegistry {
        let decoder = JSONDecoder()
        let resourceBundleName = "Air75AgentBridge_Air75AgentBridgeCore.bundle"
        let candidates = [
            applicationBundle.resourceURL?.appendingPathComponent(resourceBundleName, isDirectory: true),
            applicationBundle.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true),
            applicationBundle.bundleURL
                .appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(resourceBundleName, isDirectory: true)
        ].compactMap { $0 }
        let resourceBundle = candidates.lazy.compactMap(Bundle.init(url:)).first
        let urls = resourceBundle?.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let loaded = urls.compactMap { url -> DeviceProfile? in
            guard url.lastPathComponent != "Info.plist",
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DeviceProfile.self, from: data)
        }
        if !loaded.isEmpty { return DeviceProfileRegistry(profiles: loaded) }

        // A missing resource bundle must never prevent the app from opening.
        // The verified Air75 V3 profile is compiled in as a safe fallback;
        // release verification separately requires the packaged JSON so future
        // keyboard profiles cannot be lost silently.
        return DeviceProfileRegistry(profiles: [.air75V3Fallback])
    }
}

public extension DeviceProfile {
    static let air75V3Fallback = DeviceProfile(
        schemaVersion: 2,
        model: "NuPhy Air75 V3",
        usbIdentities: [
            .init(vendorID: 0x19F5, productID: 0x1028),
            .init(vendorID: 0x19F5, productID: 0x2620)
        ],
        bluetoothVendorIDs: [0x07D7, 0x19F5],
        productAliases: ["Air75 V3", "Air75 V3-1", "Air75 V3-2", "Air75 V3-3", "NuPhy Air75 V3 Dongle"],
        manufacturerAliases: ["NuPhy", "NuPhy Keyboard", "NuPhy Keybord"],
        allowedUsagePages: [1, 7, 12, 0xFF00, 0xFF60, 0xFFFF],
        specialUsages: Array(0x3A...0x45),
        id: "nuphy.air75-v3",
        protocolFamily: .nuphyS4,
        capabilities: KeyboardHardwareCapabilities(
            keymapDriverID: "nuphy.s4.air75v3-keymap",
            lightingDriverID: "nuphy.s4.17byte-lighting",
            sleepDriverID: "nuphy.s4.air75v3-sleep",
            keymapByteCount: Air75V3KeymapController.keymapByteCount,
            hasKnob: true,
            hasSidelight: true,
            supportsWirelessConfiguration: true,
            signalLightLayoutID: "nuphy.air75-v3.ansi-d8"
        )
    )
}
