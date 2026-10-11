import Foundation
import SQLite3
import Testing

@testable import Kissmark

@MainActor
struct DocumentSearchTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentSearchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func write(_ text: String, _ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func folder(_ url: URL? = nil, singleFile: Bool = false) -> SelectedFolder {
        SelectedFolder(url: url ?? root, bookmarkData: Data(), isSingleFile: singleFile)
    }

    // MARK: Folder

    @Test("Folder search finds unopened nested Documents by body and title, literally and case-insensitively")
    func folderTitleBodyNested() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("Hello World", "top.md")
        try write("nothing", "a/b/Deep.markdown")
        try write("100% sure_thing", "a/Wild.md")
        try write("nothing", "Needle Title.md")
        try write("needle", "notes.txt")
        try write("needle", ".hidden.md")

        let body = try await FolderDocumentSearch.search(folder: folder(), query: "hello WORLD")
        #expect(body.map(\.title) == ["top"])
        #expect(body[0].snippet.contains("Hello World"))
        #expect(body[0].lastOpenedAt == nil && body[0].bookmark == nil)

        let nested = try await FolderDocumentSearch.search(folder: folder(), query: "deep")
        #expect(nested.map(\.title) == ["Deep"])
        #expect(nested[0].url.path.hasSuffix("a/b/Deep.markdown"))

        let title = try await FolderDocumentSearch.search(folder: folder(), query: "needle")
        #expect(title.map(\.title) == ["Needle Title"])

        // Wildcard characters are literal.
        #expect(try await FolderDocumentSearch.search(folder: folder(), query: "%").map(\.title) == ["Wild"])
        #expect(try await FolderDocumentSearch.search(folder: folder(), query: "e_t").map(\.title) == ["Wild"])
        #expect(try await FolderDocumentSearch.search(folder: folder(), query: "   ").isEmpty)
        #expect(try await FolderDocumentSearch.search(folder: folder(), query: "absent").isEmpty)
    }

    @Test("Folder search treats composed and decomposed Korean as equal in titles and bodies")
    func folderUnicode() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let composed = "한글 문서".precomposedStringWithCanonicalMapping
        try write("본문에 \(composed) 포함", "x/body.md")
        try write("none", "x/\("회의록".decomposedStringWithCanonicalMapping).md")

        let body = try await FolderDocumentSearch.search(folder: folder(), query: "한글 문서".decomposedStringWithCanonicalMapping)
        #expect(body.map(\.title) == ["body"])
        let title = try await FolderDocumentSearch.search(folder: folder(), query: "회의록".precomposedStringWithCanonicalMapping)
        #expect(title.map(\.title) == ["회의록".precomposedStringWithCanonicalMapping])
    }

    @Test("Folder search never follows symlinks out of the root")
    func folderSymlinks() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentSearchOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try "secret needle".write(to: outside.appendingPathComponent("Secret.md"), atomically: true, encoding: .utf8)
        try write("inside needle", "Inside.md")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.md"), withDestinationURL: outside.appendingPathComponent("Secret.md")
        )

        let results = try await FolderDocumentSearch.search(folder: folder(), query: "needle")
        #expect(results.map(\.title) == ["Inside"])
    }

    @Test("A single-file grant searches only that file, never its siblings")
    func folderSingleFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("needle one", "One.md")
        try write("needle two", "Two.md")
        let single = folder(root.appendingPathComponent("One.md"), singleFile: true)

        #expect(try await FolderDocumentSearch.search(folder: single, query: "needle").map(\.title) == ["One"])
        #expect(try await FolderDocumentSearch.search(folder: single, query: "two").isEmpty)
    }

    @Test("Unreadable files surface as an error that still carries the readable hits")
    func folderUnreadableReported() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("needle", "Good.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: root.appendingPathComponent("Bad.md"))

        do {
            _ = try await FolderDocumentSearch.search(folder: folder(), query: "needle")
            Issue.record("expected FolderDocumentSearchError")
        } catch let error as FolderDocumentSearchError {
            #expect(error.results.map(\.title) == ["Good"])
            #expect(error.failures.count == 1 && error.failures[0].hasPrefix("Bad.md"))
        }
    }

    @Test("A cancelled Folder search throws CancellationError")
    func folderCancel() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<50 { try write("needle", "d\(index)/f.md") }
        let selected = folder()
        let task = Task { try await FolderDocumentSearch.search(folder: selected, query: "needle") }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {}
    }

    // MARK: Memory

    private struct Seed {
        var path: String
        var title: String
        var body: String?
        var openedAt: Double
        var project: String? = nil
        var host: String? = nil
        var agent: String? = nil
        var bookmark: [UInt8]? = nil
    }

    /// Fresh store (creates the schema) seeded through a second raw connection, so tests
    /// never touch the real user store.
    private func makeStore(_ seeds: [Seed]) throws -> MemoryStore {
        let directory = root.appendingPathComponent("memory", isDirectory: true)
        let store = MemoryStore(directory: directory)
        try exec(directory, seeds.flatMap { seed -> [String] in
            func q(_ value: String?) -> String { value.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? "NULL" }
            let blob = seed.bookmark.map { "x'" + $0.map { String(format: "%02x", $0) }.joined() + "'" } ?? "NULL"
            var statements = [
                "INSERT INTO documents (path, title, first_opened_at, last_opened_at, open_count, bookmark) VALUES (\(q(seed.path)), \(q(seed.title)), \(seed.openedAt), \(seed.openedAt), 1, \(blob))",
                "INSERT INTO opens (path, opened_at, opener, project, host, agent) VALUES (\(q(seed.path)), \(seed.openedAt), 'agent', \(q(seed.project)), \(q(seed.host)), \(q(seed.agent)))",
            ]
            if let body = seed.body {
                statements.append("INSERT INTO document_text (path, title, body) VALUES (\(q(seed.path)), \(q(seed.title)), \(q(body)))")
            }
            return statements
        })
        return store
    }

    private func exec(_ directory: URL, _ statements: [String]) throws {
        var db: OpaquePointer?
        defer { if let db { sqlite3_close(db) } }
        try #require(sqlite3_open_v2(directory.appendingPathComponent("memory.sqlite").path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        for statement in statements {
            try #require(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
        }
    }

    @Test("Memory search matches Korean, case, quotes and wildcard characters literally")
    func memoryLiteralMatching() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore([
            Seed(path: "/m/korean.md", title: "korean", body: "한글 문서 Hello", openedAt: 10),
            Seed(path: "/m/quote.md", title: "quote", body: "He said \"it's\" fine", openedAt: 20),
            Seed(path: "/m/pct.md", title: "pct", body: "100% done", openedAt: 30),
            Seed(path: "/m/under.md", title: "under", body: "a_b", openedAt: 40),
            Seed(path: "/m/axb.md", title: "axb", body: "axb", openedAt: 50),
            Seed(path: "/m/NoBody.md", title: "Titled Only", body: nil, openedAt: 60),
        ])

        #expect(try store.searchDocuments(query: "한글 문서".decomposedStringWithCanonicalMapping).map(\.path) == ["/m/korean.md"])
        #expect(try store.searchDocuments(query: "hELLO").map(\.path) == ["/m/korean.md"])
        #expect(try store.searchDocuments(query: "\"it's\"").map(\.path) == ["/m/quote.md"])
        #expect(try store.searchDocuments(query: "%").map(\.path) == ["/m/pct.md"])
        #expect(try store.searchDocuments(query: "a_b").map(\.path) == ["/m/under.md"])
        #expect(try store.searchDocuments(query: "titled").map(\.path) == ["/m/NoBody.md"])
        #expect(try store.searchDocuments(query: "").isEmpty)
        #expect(try store.searchDocuments(query: "nope").isEmpty)
        #expect(try store.searchDocuments(query: "it's")[0].snippet.contains("He said"))
    }

    @Test("Memory search orders newest first, deduplicates, keeps bookmarks, and applies exact project/agent filters")
    func memoryFiltersOrderBookmark() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore([
            Seed(path: "/m/old.md", title: "old", body: "needle", openedAt: 1, project: "alpha", agent: "omp"),
            Seed(path: "/m/mid.md", title: "mid", body: "needle", openedAt: 2, project: "alpha", host: "claude-code", agent: "other"),
            Seed(path: "/m/new.md", title: "new", body: "needle", openedAt: 3, project: "alpha-two", agent: "omp", bookmark: [1, 2, 3]),
            Seed(path: "/outside/folder.md", title: "out", body: "needle", openedAt: 4, project: nil, agent: nil, bookmark: [9, 8]),
        ])
        // A duplicate text row must not duplicate the result.
        try exec(root.appendingPathComponent("memory", isDirectory: true), [
            "INSERT INTO document_text (path, title, body) VALUES ('/m/new.md', 'new', 'needle again')",
        ])

        let all = try store.searchDocuments(query: "needle")
        #expect(all.map(\.path) == ["/outside/folder.md", "/m/new.md", "/m/mid.md", "/m/old.md"])
        #expect(all[0].bookmark == Data([9, 8]) && all[1].bookmark == Data([1, 2, 3]) && all[2].bookmark == nil)
        #expect(all[0].lastOpenedAt == Date(timeIntervalSince1970: 4))
        #expect(all[1].project == "alpha-two" && all[1].agent == "omp")
        #expect(all[2].agent == "other")

        // project is exact: "alpha" does not match "alpha-two".
        #expect(try store.searchDocuments(query: "needle", project: "alpha").map(\.path) == ["/m/mid.md", "/m/old.md"])
        // agent matches agent or host.
        #expect(try store.searchDocuments(query: "needle", agent: "omp").map(\.path) == ["/m/new.md", "/m/old.md"])
        #expect(try store.searchDocuments(query: "needle", agent: "claude-code").map(\.path) == ["/m/mid.md"])
        // Combined, and filters are never wildcards.
        #expect(try store.searchDocuments(query: "needle", project: "alpha", agent: "omp").map(\.path) == ["/m/old.md"])
        #expect(try store.searchDocuments(query: "needle", project: "alph%").isEmpty)
        #expect(try store.searchDocuments(query: "needle", agent: "o_p").isEmpty)
    }

    @Test("Unavailable or broken memory throws instead of returning no results")
    func memoryErrors() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // The "directory" is a file, so the database cannot open.
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        #expect(throws: (any Error).self) { try MemoryStore(directory: blocked).searchDocuments(query: "x") }

        let store = try makeStore([])
        try exec(root.appendingPathComponent("memory", isDirectory: true), ["DROP TABLE document_text"])
        #expect(throws: (any Error).self) { try store.searchDocuments(query: "x") }

        let workspace = FolderBrowserWorkspace(folder: folder())
        #expect(throws: (any Error).self) { try workspace.searchMemory(query: "x") }
    }

    @Test("Workspace forwards Memory search to its injected store")
    func workspaceForwardsMemory() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore([Seed(path: "/m/a.md", title: "a", body: "needle", openedAt: 1, project: "p", agent: "g")])
        let workspace = FolderBrowserWorkspace(folder: folder(), memory: store)
        #expect(try workspace.searchMemory(query: "needle", project: "p", agent: "g").map(\.path) == ["/m/a.md"])
        #expect(try workspace.searchMemory(query: "needle", project: "q").isEmpty)
    }
}
