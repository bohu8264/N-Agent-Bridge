import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One sidebar task from Codex Desktop's local thread index.
public struct CodexThreadIndexEntry: Equatable, Sendable {
    public var threadID: String
    public var rolloutPath: String
    public var recencyAtMS: Int64
    public var title: String?
    public var projectPath: String?

    public init(threadID: String, rolloutPath: String, recencyAtMS: Int64,
                title: String? = nil, projectPath: String? = nil) {
        self.threadID = threadID
        self.rolloutPath = rolloutPath
        self.recencyAtMS = recencyAtMS
        self.title = title
        self.projectPath = projectPath
    }
}

/// Reads the thread index that Codex Desktop maintains in `~/.codex/state_<N>.sqlite`.
/// The database is opened read-only and only structural columns are selected:
/// thread id, rollout file path, recency, title and project directory. Prompt,
/// response and preview content are never queried.
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
        let availableColumns = threadColumns(in: database)
        let titleExpression = availableColumns.contains("title") ? "title" : "NULL"
        let cwdExpression = availableColumns.contains("cwd") ? "cwd" : "NULL"
        let sql = """
        SELECT id, rollout_path, COALESCE(recency_at_ms, 0), \(titleExpression), \(cwdExpression)
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
                recencyAtMS: sqlite3_column_int64(statement, 2),
                title: sqlite3_column_text(statement, 3).map { String(cString: $0) },
                projectPath: sqlite3_column_text(statement, 4).map { String(cString: $0) }
            ))
        }
        return entries
    }

    /// Looks up exact stable IDs in addition to the recent window. This keeps
    /// old custom/pinned assignments live without parsing every historical
    /// rollout on each poll.
    public func userThreads(withIDs ids: Set<String>, databaseURL: URL? = nil) -> [CodexThreadIndexEntry] {
        guard !ids.isEmpty, let dbURL = databaseURL ?? currentDatabaseURL() else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close_v2(database)
            return []
        }
        defer { sqlite3_close_v2(database) }
        sqlite3_busy_timeout(database, 250)
        let availableColumns = threadColumns(in: database)
        let titleExpression = availableColumns.contains("title") ? "title" : "NULL"
        let cwdExpression = availableColumns.contains("cwd") ? "cwd" : "NULL"
        let sql = """
        SELECT id, rollout_path, COALESCE(recency_at_ms, 0), \(titleExpression), \(cwdExpression)
        FROM threads
        WHERE id = ?1
          AND COALESCE(thread_source, 'user') = 'user'
          AND COALESCE(archived, 0) = 0
          AND rollout_path IS NOT NULL
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var entries: [CodexThreadIndexEntry] = []
        for id in ids.sorted() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, id, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let idText = sqlite3_column_text(statement, 0),
                  let pathText = sqlite3_column_text(statement, 1) else { continue }
            entries.append(CodexThreadIndexEntry(
                threadID: String(cString: idText),
                rolloutPath: String(cString: pathText),
                recencyAtMS: sqlite3_column_int64(statement, 2),
                title: sqlite3_column_text(statement, 3).map { String(cString: $0) },
                projectPath: sqlite3_column_text(statement, 4).map { String(cString: $0) }
            ))
        }
        return entries
    }

    private func threadColumns(in database: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                names.insert(String(cString: name))
            }
        }
        return names
    }

    /// Rollout paths in the index are usually absolute; resolve relative ones
    /// against `~/.codex` for robustness.
    public func rolloutURL(for entry: CodexThreadIndexEntry) -> URL {
        entry.rolloutPath.hasPrefix("/")
            ? URL(fileURLWithPath: entry.rolloutPath)
            : codexHome.appendingPathComponent(entry.rolloutPath)
    }
}
