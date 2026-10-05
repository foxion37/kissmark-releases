import Foundation
import Testing
@testable import Kissmark

struct SelectedFolderTests {
    @Test("withAccess runs the body and returns its value for a plain URL")
    func withAccessRunsBodyWithoutScope() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = SelectedFolder(url: root, bookmarkData: Data())

        let count = folder.withAccess { url -> Int in
            try? "x".write(to: url.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
            return (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? -1
        }
        #expect(count == 1)
    }

    @Test("make(fromPicked:) produces a bookmark that round-trips through FolderBookmarks")
    func bookmarkRoundTrip() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try makeDefaults()
        let store = FolderBookmarks(defaults: defaults)

        let picked = try SelectedFolder.make(fromPicked: root)
        #expect(!picked.bookmarkData.isEmpty)
        store.save(picked, as: .archive)
        let id = UUID()
        store.save(picked, as: .mirror(id: id))

        #expect(try store.load(.archive)?.url.standardizedFileURL == root.standardizedFileURL)
        #expect(try store.load(.mirror(id: id))?.url.standardizedFileURL == root.standardizedFileURL)
        #expect(try store.load(.main) == nil)

        store.remove(.archive)
        #expect(try store.load(.archive) == nil)
    }

    @Test("An unresolvable bookmark returns nil and is kept")
    func unresolvableBookmarkReturnsNilAndIsKept() throws {
        let defaults = try makeDefaults()
        let store = FolderBookmarks(defaults: defaults)
        let garbage = Data([0x00, 0x01, 0x02])
        defaults.set(garbage, forKey: FolderBookmarkKind.inbox.key)

        #expect(try store.load(.inbox) == nil)
        #expect(defaults.data(forKey: FolderBookmarkKind.inbox.key) == garbage)
    }

    @Test("Archive copy runs inside withAccess on a restored bookmark")
    func archiveCopyThroughWithAccess() throws {
        let source = try makeFolder()
        let archive = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: archive)
        }
        let document = source.appendingPathComponent("note.md")
        try "hello".write(to: document, atomically: true, encoding: .utf8)

        let defaults = try makeDefaults()
        let store = FolderBookmarks(defaults: defaults)
        store.save(try SelectedFolder.make(fromPicked: archive), as: .archive)

        let restored = try #require(try store.load(.archive))
        let copied = try restored.withAccess { try ArchiveStore.copy(document, into: $0) }
        #expect(try String(contentsOf: copied, encoding: .utf8) == "hello")
    }

    @Test("contains covers the granted Folder itself and everything under it")
    func containsCoversTheGrant() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
        let document = drafts.appendingPathComponent("Note.md")
        try "# Note".write(to: document, atomically: true, encoding: .utf8)
        let folder = SelectedFolder(url: root, bookmarkData: Data())

        #expect(folder.contains(root))
        #expect(folder.contains(drafts))
        #expect(folder.contains(document))
        #expect(!folder.contains(root.deletingLastPathComponent()))
        #expect(!folder.contains(root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "2")))
    }

    @Test("rootURL browses the sub-root when one is set, the grant otherwise")
    func rootURLUsesTheBrowseRoot() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("Drafts", isDirectory: true)

        let granted = SelectedFolder(url: root, bookmarkData: Data())
        let inside = SelectedFolder(url: root, bookmarkData: Data(), browseURL: parent)
        let single = SelectedFolder(url: parent, bookmarkData: Data(), isSingleFile: true)

        #expect(granted.rootURL == root)
        #expect(!granted.isSingleFile)
        #expect(inside.rootURL == parent)
        #expect(!inside.isSingleFile)
        #expect(single.rootURL == parent)
        #expect(single.isSingleFile)
    }

    @Test("make(fromPicked:) keeps a single-file marker")
    func makeKeepsTheSingleFileMarker() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Note.md")
        try "# Note".write(to: document, atomically: true, encoding: .utf8)

        let picked = try SelectedFolder.make(fromPicked: document, isSingleFile: true)

        #expect(picked.isSingleFile)
        #expect(picked.url.standardizedFileURL == document.standardizedFileURL)
        #expect(!picked.bookmarkData.isEmpty)
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KM_SF_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "KM_SF_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
