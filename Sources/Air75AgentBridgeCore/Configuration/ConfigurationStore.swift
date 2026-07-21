import Foundation

public final class ConfigurationStore: @unchecked Sendable {
    public enum StoreError: LocalizedError {
        case encodingFailed
        case backupUnreadable

        public var errorDescription: String? {
            switch self {
            case .encodingFailed: return "无法编码配置"
            case .backupUnreadable: return "备份写入后无法重新读取"
            }
        }
    }

    public let applicationSupportURL: URL
    public let backupsURL: URL
    private let configurationURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(baseURL: URL? = nil) {
        // Keep the legacy on-disk directory so existing configuration and the
        // verified original-hardware backups survive the N Agent Bridge rename.
        let root = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Air75AgentBridge", isDirectory: true)
        applicationSupportURL = root
        backupsURL = root.appendingPathComponent("Backups", isDirectory: true)
        configurationURL = root.appendingPathComponent("configuration-v1.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    public func load() -> BridgeConfiguration {
        guard let data = try? Data(contentsOf: configurationURL),
              var value = try? decoder.decode(BridgeConfiguration.self, from: data) else {
            return BridgeConfiguration()
        }
        if value.schemaVersion < 2 {
            let isOriginalF13Profile = value.keyBindings.count == 12
                && value.keyBindings.allSatisfy { $0.usagePage == 0x07 }
                && value.keyBindings.map(\.usage) == Array(0x68...0x73)
            if isOriginalF13Profile { value.keyBindings = BridgeConfiguration.defaultBindings }
        }
        if value.schemaVersion < 3 {
            // Releases before schema 3 could save a configured keyboard with
            // both runtime switches off. Recover it once unless the user later
            // explicitly pauses mapping in a schema-3 build.
            if value.boundFingerprint != nil && value.mappingPausedByUser != true {
                value.enabled = true
                value.codexModeEnabled = true
                if value.mappingMode == .unavailable { value.mappingMode = .runtime }
            }
            value.schemaVersion = 3
            try? save(value)
        }
        if value.schemaVersion < 4 {
            // Schema 4 replaces the old whole-backlight Agent mode with the
            // requested sidelight-only five-state mode. Enable the new mode
            // once so an upgraded installation works immediately.
            value.agentLightingEnabled = true
            value.overlayEnabled = false
            value.schemaVersion = 4
            try? save(value)
        }
        if value.schemaVersion < 5 {
            value.taskLightPalette = .default
            value.schemaVersion = 5
            try? save(value)
        }
        if value.schemaVersion < 6 {
            if value.hardwareProfileInstalled == true, value.hardwareProfileID == nil {
                value.hardwareProfileID = "nuphy.air75-v3"
            }
            value.schemaVersion = 6
            try? save(value)
        }
        var requiresSchemaSave = false
        let repairedBindings = BridgeConfiguration.repairingUnsupportedBindings(
            value.keyBindings,
            hardwareProfileInstalled: value.hardwareProfileInstalled == true
        )
        if repairedBindings != value.keyBindings {
            value.keyBindings = repairedBindings
            requiresSchemaSave = true
        }
        if value.schemaVersion < 7 {
            value.schemaVersion = 7
            requiresSchemaSave = true
        }
        if value.schemaVersion < 8 {
            value.sidelightRestoredAfterSignalLights = false
            value.schemaVersion = 8
            requiresSchemaSave = true
        }
        if value.schemaVersion < 9 {
            value.agentSourceMode = .recent
            value.customAgentThreadIDs = Array(repeating: nil, count: 6)
            value.pinnedAgentThreadIDs = Array(repeating: nil, count: 6)
            let layoutID = value.hardwareProfileID == "nuphy.air75-v3"
                ? "nuphy.air75-v3.ansi-d8" : nil
            if layoutID != nil {
                value.keyBindings = value.keyBindings.map { binding in
                    var repaired = binding
                    repaired.signalLightIndex = SignalLightLayout.index(
                        layoutID: layoutID,
                        usagePage: binding.usagePage,
                        usage: binding.usage
                    )
                    return repaired
                }
            }
            value.schemaVersion = 9
            requiresSchemaSave = true
        }
        if value.schemaVersion < 10 {
            value.modelKeyBindings = nil
            value.schemaVersion = 10
            requiresSchemaSave = true
        }
        if value.schemaVersion < 11 {
            if value.hardwareProfileInstalled == true,
               let profileID = value.hardwareProfileID {
                value.hardwareProfileStates = [
                    profileID: InstalledHardwareProfileState(
                        installed: true,
                        backupName: value.hardwareProfileBackupName,
                        boundFingerprint: value.boundFingerprint
                    )
                ]
                var bindings = value.modelKeyBindings ?? [:]
                bindings[profileID] = value.keyBindings
                value.modelKeyBindings = bindings
            } else {
                value.hardwareProfileStates = [:]
            }
            value.schemaVersion = 11
            requiresSchemaSave = true
        }
        if value.schemaVersion < 12 {
            // Apply the verified indicator default once when each supported
            // model is next enabled over USB-C. This also repairs machines
            // upgraded from builds that left an arbitrary backlight mode.
            value.indicatorModeInitializedProfileIDs = []
            value.schemaVersion = 12
            requiresSchemaSave = true
        }
        if value.schemaVersion < 13 {
            // A 0.13.1 first-run configuration could persist the exact mixed
            // F1/F15/Tab/F4-F12 sequence. Repair both the legacy mirror and
            // every per-model copy according to that keyboard's installed
            // board-profile state. The full-signature check deliberately
            // leaves all other custom mappings intact.
            value.keyBindings = BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
                value.keyBindings,
                hardwareProfileInstalled: value.hardwareProfileInstalled == true
            )
            if var modelBindings = value.modelKeyBindings {
                for (profileID, bindings) in modelBindings {
                    modelBindings[profileID] = BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
                        bindings,
                        hardwareProfileInstalled: value.hasInstalledHardwareProfile(for: profileID)
                    )
                }
                value.modelKeyBindings = modelBindings
            }
            value.schemaVersion = 13
            requiresSchemaSave = true
        }
        if value.schemaVersion < 14 {
            // Schema 13 repaired the known mixed F13/F15/Tab sequence only
            // while upgrading from an older schema. A configuration first
            // written by that short-lived build could already claim schema 13
            // and therefore bypass the repair forever. Schema 14 applies the
            // same full-signature repair to every model copy. The strict
            // signature deliberately preserves genuine custom bindings.
            value.schemaVersion = 14
            requiresSchemaSave = true
        }
        let repairedLegacy = BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
            value.keyBindings,
            hardwareProfileInstalled: value.hardwareProfileInstalled == true
        )
        if repairedLegacy != value.keyBindings {
            value.keyBindings = repairedLegacy
            requiresSchemaSave = true
        }
        if var modelBindings = value.modelKeyBindings {
            for (profileID, bindings) in modelBindings {
                let repaired = BridgeConfiguration.repairingKnownCorruptedDefaultLayout(
                    bindings,
                    hardwareProfileInstalled: value.hasInstalledHardwareProfile(for: profileID)
                )
                if repaired != bindings {
                    modelBindings[profileID] = repaired
                    requiresSchemaSave = true
                }
            }
            value.modelKeyBindings = modelBindings
        }
        // A short-lived multi-model build derived Kick75 from the installed
        // Air profile and persisted only Agent 1 as F14 while the remaining
        // actions stayed F2-F12. That mixed sequence can never represent the
        // requested physical F1-F12 default; repair only this exact legacy
        // signature so real user customizations remain untouched.
        if var kickBindings = value.modelKeyBindings?["nuphy.kick75"],
           kickBindings.count == 12,
           kickBindings.map(\.usagePage) == Array(repeating: 0x07, count: 12),
           kickBindings.map(\.usage) == [0x69] + Array(0x3B...0x45),
           kickBindings.map(\.action) == BridgeConfiguration.defaultBindings.map(\.action) {
            kickBindings[0] = BridgeConfiguration.defaultBindings[0]
            var bindings = value.modelKeyBindings ?? [:]
            bindings["nuphy.kick75"] = kickBindings
            value.modelKeyBindings = bindings
            requiresSchemaSave = true
        }
        if requiresSchemaSave { try? save(value) }
        return value
    }

    public func save(_ configuration: BridgeConfiguration) throws {
        try prepareDirectories()
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: [.atomic, .completeFileProtection])
    }

    @discardableResult
    public func createRuntimeBackup(device: DeviceSnapshot, configuration: BridgeConfiguration, note: String) throws -> URL {
        try prepareDirectories()
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsURL.appendingPathComponent("\(stamp)-\(device.id)-runtime.json")
        let payload = RuntimeBackup(schemaVersion: 1, createdAt: Date(), device: device,
                                    configuration: configuration, hardwareProfileDataBase64: nil,
                                    note: note, checksum: "pending")
        var mutable = payload
        let firstPass = try encoder.encode(payload)
        mutable.checksum = FNV1a.hash(firstPass.base64EncodedString())
        let data = try encoder.encode(mutable)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        guard let readback = try? Data(contentsOf: url), readback == data else { throw StoreError.backupUnreadable }
        return url
    }

    public func listBackups() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: [.creationDateKey]))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    @discardableResult
    public func createLightingBackup(states: [Air75LightingState], note: String,
                                     profileID: String = "nuphy.air75-v3",
                                     deviceFingerprint: DeviceFingerprint? = nil) throws -> URL {
        try prepareDirectories()
        guard Set(states.map(\.handle)) == Set([0, 1]) else { throw StoreError.encodingFailed }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsURL.appendingPathComponent("\(stamp)-hardware-lighting.json")
        let backup = HardwareLightingBackup(schemaVersion: 2, createdAt: Date(), states: states, note: note,
                                            profileID: profileID, deviceFingerprint: deviceFingerprint)
        let data = try encoder.encode(backup)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        guard let readback = try? Data(contentsOf: url), readback == data else { throw StoreError.backupUnreadable }
        return url
    }

    public func loadLatestLightingBackup(profileID: String = "nuphy.air75-v3") -> HardwareLightingBackup? {
        for candidate in listBackups().filter({ $0.lastPathComponent.hasSuffix("-hardware-lighting.json") }) {
            guard let data = try? Data(contentsOf: candidate),
                  let backup = try? decoder.decode(HardwareLightingBackup.self, from: data),
                  backup.profileID == profileID || (backup.profileID == nil && profileID == "nuphy.air75-v3") else { continue }
            return backup
        }
        return nil
    }

    /// Returns the oldest valid lighting backup for this profile. It is the
    /// only backup guaranteed to predate all Bridge lighting writes and is
    /// therefore the correct source for retiring the legacy Codex sidelight.
    public func loadOriginalLightingBackup(profileID: String = "nuphy.air75-v3") -> HardwareLightingBackup? {
        for candidate in listBackups()
            .filter({ $0.lastPathComponent.hasSuffix("-hardware-lighting.json") })
            .reversed() {
            guard let data = try? Data(contentsOf: candidate),
                  let backup = try? decoder.decode(HardwareLightingBackup.self, from: data),
                  backup.profileID == profileID || (backup.profileID == nil && profileID == "nuphy.air75-v3") else {
                continue
            }
            return backup
        }
        return nil
    }

    @discardableResult
    public func createSleepBackup(configuration: KeyboardSleepConfiguration, note: String,
                                  profileID: String,
                                  deviceFingerprint: DeviceFingerprint? = nil) throws -> URL {
        try prepareDirectories()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsURL.appendingPathComponent("\(stamp)-hardware-sleep.json")
        let backup = HardwareSleepBackup(
            schemaVersion: 1,
            createdAt: Date(),
            configuration: configuration,
            note: note,
            profileID: profileID,
            deviceFingerprint: deviceFingerprint
        )
        let data = try encoder.encode(backup)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        guard let readback = try? Data(contentsOf: url), readback == data else {
            throw StoreError.backupUnreadable
        }
        return url
    }

    @discardableResult
    public func createKeymapBackup(data: [UInt8], note: String,
                                   profileID: String = "nuphy.air75-v3",
                                   deviceFingerprint: DeviceFingerprint? = nil) throws -> URL {
        guard !data.isEmpty else { throw StoreError.encodingFailed }
        try prepareDirectories()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsURL.appendingPathComponent("\(stamp)-hardware-keymap.json")
        let encoded = Data(data).base64EncodedString()
        let backup = HardwareKeymapBackup(schemaVersion: 2, createdAt: Date(),
                                          dataBase64: encoded, checksum: FNV1a.hash(encoded), note: note,
                                          profileID: profileID, deviceFingerprint: deviceFingerprint,
                                          byteCount: data.count)
        let bytes = try encoder.encode(backup)
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        guard let readback = try? Data(contentsOf: url), readback == bytes else { throw StoreError.backupUnreadable }
        return url
    }

    public func loadLatestKeymapBackup() -> HardwareKeymapBackup? {
        let latest = listBackups().first { $0.lastPathComponent.hasSuffix("-hardware-keymap.json") }
        guard let latest else { return nil }
        return loadKeymapBackup(at: latest)
    }

    public func loadKeymapBackup(named name: String) -> HardwareKeymapBackup? {
        guard URL(fileURLWithPath: name).lastPathComponent == name else { return nil }
        return loadKeymapBackup(at: backupsURL.appendingPathComponent(name))
    }

    public func loadOriginalKeymapBackup(preferredName: String? = nil) -> (url: URL, backup: HardwareKeymapBackup)? {
        loadOriginalKeymapBackup(
            profileID: "nuphy.air75-v3",
            expectedByteCount: Air75V3KeymapController.keymapByteCount,
            preferredName: preferredName,
            isPlausibleKeymap: Air75V3KeymapController.isPlausibleKeymap,
            isBridgeProfile: Air75V3KeymapController.hasBridgeProfile
        )
    }

    public func loadOriginalKeymapBackup(
        profileID: String,
        expectedByteCount: Int,
        preferredName: String? = nil,
        isPlausibleKeymap: ([UInt8]) -> Bool,
        isBridgeProfile: ([UInt8]) -> Bool
    ) -> (url: URL, backup: HardwareKeymapBackup)? {
        var candidates: [URL] = []
        if let preferredName,
           URL(fileURLWithPath: preferredName).lastPathComponent == preferredName {
            candidates.append(backupsURL.appendingPathComponent(preferredName))
        }
        candidates.append(contentsOf: listBackups().filter {
            $0.lastPathComponent.hasSuffix("-hardware-keymap.json")
                && !candidates.contains($0)
        })
        for url in candidates {
            guard let backup = loadKeymapBackup(at: url), let bytes = backup.bytes,
                  bytes.count == expectedByteCount,
                  backup.profileID == profileID || (backup.profileID == nil && profileID == "nuphy.air75-v3"),
                  isPlausibleKeymap(bytes),
                  !isBridgeProfile(bytes) else { continue }
            return (url, backup)
        }
        return nil
    }

    private func loadKeymapBackup(at url: URL) -> HardwareKeymapBackup? {
        guard let data = try? Data(contentsOf: url),
              let backup = try? decoder.decode(HardwareKeymapBackup.self, from: data),
              backup.checksum == FNV1a.hash(backup.dataBase64),
              let bytes = backup.bytes,
              bytes.count == (backup.byteCount ?? Air75V3KeymapController.keymapByteCount) else { return nil }
        return backup
    }
}

public struct RuntimeBackup: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var device: DeviceSnapshot
    public var configuration: BridgeConfiguration
    public var hardwareProfileDataBase64: String?
    public var note: String
    public var checksum: String
}

public struct HardwareLightingBackup: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var states: [Air75LightingState]
    public var note: String
    public var profileID: String?
    public var deviceFingerprint: DeviceFingerprint?
}

public struct HardwareSleepBackup: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var configuration: KeyboardSleepConfiguration
    public var note: String
    public var profileID: String
    public var deviceFingerprint: DeviceFingerprint?
}

public struct HardwareKeymapBackup: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var dataBase64: String
    public var checksum: String
    public var note: String
    public var profileID: String?
    public var deviceFingerprint: DeviceFingerprint?
    public var byteCount: Int?

    public var bytes: [UInt8]? { Data(base64Encoded: dataBase64).map(Array.init) }
}

public enum FNV1a {
    public static func hash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
