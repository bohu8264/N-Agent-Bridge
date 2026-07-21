import Air75AgentBridgeCore
import Foundation

/// Polls Codex's local rollout metadata without reading prompt/response text.
/// Candidate user tasks come from Codex Desktop's own thread index
/// (`~/.codex/state_<N>.sqlite`), while unread/pinned IDs come from its global
/// UI state; each task's five-state value is parsed from the tail of its
/// rollout file. When the index is unavailable the observer falls back to the
/// legacy directory scan and reports a single task.
final class CodexDesktopStatusObserver: @unchecked Sendable {
    static let maximumTaskCount = 6
    /// Only this recent window (plus pinned/custom IDs) needs rollout parsing.
    /// The larger lightweight catalog below exists solely for the assignment UI.
    static let maximumStatusCandidateCount = 50
    static let maximumCatalogCount = 500
    static let statusHeartbeatInterval: TimeInterval = 30

    var handler: (([CodexTaskLightSnapshot]) -> Void)?

    private let codexHome: URL
    private let sessionRoot: URL
    private let threadIndexReader: CodexThreadIndexReader
    private let metadataReader: CodexDesktopMetadataReader
    private let queue = DispatchQueue(label: "Air75AgentBridge.CodexStatus", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastPublishedKeys: [PublishedKey]?
    private var lastPublishedAt: Date?
    private var rolloutCache: [String: (modificationDate: Date, raw: CodexTaskLightSnapshot)] = [:]
    private var trackedThreadIDs: Set<String> = []
    private var visibleConfirmationThreadID: String?
    private var appServerTitleByThreadID: [String: String] = [:]

    private struct PublishedKey: Equatable {
        var threadID: String?
        var state: CodexTaskLightState
        var isUnread: Bool
        var pinnedOrder: Int?
        var title: String?
        var recencyAtMS: Int64
        var projectID: String?
        var projectName: String?
        var projectOrder: Int?
    }

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)) {
        self.codexHome = codexHome
        sessionRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        threadIndexReader = CodexThreadIndexReader(codexHome: codexHome)
        metadataReader = CodexDesktopMetadataReader(codexHome: codexHome)
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in self?.poll() }
        timer = source
        source.resume()
    }

    func stop() {
        lock.lock()
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
    }

    func setTrackedThreadIDs(_ ids: Set<String>) {
        lock.lock()
        trackedThreadIDs = ids
        lastPublishedKeys = nil
        lastPublishedAt = nil
        lock.unlock()
    }

    /// Adds the live confirmation signal that Codex Desktop does not persist
    /// to rollout JSONL (notably MCP/app installation elicitation cards).
    func setVisibleConfirmationThreadID(_ threadID: String?) {
        lock.lock()
        guard visibleConfirmationThreadID != threadID else {
            lock.unlock()
            return
        }
        visibleConfirmationThreadID = threadID
        lastPublishedKeys = nil
        lastPublishedAt = nil
        lock.unlock()
    }

    /// Replaces stale first-message titles with Codex app-server's live
    /// `Thread.name` values. A changed name republishes the assignment catalog
    /// on the next one-second status pass.
    func setAppServerTitles(_ titles: [String: String]) {
        lock.lock()
        guard appServerTitleByThreadID != titles else {
            lock.unlock()
            return
        }
        appServerTitleByThreadID = titles
        lastPublishedKeys = nil
        lastPublishedAt = nil
        lock.unlock()
    }

    private func poll() {
        let snapshots = currentSnapshots()
        let now = Date()
        let keys = snapshots.map {
            PublishedKey(threadID: $0.threadID, state: $0.state, isUnread: $0.isUnread,
                         pinnedOrder: $0.pinnedOrder,
                         title: $0.title, recencyAtMS: $0.recencyAtMS,
                         projectID: $0.projectID, projectName: $0.projectName,
                         projectOrder: $0.projectOrder)
        }
        // Publish a low-frequency heartbeat even when the logical state does
        // not change. Some keyboard firmware clears transient D8 colors after
        // sleep; BridgeStore uses this heartbeat to reassert live statuses.
        lock.lock()
        if keys == lastPublishedKeys,
           let lastPublishedAt,
           now.timeIntervalSince(lastPublishedAt) < Self.statusHeartbeatInterval {
            lock.unlock()
            return
        }
        lastPublishedKeys = keys
        lastPublishedAt = now
        lock.unlock()
        handler?(snapshots)
    }

    private func currentSnapshots() -> [CodexTaskLightSnapshot] {
        let now = Date()
        let metadata = metadataReader.snapshot()
        let unreadThreadIDs = metadata.unreadThreadIDs
        let pinnedThreadIDs = metadata.pinnedThreadIDs
        let pinnedOrderByID = Dictionary(uniqueKeysWithValues: pinnedThreadIDs.enumerated().map { ($0.element, $0.offset) })
        lock.lock()
        let tracked = trackedThreadIDs
        let waitingThreadID = visibleConfirmationThreadID
        let appServerTitles = appServerTitleByThreadID
        lock.unlock()
        let catalogEntries = threadIndexReader.topUserThreads(limit: Self.maximumCatalogCount)
        let recentEntries = Array(catalogEntries.prefix(Self.maximumStatusCandidateCount))
        let recentIDs = Set(recentEntries.map(\.threadID))
        let exactIDs = tracked.union(pinnedThreadIDs).union(waitingThreadID.map { [$0] } ?? [])
        let catalogIDs = Set(catalogEntries.map(\.threadID))
        let exactEntries = threadIndexReader.userThreads(withIDs: exactIDs.subtracting(recentIDs))
        let statusEntries = recentEntries + exactEntries
        if !catalogEntries.isEmpty || !statusEntries.isEmpty {
            let statusSnapshots = statusEntries.map { entry -> CodexTaskLightSnapshot in
                let raw = rawSnapshot(
                    for: threadIndexReader.rolloutURL(for: entry),
                    fallbackThreadID: entry.threadID
                )
                let isUnread = unreadThreadIDs.contains(entry.threadID)
                // Unread completion may stay green, but unread must never
                // bypass stale-reasoning cleanup. Otherwise an interrupted
                // historical task remains blue forever on a fresh install.
                var snapshot = CodexRolloutStatusParser.applyDecay(
                    to: raw,
                    now: now,
                    preserveUnreadCompletion: isUnread
                )
                snapshot.threadID = entry.threadID
                snapshot.title = CodexSidebarTitleIndex.preferredTitle(
                    for: entry.threadID,
                    indexedTitle: entry.title,
                    sidebarTitles: metadata.sidebarTitleByThreadID,
                    appServerTitles: appServerTitles
                )
                snapshot.projectPath = entry.projectPath
                snapshot.recencyAtMS = entry.recencyAtMS
                snapshot.isUnread = unreadThreadIDs.contains(entry.threadID)
                snapshot.pinnedOrder = pinnedOrderByID[entry.threadID]
                applyProjectMetadata(to: &snapshot, threadID: entry.threadID,
                                     fallbackPath: entry.projectPath, metadata: metadata)
                applyVisibleConfirmation(to: &snapshot, threadID: entry.threadID,
                                         waitingThreadID: waitingThreadID, now: now)
                return snapshot
            }
            let statusByID = Dictionary(uniqueKeysWithValues: statusSnapshots.compactMap { snapshot in
                snapshot.threadID.map { ($0, snapshot) }
            })
            var snapshots = catalogEntries.map { entry -> CodexTaskLightSnapshot in
                if let live = statusByID[entry.threadID] { return live }
                var snapshot = CodexTaskLightSnapshot(
                    threadID: entry.threadID,
                    title: CodexSidebarTitleIndex.preferredTitle(
                        for: entry.threadID,
                        indexedTitle: entry.title,
                        sidebarTitles: metadata.sidebarTitleByThreadID,
                        appServerTitles: appServerTitles
                    ),
                    projectPath: entry.projectPath,
                    state: .idle,
                    eventDate: nil,
                    recencyAtMS: entry.recencyAtMS,
                    isUnread: unreadThreadIDs.contains(entry.threadID),
                    pinnedOrder: pinnedOrderByID[entry.threadID]
                )
                applyProjectMetadata(to: &snapshot, threadID: entry.threadID,
                                     fallbackPath: entry.projectPath, metadata: metadata)
                applyVisibleConfirmation(to: &snapshot, threadID: entry.threadID,
                                         waitingThreadID: waitingThreadID, now: now)
                return snapshot
            }
            snapshots.append(contentsOf: statusSnapshots.filter {
                guard let id = $0.threadID else { return false }
                return !catalogIDs.contains(id)
            })
            pruneCache(keeping: statusEntries.map { threadIndexReader.rolloutURL(for: $0).path })
            return snapshots
        }

        // Codex 升级导致索引不可用时退回旧的目录扫描，仍提供单任务状态。
        if let rollout = mostRecentUserRollout(), let data = readTail(of: rollout, maximumBytes: 1_500_000) {
            return [CodexRolloutStatusParser.parse(data: data, now: now)]
        }
        return []
    }

    private func applyVisibleConfirmation(
        to snapshot: inout CodexTaskLightSnapshot,
        threadID: String,
        waitingThreadID: String?,
        now: Date
    ) {
        guard waitingThreadID == threadID else { return }
        snapshot.state = .waitingForConfirmation
        snapshot.eventDate = now
    }

    private func applyProjectMetadata(
        to snapshot: inout CodexTaskLightSnapshot,
        threadID: String,
        fallbackPath: String?,
        metadata: CodexDesktopMetadataReader.Snapshot
    ) {
        let assignedProject = metadata.projectIDByThreadID[threadID]
            .flatMap { metadata.projectsByID[$0] }
        // Codex keeps historical thread-project assignments after a project is
        // removed or rebuilt. Only current `local-projects` belong in the
        // visible sidebar. For newer threads without an explicit assignment,
        // match the structural cwd against the current projects' rootPaths.
        let project = assignedProject ?? currentProject(
            matching: fallbackPath,
            projects: Array(metadata.projectsByID.values)
        )
        guard let project else { return }
        snapshot.projectID = project.id
        snapshot.projectName = project.name
        snapshot.projectOrder = project.order
        if snapshot.projectPath?.isEmpty != false {
            snapshot.projectPath = project.rootPaths.first
        }
    }

    private func currentProject(
        matching path: String?,
        projects: [CodexDesktopMetadataReader.Project]
    ) -> CodexDesktopMetadataReader.Project? {
        guard let path, !path.isEmpty else { return nil }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        return projects.compactMap { project -> (CodexDesktopMetadataReader.Project, Int)? in
            let matchingLength = project.rootPaths.map {
                URL(fileURLWithPath: $0).standardizedFileURL.path
            }.filter { root in
                candidate == root || candidate.hasPrefix(root + "/")
            }.map(\.count).max()
            return matchingLength.map { (project, $0) }
        }.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.order > rhs.0.order
        }?.0
    }

    /// Rollout files are large and mostly append-only: re-parse the tail only
    /// when the modification date moves, otherwise reuse the cached result.
    private func rawSnapshot(for url: URL, fallbackThreadID: String) -> CodexTaskLightSnapshot {
        let path = url.path
        let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if let cached = rolloutCache[path], cached.modificationDate == modificationDate {
            return cached.raw
        }
        var raw: CodexTaskLightSnapshot
        if let data = readTail(of: url, maximumBytes: 1_500_000) {
            raw = CodexRolloutStatusParser.parseRaw(data: data)
        } else {
            raw = CodexTaskLightSnapshot(threadID: fallbackThreadID, state: .idle, eventDate: nil)
        }
        // 大文件的 session_meta 可能不在尾部窗口内；线程身份以索引为准。
        if raw.threadID == nil { raw.threadID = fallbackThreadID }
        rolloutCache[path] = (modificationDate, raw)
        return raw
    }

    private func pruneCache(keeping paths: [String]) {
        guard rolloutCache.count > 32 else { return }
        let keep = Set(paths)
        rolloutCache = rolloutCache.filter { keep.contains($0.key) }
    }

    private func mostRecentUserRollout() -> URL? {
        let fileManager = FileManager.default
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd"

        var candidates: [(URL, Date)] = []
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let directory = sessionRoot.appendingPathComponent(formatter.string(from: day), isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                candidates.append((file, values.contentModificationDate ?? .distantPast))
            }
        }

        for candidate in candidates.sorted(by: { $0.1 > $1.1 }).prefix(24) {
            if isUserOwnedRollout(candidate.0) { return candidate.0 }
        }
        return nil
    }

    private func isUserOwnedRollout(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 64_000)) ?? nil
        guard let prefix else { return false }
        for rawLine in prefix.split(separator: 0x0A).prefix(8) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any] else { continue }
            let source = (payload["thread_source"] as? String)?.lowercased()
            return source == nil || source == "user"
        }
        return false
    }

    private func readTail(of url: URL, maximumBytes: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > maximumBytes ? size - maximumBytes : 0
        do {
            try handle.seek(toOffset: start)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }
}
