import Foundation
import Testing
@testable import Kissmark

@MainActor
struct DocumentSearchModelTests {
    /// Lets a test hold a Folder search open and release it after a newer search finished.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func open() { continuation?.resume(); continuation = nil }
    }

    private func settle(_ model: DocumentSearchModel) async {
        for _ in 0..<200 where model.phase == .loading { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("A slow older Folder search never overwrites a newer query")
    func staleFolderResultIsDropped() async {
        let gate = Gate()
        let model = DocumentSearchModel(
            debounce: .zero,
            folderSearch: { query in
                if query == "old" { await gate.wait() }
                return [DocumentSearchResult(path: "/\(query).md", title: query, snippet: "", lastOpenedAt: nil, bookmark: nil, project: nil, agent: nil)]
            },
            memorySearch: { _, _, _ in [] }
        )
        model.query = "old"
        model.inputChanged(immediately: true)
        await Task.yield()
        model.query = "new"
        model.inputChanged(immediately: true)
        await settle(model)
        await gate.open()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.results.map(\.title) == ["new"])
        #expect(model.selection == "/new.md")
    }

    @Test("Scope change drops the other scope's results and Memory passes exact filters")
    func scopeChangeReplacesResults() async {
        var received: [String] = []
        let model = DocumentSearchModel(
            debounce: .zero,
            folderSearch: { _ in [DocumentSearchResult(path: "/folder.md", title: "folder", snippet: "", lastOpenedAt: nil, bookmark: nil, project: nil, agent: nil)] },
            memorySearch: { query, project, agent in
                received = [query, project, agent]
                return [DocumentSearchResult(path: "/memory.md", title: "memory", snippet: "", lastOpenedAt: nil, bookmark: nil, project: nil, agent: nil)]
            }
        )
        model.query = "q"
        model.inputChanged(immediately: true)
        await settle(model)
        #expect(model.results.map(\.title) == ["folder"])

        model.scope = .memory
        model.project = " proj "
        model.agent = "a%"
        model.inputChanged(immediately: true)
        #expect(model.results.isEmpty)
        await settle(model)
        #expect(model.results.map(\.title) == ["memory"])
        #expect(received == ["q", "proj", "a%"])
    }

    @Test("Failures are distinct from empty results; blank query is idle; Return opens only a finished search")
    func failureBlankAndSubmit() async {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        let model = DocumentSearchModel(
            debounce: .zero,
            folderSearch: { _ in throw Boom() },
            memorySearch: { _, _, _ in [] }
        )
        model.query = "  "
        model.inputChanged(immediately: true)
        #expect(model.phase == .idle)

        model.query = "x"
        #expect(model.submit() == nil)
        await settle(model)
        #expect(model.phase == .failed("boom"))
        #expect(model.results.isEmpty)
    }

    @Test("Arrow selection stays inside the results")
    func selectionClamps() async {
        let model = DocumentSearchModel(
            debounce: .zero,
            folderSearch: { _ in [DocumentSearchResult(path: "/a", title: "a", snippet: "", lastOpenedAt: nil, bookmark: nil, project: nil, agent: nil), DocumentSearchResult(path: "/b", title: "b", snippet: "", lastOpenedAt: nil, bookmark: nil, project: nil, agent: nil)] },
            memorySearch: { _, _, _ in [] }
        )
        model.query = "x"
        model.inputChanged(immediately: true)
        await settle(model)
        model.moveSelection(by: -1)
        #expect(model.selection == "/a")
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        #expect(model.selection == "/b")
        #expect(model.submit()?.id == "/b")
    }

    @Test("Unreadable files do not hide readable Folder matches or prevent opening them")
    func partialFolderFailureKeepsReadableMatches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("search-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("good.md"), atomically: true, encoding: .utf8)
        try Data([0xFF]).write(to: root.appendingPathComponent("bad.md"))
        let folder = SelectedFolder(url: root, bookmarkData: Data())
        let model = DocumentSearchModel(
            debounce: .zero,
            folderSearch: { try await FolderDocumentSearch.search(folder: folder, query: $0) },
            memorySearch: { _, _, _ in [] }
        )
        model.query = "needle"
        model.inputChanged(immediately: true)
        await settle(model)
        #expect(model.results.map(\.title) == ["good"])
        if case .failed = model.phase {} else { Issue.record("Partial failure must remain visible") }
        #expect(model.submit()?.url.resolvingSymlinksInPath() == root.appendingPathComponent("good.md").resolvingSymlinksInPath())
    }
}
