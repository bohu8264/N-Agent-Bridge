import Air75AgentBridgeCore
import Foundation

/// Polls Codex's local rollout metadata without reading prompt/response text.
/// The sidebar's top user tasks come from Codex Desktop's own thread index
/// (`~/.codex/state_<N>.sqlite`); each task's five-state value is parsed from
/// the tail of its rollout file. When the index is unavailable the observer
/// falls back to the legacy directory scan and reports a single task.
final class CodexDesktopStatusObserver: @unchecked Sendable {
    static let maximumTaskCount = 6

    var handler: (([CodexTaskLightSnapshot]) -> Void)?

    private let codexHome: URL
    private let sessionRoot: URL
    private let threadIndexReader: CodexThreadIndexReader
    private let queue = DispatchQueue(label: "Air75AgentBridge.CodexStatus", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastPublishedKeys: [PublishedKey]?
    private var rolloutCache: [String: (modificationDate: Date, raw: CodexTaskLightSnapshot)] = [:]

    private struct PublishedKey: Equatable {
        var threadID: String?
        var state: CodexTaskLightState
    }

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)) {
        self.codexHome = codexHome
        sessionRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        threadIndexReader = CodexThreadIndexReader(codexHome: codexHome)
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

    private func poll() {
        let snapshots = currentSnapshots()
        let keys = snapshots.map { PublishedKey(threadID: $0.threadID, state: $0.state) }
        // Event timestamps change during a turn, but the lights only need an
        // update when a task identity or five-state value changes.
        if keys == lastPublishedKeys { return }
        lastPublishedKeys = keys
        handler?(snapshots)
    }

    private func currentSnapshots() -> [CodexTaskLightSnapshot] {
        let now = Date()
        let entries = threadIndexReader.topUserThreads(limit: Self.maximumTaskCount)
        if !entries.isEmpty {
            let snapshots = entries.map { entry in
                CodexRolloutStatusParser.applyDecay(
                    to: rawSnapshot(for: threadIndexReader.rolloutURL(for: entry), fallbackThreadID: entry.threadID),
                    now: now
                )
            }
            pruneCache(keeping: entries.map { threadIndexReader.rolloutURL(for: $0).path })
            return snapshots
        }

        // Codex 升级导致索引不可用时退回旧的目录扫描，仍提供单任务状态。
        if let rollout = mostRecentUserRollout(), let data = readTail(of: rollout, maximumBytes: 1_500_000) {
            return [CodexRolloutStatusParser.parse(data: data, now: now)]
        }
        return []
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
