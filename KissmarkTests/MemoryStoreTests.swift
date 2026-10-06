import Foundation
import SQLite3
import Testing

@testable import Kissmark

struct MemoryStoreTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("queue", isDirectory: true), withIntermediateDirectories: true)
    }

    private func makeStore() -> MemoryStore {
        MemoryStore(directory: root)
    }

    private func query(_ sql: String) throws -> [[String?]] {
        var db: OpaquePointer?
        try SQLiteCheck.__check(sqlite3_open_v2(root.appendingPathComponent("memory.sqlite").path, &db, SQLITE_OPEN_READONLY, nil))
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        try SQLiteCheck.__check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
        defer { sqlite3_finalize(statement) }
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

    /// Returns the first row as a flat string tuple; empty for no rows.
    private func scalar(_ sql: String) throws -> [String?] {
        try query(sql).first ?? []
    }

    private func writeQueueEntry(name: String, path: String, age: TimeInterval? = nil, body: String? = nil) throws {
        let entry = """
        {"version": 1, "kind": "open", "path": "\(path)", "requested_at": 0, \
        "project": "proj", "host": "claude-code", "agent": "omp", "session": "s1"}
        """
        let file = root.appendingPathComponent("queue", isDirectory: true).appendingPathComponent(name)
        try (body ?? entry).data(using: .utf8)!.write(to: file)
        if let age {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeInterval: -age, since: .now)], ofItemAtPath: file.path
            )
        }
    }

    struct TestPoint: Encodable {
        let heading: String?
        let quote: String
        let note: String?
    }

    struct TestEntry: Encodable {
        let version = 1
        let kind: String
        let path: String
        let requested_at = 0.0
        let host = "claude-code"
        let agent = "omp"
        let session = "s1"
        let points: [TestPoint]?
    }

    private func writeEntry(name: String, path: String, kind: String, points: [TestPoint]?, age: TimeInterval? = nil) throws {
        let data = try JSONEncoder().encode(TestEntry(kind: kind, path: path, points: points))
        let file = root.appendingPathComponent("queue", isDirectory: true).appendingPathComponent(name)
        try data.write(to: file)
        if let age {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeInterval: -age, since: .now)], ofItemAtPath: file.path
            )
        }
    }

    @Test func schemaHasUserVersionThree() throws {
        _ = makeStore()
        #expect(try scalar("PRAGMA user_version") == ["3"])
        #expect(try scalar("SELECT count(*) FROM pragma_table_info('documents') WHERE name = 'bookmark'") == ["1"])
    }

    @Test func v2StoreGainsBookmarkColumnWithDataKept() throws {
        let database = root.appendingPathComponent("memory.sqlite")
        var db: OpaquePointer?
        try SQLiteCheck.__check(sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil))
        try SQLiteCheck.__check(sqlite3_exec(db, """
        CREATE TABLE documents (path TEXT PRIMARY KEY, title TEXT NOT NULL, first_opened_at REAL NOT NULL, last_opened_at REAL NOT NULL, open_count INTEGER NOT NULL DEFAULT 0);
        PRAGMA user_version = 2;
        INSERT INTO documents (path, title, first_opened_at, last_opened_at, open_count) VALUES ('/old/노트.md', '노트', 1, 2, 3);
        """, nil, nil, nil))
        sqlite3_close(db)
        _ = makeStore()
        _ = makeStore()  // second open must not re-add the column
        #expect(try scalar("PRAGMA user_version") == ["3"])
        #expect(try scalar("SELECT path, open_count, bookmark IS NULL FROM documents") == ["/old/노트.md", "3", "1"])
    }

    @Test func titleSearchMatchesDecomposedKoreanFilename() throws {
        let document = root.appendingPathComponent("배포노트".decomposedStringWithCanonicalMapping + ".md")
        try "Title-only search fixture".write(to: document, atomically: true, encoding: .utf8)
        makeStore().recordOpen(url: document, text: "Title-only search fixture")

        #expect(try scalar("SELECT title FROM documents WHERE title LIKE '%배포노트%'") == ["배포노트"])
    }

    @Test func recordOpenStoresBookmarkAndUncheckClearsPoint() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "## 경고\n조심")
        let recent = try #require(store.recentDocuments(limit: 8).first)
        #expect(recent.bookmark != nil)
        let point = try #require(store.reviewPoints(for: document).first)
        store.checkPoint(id: point.id, comment: "확인함")
        store.uncheckPoint(id: point.id)
        let after = try #require(store.reviewPoints(for: document).first)
        #expect(after.checkedAt == nil)
        #expect(after.comment == nil)
    }

    @Test func reviewCompletionReturnsDateOrNil() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "본문")
        #expect(store.reviewCompletion(for: document) == nil)
        let when = Date(timeIntervalSince1970: 1_000_000)
        store.completeReview(url: document, text: "본문", at: when)
        #expect(store.reviewCompletion(for: document) == when)
    }

    @Test func recentDocumentsNewestFirstLimitedWithLatestOpener() throws {
        let store = makeStore()
        var urls: [URL] = []
        for name in ["a", "b", "c"] {
            let url = root.appendingPathComponent("\(name).md")
            try "본문".write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        store.recordOpen(url: urls[0], text: "본문", at: Date(timeIntervalSince1970: 100))
        store.recordOpen(url: urls[1], text: "본문", at: Date(timeIntervalSince1970: 200))
        store.recordOpen(url: urls[2], text: "본문", at: Date(timeIntervalSince1970: 300))
        try writeQueueEntry(name: "1-a.json", path: urls[0].resolvingSymlinksInPath().path)
        store.recordOpen(url: urls[0], text: "본문", at: Date(timeIntervalSince1970: 400))
        let recent = store.recentDocuments(limit: 2)
        #expect(recent.map(\.title) == ["a", "c"])
        #expect(recent.map(\.opener) == ["agent", "user"])
        #expect(recent[0].lastOpenedAt == Date(timeIntervalSince1970: 400))
        #expect(recent[0].path == urls[0].resolvingSymlinksInPath().path)
    }

    @Test func v1StoreMigratesWithDataKept() throws {
        let database = root.appendingPathComponent("memory.sqlite")
        var db: OpaquePointer?
        try SQLiteCheck.__check(sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil))
        try SQLiteCheck.__check(sqlite3_exec(db, """
        CREATE TABLE documents (path TEXT PRIMARY KEY, title TEXT NOT NULL, first_opened_at REAL NOT NULL, last_opened_at REAL NOT NULL, open_count INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE opens (id INTEGER PRIMARY KEY, path TEXT NOT NULL REFERENCES documents(path), opened_at REAL NOT NULL, opener TEXT NOT NULL CHECK (opener IN ('agent', 'user')), project TEXT, host TEXT, agent TEXT, session TEXT);
        CREATE VIRTUAL TABLE document_text USING fts5(path UNINDEXED, title, body, tokenize = 'trigram');
        PRAGMA user_version = 1;
        INSERT INTO documents (path, title, first_opened_at, last_opened_at, open_count) VALUES ('/old/노트.md', '노트', 1, 2, 3);
        """, nil, nil, nil))
        sqlite3_close(db)
        _ = makeStore()
        #expect(try scalar("PRAGMA user_version") == ["3"])
        #expect(try scalar("SELECT path, title, open_count FROM documents") == ["/old/노트.md", "노트", "3"])
    }

    @Test func openEntryPointsStoredWithProvenanceAndFileDeleted() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        try writeEntry(name: "1-a.json", path: document.path, kind: "open", points: [
            TestPoint(heading: "위험", quote: "디스크를 포맷한다", note: "조심")
        ])
        makeStore().recordOpen(url: document, text: "본문")
        let row = try scalar("SELECT source, kind, heading, quote, note, host, agent, session FROM review_points")
        #expect(row == ["agent", "agent", "위험", "디스크를 포맷한다", "조심", "claude-code", "omp", "s1"])
        let queueFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("queue"), includingPropertiesForKeys: nil)
        #expect(queueFiles.isEmpty)
    }

    @Test func reviewOnlyRequestKeepsRecentAgentIdentity() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let path = document.resolvingSymlinksInPath().path
        let store = makeStore()
        try writeQueueEntry(name: "open.json", path: path)
        store.recordOpen(url: document, text: "본문")
        try writeEntry(name: "review.json", path: path, kind: "review_points", points: [
            TestPoint(heading: nil, quote: "본문", note: nil)
        ])

        store.recordOpen(url: document, text: "본문")

        #expect(store.recentDocuments(limit: 1).first?.opener == "agent")
    }

    @Test func reviewPointsEntriesConsumedOpenKeptProvenance() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        try writeEntry(name: "1-a.json", path: document.path, kind: "review_points", points: [
            TestPoint(heading: nil, quote: "첫 문장", note: nil)
        ])
        try writeEntry(name: "2-b.json", path: document.path, kind: "review_points", points: [
            TestPoint(heading: "결정", quote: "둘째 문장", note: "메모")
        ])
        try writeEntry(name: "3-c.json", path: document.path, kind: "open", points: nil)
        try writeEntry(name: "4-d.json", path: root.appendingPathComponent("다른.md").path, kind: "review_points", points: [])
        makeStore().recordOpen(url: document, text: "본문")
        let rows = try query("SELECT source, kind, quote FROM review_points ORDER BY id")
        #expect(rows.map { [$0[0] ?? "", $0[1] ?? "", $0[2] ?? ""] } == [
            ["agent", "agent", "첫 문장"],
            ["agent", "agent", "둘째 문장"],
        ])
        let openRow = try scalar("SELECT opener, host FROM opens")
        #expect(openRow == ["agent", "claude-code"])
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("queue"), includingPropertiesForKeys: nil)
        #expect(files.map(\.lastPathComponent) == ["4-d.json"])
    }

    @Test func rulePointsForKindsTasksSkipFrontmatterFenceAndContext() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let text = """
        ---
        title: 메모
        ---

        ## 결정
        - SQLite를 쓴다

        ### context
        이건 다음이 아니다

        ```
        ## 경고
        코드 안이므로 무시
        ```

        ## Warning
        Caution advised here

        ## 다음
        1. 테스트를 돌린다

        ## 할 일
        - [ ] 우유를 사온다
        - [x] 끝낸 일
        """
        makeStore().recordOpen(url: document, text: text)
        let points = makeStore().reviewPoints(for: document)
        #expect(points.map { [$0.source, $0.kind, $0.quote] } == [
            ["rule", "warning", "Caution advised here"],
            ["rule", "decision", "SQLite를 쓴다"],
            ["rule", "next", "테스트를 돌린다"],
            ["rule", "task", "우유를 사온다"],
        ])
        #expect(points.map(\.heading) == ["Warning", "결정", "다음", "할 일"])
    }

    @Test func agentPointsSuppressRulePoints() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        try writeEntry(name: "1-a.json", path: document.path, kind: "open", points: [
            TestPoint(heading: nil, quote: "에이전트가 찾은 문장", note: nil)
        ])
        makeStore().recordOpen(url: document, text: "## 경고\n조심")
        let points = makeStore().reviewPoints(for: document)
        #expect(points.map { [$0.source, $0.kind, $0.quote] } == [["agent", "agent", "에이전트가 찾은 문장"]])
    }

    @Test func checkedRulePointNotRegenerated() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "## 경고\n첫 경고\n## 결정\n첫 결정")
        let first = store.reviewPoints(for: document)
        #expect(first.count == 2)
        store.checkPoint(id: first[0].id, comment: nil)
        store.recordOpen(url: document, text: "## 경고\n첫 경고\n## 결정\n첫 결정")
        let second = store.reviewPoints(for: document)
        // The checked warning point stays; the unchecked decision point is regenerated.
        #expect(second.map { [$0.kind, $0.checkedAt == nil ? "open" : "checked"] } == [["warning", "checked"], ["decision", "open"]])
    }

    @Test func completeReviewStoresSnapshotAndChecksPoints() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "## 경고\n조심")
        store.completeReview(url: document, text: "## 경고\n조심")
        let points = store.reviewPoints(for: document)
        #expect(points.count == 1)
        #expect(points[0].checkedAt != nil)
        #expect(try scalar("SELECT snapshot, completed_at IS NOT NULL FROM review_completions") == ["## 경고\n조심", "1"])
    }

    @Test func changedParagraphsSinceCompletion() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "기존 문단")
        store.completeReview(url: document, text: "기존 문단")
        store.recordOpen(url: document, text: "기존 문단\n\n새로 추가된 문단")
        let points = store.reviewPoints(for: document).filter { $0.kind == "changed" && $0.checkedAt == nil }
        #expect(points.map(\.quote) == ["새로 추가된 문단"])
        // Once checked, the changed point is not regenerated on reopen.
        store.checkPoint(id: try #require(points.first).id, comment: nil)
        store.recordOpen(url: document, text: "기존 문단\n\n새로 추가된 문단")
        #expect(store.reviewPoints(for: document).filter { $0.kind == "changed" && $0.checkedAt == nil }.isEmpty)
    }

    @Test func checkPointStoresComment() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "## 경고\n조심")
        let point = try #require(store.reviewPoints(for: document).first)
        store.checkPoint(id: point.id, comment: "확인함")
        let checked = try #require(store.reviewPoints(for: document).first)
        #expect(checked.checkedAt != nil)
        #expect(checked.comment == "확인함")
    }

    @Test func rulePointsCappedAtTwentyInPriorityOrder() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let tasks = (1...25).map { "- [ ] 항목 \($0)" }.joined(separator: "\n")
        makeStore().recordOpen(url: document, text: "## 경고\n조심\n## 할 일\n\(tasks)")
        let points = makeStore().reviewPoints(for: document)
        #expect(points.count == 20)
        #expect(points[0].kind == "warning")
        #expect(points.dropFirst().allSatisfy { $0.kind == "task" })
        #expect(points[1].quote == "항목 1")
    }

    @Test func firstOpenCreatesDocumentAsUser() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        makeStore().recordOpen(url: document, text: "본문")
        let row = try scalar("SELECT title, open_count, (SELECT opener FROM opens), (SELECT body FROM document_text) FROM documents")
        #expect(row == ["노트", "1", "user", "본문"])
    }

    @Test func secondOpenBumpsCountAndReplacesBody() throws {
        let document = root.appendingPathComponent("노트.md")
        try "첫".write(to: document, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "첫")
        store.recordOpen(url: document, text: "둘째 본문")
        let row = try scalar("SELECT open_count, (SELECT body FROM document_text), (SELECT count(*) FROM documents) FROM documents")
        #expect(row == ["2", "둘째 본문", "1"])
    }

    @Test func matchingQueueEntryMakesAgentOpenAndIsDeleted() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        try writeQueueEntry(name: "1-a.json", path: document.path)
        makeStore().recordOpen(url: document, text: "본문")
        let row = try scalar("SELECT opener, project, host, agent, session FROM opens")
        #expect(row == ["agent", "proj", "claude-code", "omp", "s1"])
        let queueFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("queue"), includingPropertiesForKeys: nil)
        #expect(queueFiles.isEmpty)
    }

    @Test func nonMatchingFreshEntryStays() throws {
        let document = root.appendingPathComponent("노트.md")
        let other = root.appendingPathComponent("다른.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        try writeQueueEntry(name: "1-a.json", path: other.path)
        makeStore().recordOpen(url: document, text: "본문")
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("queue"), includingPropertiesForKeys: nil)
        #expect(files.map(\.lastPathComponent) == ["1-a.json"])
    }

    @Test func staleAndUnparseableEntriesAreDeletedTmpIsIgnored() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        try writeQueueEntry(name: "1-stale.json", path: document.path, age: 601)
        try writeQueueEntry(name: "2-bad.json", path: document.path, body: "{not json")
        try writeQueueEntry(name: "3-kept.json.tmp", path: document.path, body: "{}")
        makeStore().recordOpen(url: document, text: "본문")
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("queue"), includingPropertiesForKeys: nil)
        #expect(files.map(\.lastPathComponent) == ["3-kept.json.tmp"])
    }

    @Test func symlinkedPathRecordsUnderResolvedPath() throws {
        let real = root.appendingPathComponent("실제")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let document = real.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("링크")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try writeQueueEntry(name: "1-a.json", path: document.standardizedFileURL.resolvingSymlinksInPath().path)
        makeStore().recordOpen(url: link.appendingPathComponent("노트.md"), text: "본문")
        let row = try scalar("SELECT path, (SELECT opener FROM opens) FROM documents")
        #expect(row == [document.standardizedFileURL.resolvingSymlinksInPath().path, "agent"])
    }

    @Test func textlessOpenReordersRecentsAndKeepsIndexedBody() throws {
        let document = root.appendingPathComponent("노트.md")
        try "본문".write(to: document, atomically: true, encoding: .utf8)
        let other = root.appendingPathComponent("다른.md")
        try "다른 본문".write(to: other, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.recordOpen(url: document, text: "본문", at: Date(timeIntervalSince1970: 1))
        store.recordOpen(url: other, text: "다른 본문", at: Date(timeIntervalSince1970: 2))

        // A load failed after the open: the request still counts and moves to the top.
        store.recordOpen(url: document, text: nil, at: Date(timeIntervalSince1970: 3))

        // The earlier indexed body survives the textless re-open.
        let bodies = try query("SELECT path, body FROM document_text")
        let noteBody = bodies.first { ($0[0] ?? "").hasSuffix("노트.md") }?[1]
        #expect(noteBody == "본문")
        let row = try scalar("SELECT open_count FROM documents WHERE path LIKE '%노트.md'")
        #expect(row == ["2"])
        #expect(store.recentDocuments(limit: 8).map(\.title) == ["노트", "다른"])
    }

    @Test func textlessFirstOpenRecordsDocumentWithoutIndexedBody() throws {
        let document = root.appendingPathComponent("구름.md")
        try "# 구름\n".write(to: document, atomically: true, encoding: .utf8)
        makeStore().recordOpen(url: document, text: nil)
        let row = try scalar("SELECT (SELECT count(*) FROM document_text), open_count FROM documents")
        #expect(row == ["0", "1"])
        #expect(makeStore().recentDocuments(limit: 8).map(\.title) == ["구름"])
    }
}

private enum SQLiteCheck {
    static func __check(_ code: Int32) throws {
        #expect(code == SQLITE_OK)
        if code != SQLITE_OK { throw MemoryStoreTestError() }
    }

    struct MemoryStoreTestError: Error {}
}
