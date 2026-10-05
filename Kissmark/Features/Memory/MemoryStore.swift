import Foundation
import os
import SQLite3

/// A stored review point (ADR 0028 round 2).
struct ReviewPoint: Equatable {
    let id: Int64
    let source: String
    let kind: String
    let heading: String?
    let quote: String
    let note: String?
    let checkedAt: Date?
    let comment: String?
}

/// A Document from the recents list (ADR 0028 round 3).
struct RecentDocument: Equatable {
    let path: String
    let title: String
    let lastOpenedAt: Date
    /// Opener of the latest open: `agent` or `user`.
    let opener: String
    let bookmark: Data?
}

/// SQLite record of every Document the app shows (ADR 0028).
/// Failures are logged and swallowed: memory never blocks opening a Document.
final class MemoryStore {
    static let live = MemoryStore(
        directory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kissmark", isDirectory: true)
    )

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kissmark", category: "memory")
    private let db: OpaquePointer?
    private let queueDirectory: URL

    init(directory: URL) {
        queueDirectory = directory.appendingPathComponent("queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dbPointer: OpaquePointer?
        let databasePath = directory.appendingPathComponent("memory.sqlite").path
        guard sqlite3_open_v2(databasePath, &dbPointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            logger.error("memory: cannot open \(databasePath, privacy: .public)")
            db = nil
            return
        }
        db = dbPointer
        exec("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS documents (
          path TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          first_opened_at REAL NOT NULL,
          last_opened_at REAL NOT NULL,
          open_count INTEGER NOT NULL DEFAULT 0,
          bookmark BLOB
        );
        CREATE TABLE IF NOT EXISTS opens (
          id INTEGER PRIMARY KEY,
          path TEXT NOT NULL REFERENCES documents(path),
          opened_at REAL NOT NULL,
          opener TEXT NOT NULL CHECK (opener IN ('agent', 'user')),
          project TEXT,
          host TEXT,
          agent TEXT,
          session TEXT
        );
        CREATE INDEX IF NOT EXISTS opens_path_time ON opens(path, opened_at DESC);
        CREATE VIRTUAL TABLE IF NOT EXISTS document_text
          USING fts5(path UNINDEXED, title, body, tokenize = 'trigram');
        CREATE TABLE IF NOT EXISTS review_points (
          id INTEGER PRIMARY KEY,
          path TEXT NOT NULL REFERENCES documents(path),
          source TEXT NOT NULL CHECK (source IN ('agent', 'rule')),
          kind TEXT NOT NULL CHECK (kind IN ('agent', 'decision', 'warning', 'failure', 'next', 'task', 'changed')),
          heading TEXT,
          quote TEXT NOT NULL,
          note TEXT,
          created_at REAL NOT NULL,
          checked_at REAL,
          comment TEXT,
          host TEXT,
          agent TEXT,
          session TEXT
        );
        CREATE INDEX IF NOT EXISTS review_points_path ON review_points(path, checked_at);
        CREATE TABLE IF NOT EXISTS review_completions (
          path TEXT PRIMARY KEY REFERENCES documents(path),
          completed_at REAL NOT NULL,
          snapshot TEXT NOT NULL
        );
        PRAGMA user_version = 3;
        """)
        let hasBookmark = ((try? query("SELECT 1 FROM pragma_table_info('documents') WHERE name = 'bookmark'")) ?? []).isEmpty == false
        if !hasBookmark { exec("ALTER TABLE documents ADD COLUMN bookmark BLOB") }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func recordOpen(url: URL, text: String, at: Date = .now) {
        guard let db else { return }
        do {
            let path = normalize(url)
            let title = url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
            let drained = drainQueue(path: path)
            #if os(macOS)
            let bookmark = try? url.bookmarkData(options: .withSecurityScope)
            #else
            let bookmark = try? url.bookmarkData()
            #endif
            try run {
                try upsertDocument(path: path, title: title, at: at, bookmark: bookmark)
                try insertOpen(path: path, at: at, provenance: drained.provenance)
                try replaceText(path: path, title: title, body: text)
                for point in drained.points {
                    try insertPoint(
                        path: path, source: "agent", kind: "agent",
                        heading: point.heading, quote: point.quote, note: point.note,
                        at: at, host: point.host, agent: point.agent, session: point.session
                    )
                }
                try refreshRulePoints(path: path, text: text, at: at)
            }
            // Only after the commit: a failed write leaves the entries for the next open.
            for file in drained.consumed {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            logger.error("memory: recordOpen failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func completeReview(url: URL, text: String, at: Date = .now) {
        guard let db else { return }
        do {
            let path = normalize(url)
            try run {
                let upsert = try prepare("INSERT INTO review_completions (path, completed_at, snapshot) VALUES (?, ?, ?) ON CONFLICT(path) DO UPDATE SET completed_at = excluded.completed_at, snapshot = excluded.snapshot")
                defer { sqlite3_finalize(upsert) }
                bind(upsert, 1, path)
                sqlite3_bind_double(upsert, 2, at.timeIntervalSince1970)
                bind(upsert, 3, text)
                try step(upsert)

                let check = try prepare("UPDATE review_points SET checked_at = ? WHERE path = ? AND checked_at IS NULL")
                defer { sqlite3_finalize(check) }
                sqlite3_bind_double(check, 1, at.timeIntervalSince1970)
                bind(check, 2, path)
                try step(check)
            }
        } catch {
            logger.error("memory: completeReview failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkPoint(id: Int64, comment: String?, at: Date = .now) {
        guard let db else { return }
        do {
            try run {
                let statement = try prepare("UPDATE review_points SET checked_at = ?, comment = ? WHERE id = ?")
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_double(statement, 1, at.timeIntervalSince1970)
                bind(statement, 2, comment)
                sqlite3_bind_int64(statement, 3, id)
                try step(statement)
            }
        } catch {
            logger.error("memory: checkPoint failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reviewPoints(for url: URL) -> [ReviewPoint] {
        guard let db else { return [] }
        do {
            return try query("SELECT id, source, kind, heading, quote, note, checked_at, comment FROM review_points WHERE path = ? ORDER BY created_at, id") {
                self.bind($0, 1, self.normalize(url))
            }.map { row in
                ReviewPoint(
                    id: row[0].flatMap { Int64($0) } ?? 0,
                    source: row[1] ?? "",
                    kind: row[2] ?? "",
                    heading: row[3],
                    quote: row[4] ?? "",
                    note: row[5],
                    checkedAt: row[6].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) },
                    comment: row[7]
                )
            }
        } catch {
            logger.error("memory: reviewPoints failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Steps

    struct IngestedPoint {
        let heading: String?
        let quote: String
        let note: String?
        let host: String?
        let agent: String?
        let session: String?
    }

    private struct Drained {
        var provenance: (project: String?, host: String?, agent: String?, session: String?)?
        var points: [IngestedPoint] = []
        /// Matching queue files, deleted once their contents are committed.
        var consumed: [URL] = []
    }

    private func drainQueue(path: String) -> Drained {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: queueDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var drained = Drained()
        var newest: (date: Date, entry: QueueEntry, file: URL)?
        var newestReviewDate: Date?
        for file in files where file.lastPathComponent.hasSuffix(".json") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let stale = modified < Date(timeInterval: -600, since: .now)
            guard let data = try? Data(contentsOf: file), let entry = try? JSONDecoder().decode(QueueEntry.self, from: data) else {
                try? FileManager.default.removeItem(at: file)  // unparseable
                continue
            }
            if stale {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            guard entry.path == path else { continue }
            if entry.kind == "review_points" {
                drained.points.append(contentsOf: (entry.points ?? []).map {
                    IngestedPoint(heading: $0.heading, quote: $0.quote, note: $0.note,
                                  host: entry.host, agent: entry.agent, session: entry.session)
                })
                drained.consumed.append(file)
                if newestReviewDate == nil || modified > newestReviewDate! {
                    newestReviewDate = modified
                    drained.provenance = (entry.project, entry.host, entry.agent, entry.session)
                }
                continue
            }
            if newest == nil || modified > newest!.date {
                newest = (modified, entry, file)
            }
        }
        guard let newest else { return drained }
        drained.consumed.append(newest.file)
        drained.provenance = (newest.entry.project, newest.entry.host, newest.entry.agent, newest.entry.session)
        drained.points.append(contentsOf: (newest.entry.points ?? []).map {
            IngestedPoint(heading: $0.heading, quote: $0.quote, note: $0.note,
                          host: newest.entry.host, agent: newest.entry.agent, session: newest.entry.session)
        })
        return drained
    }

    private struct QueuedPoint: Decodable {
        let heading: String?
        let quote: String
        let note: String?
    }

    private struct QueueEntry: Decodable {
        let kind: String?
        let path: String
        let project: String?
        let host: String?
        let agent: String?
        let session: String?
        let points: [QueuedPoint]?
    }

    private func upsertDocument(path: String, title: String, at: Date, bookmark: Data?) throws {
        let statement = try prepare("INSERT INTO documents (path, title, first_opened_at, last_opened_at, open_count, bookmark) VALUES (?, ?, ?, ?, 1, ?) ON CONFLICT(path) DO UPDATE SET title = excluded.title, last_opened_at = excluded.last_opened_at, open_count = open_count + 1, bookmark = COALESCE(excluded.bookmark, bookmark)")
        defer { sqlite3_finalize(statement) }
        let seconds = at.timeIntervalSince1970
        sqlite3_bind_text(statement, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 2, title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(statement, 3, seconds)
        sqlite3_bind_double(statement, 4, seconds)
        if let bookmark {
            _ = bookmark.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        } else {
            sqlite3_bind_null(statement, 5)
        }
        try step(statement)
    }

    func uncheckPoint(id: Int64) {
        guard db != nil else { return }
        do {
            try run {
                let statement = try prepare("UPDATE review_points SET checked_at = NULL, comment = NULL WHERE id = ?")
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_int64(statement, 1, id)
                try step(statement)
            }
        } catch {
            logger.error("memory: uncheckPoint failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reviewCompletion(for url: URL) -> Date? {
        guard db != nil else { return nil }
        let rows = try? query("SELECT completed_at FROM review_completions WHERE path = ?") {
            self.bind($0, 1, self.normalize(url))
        }
        return rows?.first?.first.flatMap { $0 }.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
    }

    func recentDocuments(limit: Int) -> [RecentDocument] {
        guard db != nil else { return [] }
        let sql = """
        SELECT path, title, last_opened_at,
          COALESCE((SELECT opener FROM opens WHERE opens.path = documents.path ORDER BY opened_at DESC, id DESC LIMIT 1), 'user'),
          bookmark
        FROM documents ORDER BY last_opened_at DESC LIMIT ?
        """
        do {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(limit))
            var result: [RecentDocument] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let text = { (index: Int32) in sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
                let bytes = sqlite3_column_bytes(statement, 4)
                result.append(RecentDocument(
                    path: text(0), title: text(1),
                    lastOpenedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    opener: text(3),
                    bookmark: bytes > 0 ? sqlite3_column_blob(statement, 4).map { Data(bytes: $0, count: Int(bytes)) } : nil
                ))
            }
            return result
        } catch {
            logger.error("memory: recentDocuments failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }


    private func insertOpen(path: String, at: Date, provenance: (project: String?, host: String?, agent: String?, session: String?)?) throws {
        let statement = try prepare("INSERT INTO opens (path, opened_at, opener, project, host, agent, session) VALUES (?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(statement, 2, at.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, provenance == nil ? "user" : "agent", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 4, provenance?.project, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 5, provenance?.host, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 6, provenance?.agent, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 7, provenance?.session, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        try step(statement)
    }

    private func replaceText(path: String, title: String, body: String) throws {
        let delete = try prepare("DELETE FROM document_text WHERE path = ?")
        defer { sqlite3_finalize(delete) }
        sqlite3_bind_text(delete, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        try step(delete)

        let insert = try prepare("INSERT INTO document_text (path, title, body) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_text(insert, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(insert, 2, title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(insert, 3, body, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        try step(insert)
    }

    private func insertPoint(
        path: String, source: String, kind: String,
        heading: String?, quote: String, note: String?, at: Date,
        host: String?, agent: String?, session: String?
    ) throws {
        let statement = try prepare("INSERT INTO review_points (path, source, kind, heading, quote, note, created_at, host, agent, session) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, path)
        bind(statement, 2, source)
        bind(statement, 3, kind)
        bind(statement, 4, heading)
        bind(statement, 5, quote)
        bind(statement, 6, note)
        sqlite3_bind_double(statement, 7, at.timeIntervalSince1970)
        bind(statement, 8, host)
        bind(statement, 9, agent)
        bind(statement, 10, session)
        try step(statement)
    }

    /// Deletes the path's unchecked rule points; regenerates them from `text`
    /// unless unchecked agent points exist. Checked (kind, heading, quote)
    /// triples are never regenerated.
    private func refreshRulePoints(path: String, text: String, at: Date) throws {
        let delete = try prepare("DELETE FROM review_points WHERE path = ? AND source = 'rule' AND checked_at IS NULL")
        defer { sqlite3_finalize(delete) }
        bind(delete, 1, path)
        try step(delete)

        let agentRows = try query("SELECT 1 FROM review_points WHERE path = ? AND source = 'agent' AND checked_at IS NULL") {
            self.bind($0, 1, path)
        }
        guard agentRows.isEmpty else { return }

        let snapshot = try query("SELECT snapshot FROM review_completions WHERE path = ?") {
            self.bind($0, 1, path)
        }.first?.first.flatMap { $0 }
        let checked = try query("SELECT kind, heading, quote FROM review_points WHERE path = ? AND checked_at IS NOT NULL") {
            self.bind($0, 1, path)
        }.compactMap { row in
            row[0].map { ReviewRules.Point(kind: $0, heading: row[1], quote: row[2] ?? "") }
        }
        for point in ReviewRules.points(in: text, snapshot: snapshot, checked: checked) {
            try insertPoint(
                path: path, source: "rule", kind: point.kind,
                heading: point.heading, quote: point.quote, note: nil,
                at: at, host: nil, agent: nil, session: nil
            )
        }
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in }) throws -> [[String?]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement)
        var rows: [[String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String?] = []
            for index in 0..<sqlite3_column_count(statement) {
                row.append(sqlite3_column_text(statement, index).map { String(cString: $0) })
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    // MARK: - SQLite plumbing

    private func normalize(_ url: URL) -> String {
        // NFC: symlink resolution can return decomposed Hangul; the helper normalizes the same way.
        url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
    }

    private func exec(_ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            logger.error("memory: schema failed: \(message, privacy: .public)")
            return
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MemoryStoreError(sqlite3_errmsg(db).map(String.init(cString:)) ?? "prepare failed")
        }
        return statement
    }

    private func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MemoryStoreError(sqlite3_errmsg(db).map(String.init(cString:)) ?? "step failed")
        }
    }

    private func run(_ body: () throws -> Void) throws {
        exec("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            exec("COMMIT")
        } catch {
            exec("ROLLBACK")
            throw error
        }
    }

    private struct MemoryStoreError: Error, LocalizedError {
        let message: String
        init(_ message: String?) { self.message = message ?? "unknown" }
        var errorDescription: String? { message }
    }
}
