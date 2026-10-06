import Foundation
import Testing
@testable import Kissmark

@MainActor
struct KissmarkDocumentToolbarItemsTests {
    @Test("경로 복사 sits between 보관 and 설정 and follows document availability")
    func copyPathSlotAndAvailability() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KM_Toolbar_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("노트.md")
        try "# 노트".write(to: document, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        defer { workspace.stop() }

        let withoutDocument = KissmarkDocumentToolbarItems.items(
            for: workspace, undoManager: nil, newDocument: {}, settings: {}
        )
        #expect(withoutDocument.first { $0.id == "kissmark.document.copyPath" }?.disabled == true)

        workspace.selectDocument(document)
        let withDocument = KissmarkDocumentToolbarItems.items(
            for: workspace, undoManager: nil, newDocument: {}, settings: {}
        )
        let ids = withDocument.map(\.id)
        let copyIndex = try #require(ids.firstIndex(of: "kissmark.document.copyPath"))
        #expect(ids[copyIndex - 1] == "kissmark.document.archive")
        #expect(ids[copyIndex + 1] == "kissmark.settings")
        #expect(withDocument.first { $0.id == "kissmark.document.copyPath" }?.disabled == false)
    }
}
