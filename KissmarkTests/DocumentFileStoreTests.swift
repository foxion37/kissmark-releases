import Foundation
import Testing
@testable import Kissmark

@MainActor
struct DocumentFileStoreTests {
    @Test("Saving refreshes the file snapshot")
    func saveRefreshesSnapshot() throws {
        let url = try temporaryFile(contents: "# Original")
        let store = DocumentFileStore()
        let loaded = try store.load(from: url)

        let version = try store.save("# Edited", to: url, expecting: loaded.version)
        let refreshed = try store.load(from: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "# Edited")
        #expect(version == refreshed.version)
    }

    @Test("Saving refuses an externally changed document")
    func externalChangeBlocksSave() throws {
        let url = try temporaryFile(contents: "# Original")
        let store = DocumentFileStore()
        let loaded = try store.load(from: url)
        try "# Changed outside Kissmark".write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: DocumentFileStoreError.changedExternally) {
            try store.save("# Editor change", to: url, expecting: loaded.version)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Changed outside Kissmark")
    }

    @Test("Save As adopts the selected copy")
    func saveAsCreatesNewDocument() throws {
        let source = try temporaryFile(contents: "# Source")
        let destination = source.deletingLastPathComponent().appendingPathComponent("Copy.md")
        let snapshot = try DocumentFileStore().saveAs("# Copy", to: destination)

        #expect(snapshot.url == destination)
        #expect(snapshot.text == "# Copy")
    }

    @Test("Rename moves the Document file and keeps its contents")
    func renameMovesDocument() throws {
        let url = try temporaryFile(contents: "# Hello")
        let store = DocumentFileStore()
        let uniqueName = "Renamed-\(UUID().uuidString)"
        let renamed = try store.rename(url, toProposedName: uniqueName)

        #expect(renamed.url.lastPathComponent == "\(uniqueName).md")
        #expect(renamed.text == "# Hello")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: renamed.url.path))
    }

    @Test("Rename refuses a colliding name")
    func renameRejectsCollision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appendingPathComponent("Alpha.md")
        let second = directory.appendingPathComponent("Beta.md")
        try "# A".write(to: first, atomically: true, encoding: .utf8)
        try "# B".write(to: second, atomically: true, encoding: .utf8)

        #expect(throws: DocumentFileStoreError.destinationExists) {
            try DocumentFileStore().rename(first, toProposedName: "Beta")
        }
    }

    @Test("Loading reads the file's creation date next to its modification date")
    func loadReadsCreationDate() throws {
        let url = try temporaryFile(contents: "# Dated")

        let version = try DocumentFileStore().load(from: url).version

        let created = try #require(version.creationDate)
        #expect(abs(created.timeIntervalSinceNow) < 60)
        #expect(abs(version.modificationDate.timeIntervalSinceNow) < 60)
    }

    private func temporaryFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
