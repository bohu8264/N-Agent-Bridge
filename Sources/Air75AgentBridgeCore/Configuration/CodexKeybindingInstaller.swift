import Foundation

public struct CodexKeybinding: Codable, Hashable, Sendable {
    public var command: String
    public var key: String?

    public init(command: String, key: String?) {
        self.command = command
        self.key = key
    }

    private enum CodingKeys: String, CodingKey { case command, key }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        key = try container.decodeIfPresent(String.self, forKey: .key)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        if let key { try container.encode(key, forKey: .key) }
        else { try container.encodeNil(forKey: .key) }
    }
}

public struct CodexKeybindingInstallResult: Sendable {
    public var keybindingsURL: URL
    public var backupURL: URL?
    public var changed: Bool

    public init(keybindingsURL: URL, backupURL: URL?, changed: Bool) {
        self.keybindingsURL = keybindingsURL
        self.backupURL = backupURL
        self.changed = changed
    }
}

public final class CodexKeybindingInstaller: @unchecked Sendable {
    public static let managedBindings: [CodexKeybinding] = [
        .init(command: "thread1", key: "Command+1"),
        .init(command: "thread2", key: "Command+2"),
        .init(command: "thread3", key: "Command+3"),
        .init(command: "thread4", key: "Command+4"),
        .init(command: "thread5", key: "Command+5"),
        .init(command: "thread6", key: "Command+6"),
        .init(command: "composer.toggleFastMode", key: "Ctrl+Alt+Command+F"),
        .init(command: "approval.approve", key: "Enter"),
        .init(command: "approval.decline", key: "Escape"),
        .init(command: "newTask", key: "Command+N"),
        .init(command: "newTask", key: "Command+Shift+O"),
        .init(command: "composer.startDictation", key: "F11"),
        .init(command: "composer.startDictation", key: "Ctrl+Shift+D"),
        .init(command: "composer.submit", key: "Ctrl+Alt+Command+Enter"),
        .init(command: "composer.decreaseReasoningEffort", key: "Ctrl+Alt+Command+["),
        .init(command: "composer.openModelPicker", key: "Ctrl+Shift+M"),
        .init(command: "composer.increaseReasoningEffort", key: "Ctrl+Alt+Command+]")
    ]

    private static let retiredManagedKeys = Set(
        ["F1", "F2", "F3", "Command+O"] + (13...24).map { "F\($0)" }
    )

    public let codexHome: URL
    public let backupDirectory: URL

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        backupDirectory: URL? = nil
    ) {
        self.codexHome = codexHome
        self.backupDirectory = backupDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Air75AgentBridge/Backups", isDirectory: true)
    }

    public var keybindingsURL: URL { codexHome.appendingPathComponent("keybindings.json") }

    public func isInstalled() -> Bool {
        guard let bindings = try? loadBindings() else { return false }
        return Self.managedBindings.allSatisfy(bindings.contains)
    }

    @discardableResult
    public func install() throws -> CodexKeybindingInstallResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let originalData = try? Data(contentsOf: keybindingsURL)
        var bindings = try loadBindings()

        // Normalize the one legacy command name Codex itself migrates at read time.
        bindings = bindings.map { binding in
            binding.command == "newThread" ? CodexKeybinding(command: "newTask", key: binding.key) : binding
        }

        let managedCommands = Set(Self.managedBindings.map(\.command))
        let reservedKeys = Set(Self.managedBindings.compactMap(\.key))
        let managedByKey: [String: String] = Dictionary(uniqueKeysWithValues: Self.managedBindings.compactMap { binding -> (String, String)? in
            guard let key = binding.key else { return nil }
            return (key, binding.command)
        })
        bindings.removeAll { binding in
            guard let key = binding.key else { return false }
            if Self.retiredManagedKeys.contains(key), managedCommands.contains(binding.command) { return true }
            guard reservedKeys.contains(key), let command = managedByKey[key] else { return false }
            return binding.command != command
        }
        for binding in Self.managedBindings where !bindings.contains(binding) { bindings.append(binding) }
        bindings = unique(bindings).sorted {
            $0.command == $1.command ? ($0.key ?? "") < ($1.key ?? "") : $0.command < $1.command
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var encoded = try encoder.encode(bindings)
        encoded.append(0x0A)
        if originalData == encoded { return .init(keybindingsURL: keybindingsURL, backupURL: nil, changed: false) }

        var backupURL: URL?
        if let originalData {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let destination = backupDirectory.appendingPathComponent("\(stamp)-codex-keybindings.json")
            try originalData.write(to: destination, options: .atomic)
            backupURL = destination
        }
        try encoded.write(to: keybindingsURL, options: .atomic)
        guard isInstalled() else { throw CocoaError(.fileWriteUnknown) }
        return .init(keybindingsURL: keybindingsURL, backupURL: backupURL, changed: true)
    }

    private func loadBindings() throws -> [CodexKeybinding] {
        guard FileManager.default.fileExists(atPath: keybindingsURL.path) else { return [] }
        let data = try Data(contentsOf: keybindingsURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([CodexKeybinding].self, from: data)
    }

    private func unique(_ bindings: [CodexKeybinding]) -> [CodexKeybinding] {
        var seen = Set<CodexKeybinding>()
        return bindings.filter { seen.insert($0).inserted }
    }
}
