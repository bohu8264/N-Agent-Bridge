import Air75AgentBridgeCore
import Foundation

/// Reads only structural sidebar metadata from Codex Desktop: unread/pinned
/// thread IDs, project names/order and each thread's project assignment. Prompt
/// text, response text and preview content are never returned, logged or
/// persisted by N Agent Bridge.
final class CodexDesktopMetadataReader: @unchecked Sendable {
    struct Project: Equatable {
        var id: String
        var name: String
        var rootPaths: [String]
        var order: Int
    }

    struct Snapshot {
        var unreadThreadIDs: Set<String>
        var pinnedThreadIDs: [String]
        var projectsByID: [String: Project]
        var projectIDByThreadID: [String: String]
        var sidebarTitleByThreadID: [String: String]
    }

    private let stateURL: URL

    init(codexHome: URL) {
        stateURL = codexHome.appendingPathComponent(".codex-global-state.json")
    }

    func snapshot() -> Snapshot {
        guard let data = try? Data(contentsOf: stateURL),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return Snapshot(unreadThreadIDs: [], pinnedThreadIDs: [],
                            projectsByID: [:], projectIDByThreadID: [:],
                            sidebarTitleByThreadID: [:])
        }
        let unread = findStringSet(named: "unread-thread-ids-by-host-v1.local", in: root) ?? []
        // Codex stores pins as an ordered array. Preserve that order because
        // the first six pins are the six Agent slots in official pin mode.
        let pinned = (findValue(named: "pinned-thread-ids", in: root) as? [String]) ?? []
        let projectOrder = (findValue(named: "project-order", in: root) as? [String]) ?? []
        let orderByID = Dictionary(uniqueKeysWithValues: projectOrder.enumerated().map {
            ($0.element, $0.offset)
        })
        let rawProjects = (findValue(named: "local-projects", in: root) as? [String: Any]) ?? [:]
        let projects = rawProjects.reduce(into: [String: Project]()) { result, element in
            guard let value = element.value as? [String: Any] else { return }
            let id = value["id"] as? String ?? element.key
            let roots = value["rootPaths"] as? [String] ?? []
            let explicitName = (value["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = roots.first.map { URL(fileURLWithPath: $0).lastPathComponent }
            let name = explicitName?.isEmpty == false ? explicitName! : (fallbackName ?? "未命名项目")
            result[id] = Project(id: id, name: name, rootPaths: roots,
                                 order: orderByID[id] ?? Int.max)
        }
        let rawAssignments = (findValue(named: "thread-project-assignments", in: root)
                              as? [String: Any]) ?? [:]
        let assignments = rawAssignments.reduce(into: [String: String]()) { result, element in
            guard let value = element.value as? [String: Any],
                  let projectID = value["projectId"] as? String, !projectID.isEmpty else { return }
            result[element.key] = projectID
        }
        return Snapshot(
            unreadThreadIDs: unread,
            pinnedThreadIDs: pinned,
            projectsByID: projects,
            projectIDByThreadID: assignments,
            sidebarTitleByThreadID: CodexSidebarTitleIndex.titles(in: root)
        )
    }

    private func findValue(named target: String, in value: Any) -> Any? {
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

    private func findStringSet(named target: String, in value: Any) -> Set<String>? {
        if let dictionary = value as? [String: Any] {
            if let exact = dictionary[target] { return stringSet(from: exact) }
            for child in dictionary.values {
                if let found = findStringSet(named: target, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findStringSet(named: target, in: child) { return found }
            }
        }
        return nil
    }

    private func stringSet(from value: Any) -> Set<String> {
        if let values = value as? [String] { return Set(values) }
        if let dictionary = value as? [String: Any] {
            return Set(dictionary.compactMap { key, raw in
                if (raw as? Bool) == true { return key }
                if let number = raw as? NSNumber, number.boolValue { return key }
                return nil
            })
        }
        return []
    }
}
