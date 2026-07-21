import Foundation

/// Extracts only stable thread IDs and the user-facing `name` field from a
/// Codex app-server `thread/list` response. The response also contains a
/// first-message preview, but N Agent Bridge deliberately does not return,
/// persist or log that field.
public enum CodexThreadListTitleIndex {
    public static func titles(in response: Any) -> [String: String] {
        let root = response as? [String: Any]
        let result = root?["result"] as? [String: Any] ?? root
        guard let threads = result?["data"] as? [[String: Any]] else { return [:] }
        return threads.reduce(into: [String: String]()) { output, thread in
            guard let id = thread["id"] as? String,
                  let rawName = thread["name"] as? String else { return }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty else { return }
            output[id] = name
        }
    }

    public static func titles(in data: Data) -> [String: String] {
        guard let response = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return titles(in: response)
    }
}
