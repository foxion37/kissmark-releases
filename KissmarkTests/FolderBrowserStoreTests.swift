import Foundation
import Testing
@testable import Kissmark

@MainActor
struct FolderBrowserStoreTests {
    @Test("Folders precede supported Markdown Documents")
    func contentsAreFilteredAndSorted() throws {
        let root = try makeFolder()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Alpha"), withIntermediateDirectories: true)
        try "# Z".write(to: root.appendingPathComponent("Z.md"), atomically: true, encoding: .utf8)
        try "# A".write(to: root.appendingPathComponent("a.MARKDOWN"), atomically: true, encoding: .utf8)
        try "ignore".write(to: root.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: root.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)

        let items = try FolderBrowserStore().contents(of: root, within: root)

        #expect(items.map(\.name) == ["Alpha", "a.MARKDOWN", "Z.md"])
    }

    @Test("Sidebar children list one Folder: Folders unread, Markdown leaves")
    func childrenListDirectEntriesOnly() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "# Root".write(to: root.appendingPathComponent("root.md"), atomically: true, encoding: .utf8)
        try "# Nested".write(to: nested.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)

        let children = try FolderBrowserStore().children(of: root, within: root)
        #expect(children.map(\.name) == ["Notes", "root"])
        let notes = try #require(children.first { $0.kind == .folder })
        #expect(notes.children == [], "a child Folder is not listed with its parent")
        #expect(children.first { $0.kind == .document }?.children == nil)
        #expect(try FolderBrowserStore().children(of: notes.url, within: root).map(\.name) == ["nested"])
    }

    @Test("Listing a Folder never opens its child Folders")
    func childrenDoNotReadGrandchildren() throws {
        let root = try makeFolder()
        let sealed = root.appendingPathComponent("Sealed", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sealed.appendingPathComponent("Inner", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sealed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path)
            try? FileManager.default.removeItem(at: root)
        }

        #expect(throws: (any Error).self, "the fixture really is unreadable") {
            try FolderBrowserStore().children(of: sealed, within: root)
        }
        #expect(try FolderBrowserStore().children(of: root, within: root).map(\.name) == ["Sealed"])
    }

    @Test("New Documents remain inside the selected Folder")
    func createsMarkdownDocumentInsideRoot() throws {
        let root = try makeFolder()
        let snapshot = try FolderBrowserStore().createDocument(named: "Draft", in: root, within: root)

        #expect(snapshot.url.lastPathComponent == "Draft.md")
        #expect(snapshot.text.isEmpty)
        #expect(throws: FolderBrowserError.invalidDocumentName) {
            try FolderBrowserStore().createDocument(named: "../outside", in: root, within: root)
        }
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
