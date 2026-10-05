import Foundation
import Testing
@testable import Kissmark

struct ArchiveStoreTests {
    @Test("Archive copies without replacing an existing Document")
    func copyUsesSuffix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Report.md")
        try "# Report".write(to: source, atomically: true, encoding: .utf8)
        let first = try ArchiveStore.copy(source, into: root)
        let second = try ArchiveStore.copy(source, into: root)
        #expect(first.lastPathComponent == "Report.md")
        #expect(second.lastPathComponent == "Report (1).md")
    }
}
