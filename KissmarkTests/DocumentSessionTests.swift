import Foundation
import Testing
@testable import Kissmark

@MainActor
struct DocumentSessionTests {
    @Test("Existing documents begin locked and become dirty after editing")
    func existingDocumentState() {
        let session = DocumentSession(snapshot: snapshot(text: "# Original"))

        #expect(session.mode == .read)
        #expect(!session.isDirty)
        session.setMode(.edit)
        session.text = "# Edited"
        #expect(session.isDirty)
    }

    @Test("Discard returns to the last saved text")
    func discardChanges() {
        let session = DocumentSession(snapshot: snapshot(text: "# Original"))
        session.setMode(.edit)
        session.text = "# Edited"

        session.discardChanges()

        #expect(session.text == "# Original")
        #expect(!session.isDirty)
    }

    @Test("A new document begins unlocked")
    func newDocumentState() {
        let session = DocumentSession(newDocumentNamed: "Draft", text: "# Draft")

        #expect(session.mode == .edit)
        #expect(session.isDirty)
    }

    @Test("Rename updates the Document title and source URL")
    func renameUpdatesTitleAndURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try "# Title".write(to: url, atomically: true, encoding: .utf8)
        let store = DocumentFileStore()
        let session = DocumentSession(snapshot: try store.load(from: url))
        let uniqueName = "Fresh-\(UUID().uuidString)"

        #expect(session.rename(to: uniqueName, using: store))
        #expect(session.title == uniqueName)
        #expect(session.sourceURL?.lastPathComponent == "\(uniqueName).md")
        #expect(session.renameError == nil)
    }

    @Test("Flush on lock persists edits without an explicit Save")
    func lockFlushesEdits() throws {
        let fixture = try #require(Bundle.main.url(forResource: "agent-output", withExtension: "md"))
        let original = try String(contentsOf: fixture, encoding: .utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try original.write(to: url, atomically: true, encoding: .utf8)

        let store = DocumentFileStore()
        let session = DocumentSession(snapshot: try store.load(from: url))
        session.setMode(.edit, using: store)
        let edited = original + "\n\n## Roundtrip\nEdited in WYSIWYG path.\n"
        session.text = edited
        #expect(session.isDirty)

        session.setMode(.read, using: store)
        #expect(session.saveError == nil)
        #expect(!session.isDirty)
        #expect(session.mode == .read)

        let reread = try store.load(from: url)
        #expect(reread.text == edited)
        #expect(reread.text.contains("Roundtrip"))
    }

    @Test("Close flushes pending edits")
    func closeFlushesEdits() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try "# A".write(to: url, atomically: true, encoding: .utf8)
        let store = DocumentFileStore()
        let session = DocumentSession(snapshot: try store.load(from: url))
        session.setMode(.edit, using: store)
        session.text = "# B"

        #expect(session.requestClose(using: store) == .close)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# B")
    }

    @Test("Text that changes while locked is written to disk immediately")
    func lockedTextChangeFlushes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KM_Final_\(UUID().uuidString).md")
        try "# A".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = DocumentSession(snapshot: try DocumentFileStore().load(from: url))
        session.setMode(.edit)
        session.text = "# A\n\nfirst"
        session.setMode(.read)
        session.text = "# A\n\nfirst second"
        #expect(try String(contentsOf: url, encoding: .utf8) == "# A\n\nfirst second")
        #expect(!session.isDirty)
    }

    @Test("The locked-write callback fires only after a change that reached the disk")
    func lockedWriteCallbackFiresOnlyAfterAFlush() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KM_Final_\(UUID().uuidString).md")
        try "# A".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = DocumentSession(snapshot: try DocumentFileStore().load(from: url))
        var writes = 0
        session.onLockedWrite = { writes += 1 }

        session.setMode(.edit)
        session.text = "# A\n\nfirst"
        #expect(writes == 0)                                 // Edit Mode: the autosave owns the write

        session.setMode(.read)
        session.text = "# A\n\nfirst second"                 // Read Mode: flushed, then the callback
        #expect(writes == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# A\n\nfirst second")

        // An outside change makes the next locked flush fail, so nothing was written to mirror.
        try "# A (outside)".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path
        )
        session.text = "# A\n\nlost"
        #expect(session.isDirty)
        #expect(writes == 1)
    }

    @Test("Lock and unlock without edits never writes the file")
    func lockWithoutEditsDoesNotWrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KM_Final_\(UUID().uuidString).md")
        try "# A".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let session = DocumentSession(snapshot: try DocumentFileStore().load(from: url))
        session.setMode(.edit)
        session.setMode(.read)
        session.setMode(.edit)
        session.setMode(.read)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(before == after)
        #expect(!session.isDirty)
    }

    private func snapshot(text: String) -> DocumentFileSnapshot {
        DocumentFileSnapshot(
            url: URL(fileURLWithPath: "/tmp/Reader.md"),
            text: text,
            version: DocumentFileVersion(modificationDate: .distantPast, fileSize: 0)
        )
    }
}
