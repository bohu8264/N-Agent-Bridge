import Foundation
import SQLite3

/// One sidebar task from Codex Desktop's local thread index.
public struct CodexThreadIndexEntry: Equatable, Sendable {
    public var threadID: String
    public var rolloutPath: String
    public var recencyAtMS: Int64

    public init(threadID: String, rolloutPath: String, recencyAtMS: Int64) {
        self.threadID = threadID
        self.rolloutPath = rolloutPath
        self.recencyAtMS = recencyAtMS
    }
}

/// Reads the thread index that Codex Desktop maintains in `~/.codex/state_<N>.sqlite`.
/// The database is opened read-only and only structural columns are selected:
/// thread id, rollout file path and recency. Titles, previews and prompt
/// content are never queried, matching the app's privacy contract.
public final class CodexThreadIndexReader: @unchecked Sendable {
    private let codexHome: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    /// Codex bumps the schema number in the file name across migrations
    /// (`state_5.sqlite` today). Pick the highest one that exists instead of
    /// hardcoding the current version.
    public func currentDatabaseURL() -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var best: (version: Int, url: URL)?
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst("state_".count).dropLast(".sqlite".count))
            else { continue }
            if best == nil || version > best!.version { best = (version, url) }
        }
        return best?.url
    }

    /// The top sidebar tasks: user-owned, not archived, most recent user
    /// activity first. Returns an empty array whenever the index is missing or
    /// unreadable so callers can fall back to directory scanning.
    public func topUserThreads(limit: Int, databaseURL: URL? = nil) -> [CodexThreadIndexEntry] {
        guard limit > 0, let dbURL = databaseURL ?? currentDatabaseURL() else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close_v2(database)
            return []
        }
        defer { sqlite3_close_v2(database) }
        sqlite3_busy_timeout(database, 250)

        // Only structural columns. `thread_source` NULL is treated as a user
        // thread, mirroring the rollout header heuristic used elsewhere.
        let sql = """
        SELECT id, rollout_path, COALESCE(recency_at_ms, 0)
        FROM threads
        WHERE COALESCE(thread_source, 'user') = 'user'
          AND COALESCE(archived, 0) = 0
          AND rollout_path IS NOT NULL
        ORDER BY COALESCE(recency_at_ms, 0) DESC
        LIMIT ?1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var entries: [CodexThreadIndexEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let pathText = sqlite3_column_text(statement, 1) else { continue }
            entries.append(CodexThreadIndexEntry(
                threadID: String(cString: idText),
                rolloutPath: String(cString: pathText),
                recencyAtMS: sqlite3_column_int64(statement, 2)
            ))
        }
        return entries
    }

    /// Rollout paths in the index are usually absolute; resolve relative ones
    /// against `~/.codex` for robustness.
    public func rolloutURL(for entry: CodexThreadIndexEntry) -> URL {
        entry.rolloutPath.hasPrefix("/")
            ? URL(fileURLWithPath: entry.rolloutPath)
            : codexHome.appendingPathComponent(entry.rolloutPath)
    }
}
