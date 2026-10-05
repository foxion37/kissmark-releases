import Foundation
import Testing
@testable import Kissmark

struct UbiquitousFileAccessTests {
    @Test("Given a local file When preparing Then reading continues")
    func localFileNeedsNoDownload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).md")
        try "# Local".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        try UbiquitousFileAccess.prepareForReading(url)
        let snapshot = try DocumentFileStore().load(from: url)
        #expect(snapshot.text == "# Local")
    }
}

struct FolderBrowserICloudPlaceholderTests {
    @Test("Given an iCloud placeholder When listing Then the Markdown name is shown")
    func icloudPlaceholderMapsToDocument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("Status.md.icloud"))

        let items = try FolderBrowserStore().contents(of: root, within: root)

        #expect(items.map(\.name) == ["Status.md"])
        #expect(items.first?.kind == .document)
    }
}
