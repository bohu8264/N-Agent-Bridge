import Foundation

/// Reads Codex Desktop's persisted short descriptions as a compatibility
/// fallback. The authoritative current title comes from app-server
/// `thread/list` as `Thread.name`; prompt, response and preview bodies are
/// never inspected.
public enum CodexSidebarTitleIndex {
    public static func titles(in jsonObject: Any) -> [String: String] {
        guard let raw = findValue(named: "thread-descriptions-v1", in: jsonObject)
                as? [String: Any] else { return [:] }
        return raw.reduce(into: [String: String]()) { result, element in
            guard let value = element.value as? String else { return }
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            result[element.key] = title
        }
    }

    public static func titles(in data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return titles(in: root)
    }

    /// App-server's `Thread.name` is authoritative. Persisted sidebar
    /// descriptions and SQLite title remain fallbacks for older Codex builds.
    public static func preferredTitle(
        for threadID: String,
        indexedTitle: String?,
        sidebarTitles: [String: String],
        appServerTitles: [String: String] = [:]
    ) -> String? {
        if let appServer = appServerTitles[threadID], !appServer.isEmpty { return appServer }
        if let sidebar = sidebarTitles[threadID], !sidebar.isEmpty { return sidebar }
        guard let indexedTitle else { return nil }
        let fallback = indexedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    private static func findValue(named target: String, in value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            if let exact = dictionary[target] { return exact }
            for child in dictionary.values {
                if let found = findValue(named: target, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findValue(named: target, in: child) { return found }
            }
        }
        return nil
    }
}
