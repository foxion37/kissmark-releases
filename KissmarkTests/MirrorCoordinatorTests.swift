import Foundation
import Testing
@testable import Kissmark

@MainActor
struct MirrorCoordinatorTests {
    private func makeDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KM_Mirror_\(name)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "KM_Mirror_\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("Writes the Document to every target under its Folder-relative path")
    func writesNestedPathToEveryTarget() throws {
        let folder = try makeDir("folder"), a = try makeDir("a"), b = try makeDir("b")
        let (defaults, suite) = try makeDefaults()
        defer { [folder, a, b].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        let doc = folder.appendingPathComponent("Reports/Status.md")
        try FileManager.default.createDirectory(at: doc.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# S".write(to: doc, atomically: true, encoding: .utf8)

        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: a)
        _ = try mirror.add(fromPicked: b)
        let failed = mirror.mirror(.init(documentURL: doc, text: "# S", previousDocumentURL: nil),
                                   from: SelectedFolder(url: folder, bookmarkData: Data()))

        #expect(failed.isEmpty)
        for target in [a, b] {
            #expect(try String(contentsOf: target.appendingPathComponent("Reports/Status.md"), encoding: .utf8) == "# S")
        }
        #expect(mirror.lastResults.values.allSatisfy { if case .ok = $0 { true } else { false } })
    }

    @Test("Targets persist across instances; remove deletes bookmark and result")
    func removeDeletesBookmark() throws {
        let a = try makeDir("a")
        let (defaults, suite) = try makeDefaults()
        defer { try? FileManager.default.removeItem(at: a); defaults.removePersistentDomain(forName: suite) }
        let first = MirrorCoordinator(defaults: defaults)
        let target = try first.add(fromPicked: a)
        #expect(MirrorCoordinator(defaults: defaults).targets == [target])
        #expect(defaults.data(forKey: FolderBookmarkKind.mirror(id: target.id).key) != nil)

        first.remove(target.id)
        #expect(MirrorCoordinator(defaults: defaults).targets.isEmpty)
        #expect(defaults.data(forKey: FolderBookmarkKind.mirror(id: target.id).key) == nil)
        #expect(first.lastResults[target.id] == nil)
        #expect(try first.add(fromPicked: a).id != target.id)
    }

    @Test("Rename writes the new path and removes the old copy")
    func renameThenUndoLeavesOneCopy() throws {
        let folder = try makeDir("folder"), a = try makeDir("a")
        let (defaults, suite) = try makeDefaults()
        defer { [folder, a].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: a)
        let selected = SelectedFolder(url: folder, bookmarkData: Data())
        let draft = folder.appendingPathComponent("Draft.md"), renamed = folder.appendingPathComponent("Final.md")

        mirror.mirror(.init(documentURL: draft, text: "x", previousDocumentURL: nil), from: selected)
        mirror.mirror(.init(documentURL: renamed, text: "x", previousDocumentURL: draft), from: selected)
        #expect(!FileManager.default.fileExists(atPath: a.appendingPathComponent("Draft.md").path))
        #expect(FileManager.default.fileExists(atPath: a.appendingPathComponent("Final.md").path))

        mirror.mirror(.init(documentURL: draft, text: "x", previousDocumentURL: renamed), from: selected)
        let names = try FileManager.default.contentsOfDirectory(atPath: a.path)
        #expect(names == ["Draft.md"])
    }

    @Test("A failing target does not block others and notices once")
    func failingTargetNoticesOnce() throws {
        let folder = try makeDir("folder"), good = try makeDir("good"), bad = try makeDir("bad")
        let (defaults, suite) = try makeDefaults()
        defer { [folder, good, bad].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: good)
        let badTarget = try mirror.add(fromPicked: bad)
        // Make "Notes" a file inside the bad target so "Notes/A.md" cannot be written.
        try "blocker".write(to: bad.appendingPathComponent("Notes"), atomically: true, encoding: .utf8)
        let selected = SelectedFolder(url: folder, bookmarkData: Data())
        let doc = folder.appendingPathComponent("Notes/A.md")

        let first = mirror.mirror(.init(documentURL: doc, text: "1", previousDocumentURL: nil), from: selected)
        let second = mirror.mirror(.init(documentURL: doc, text: "2", previousDocumentURL: nil), from: selected)

        #expect(first.map(\.id) == [badTarget.id])
        #expect(second.isEmpty)
        #expect(try String(contentsOf: good.appendingPathComponent("Notes/A.md"), encoding: .utf8) == "2")
        if case .failed = mirror.lastResults[badTarget.id] {} else { Issue.record("bad target should be failed") }
    }

    @Test("relativePath normalizes a leading /private on both sides, and only for var/tmp/etc")
    func relativePathNormalizesPrivatePrefix() {
        let cases: [(folder: String, url: String, expected: String?)] = [
            ("/private/var/tmp/X", "/private/var/tmp/X/Missing.md", "Missing.md"),
            ("/var/tmp/X", "/private/var/tmp/X/a/b.md", "a/b.md"),
            ("/private/var/tmp/X", "/var/tmp/X/c.md", "c.md"),
            ("/private/Users/X", "/Users/X/d.md", nil),
            ("/var/tmp/X", "/var/tmp/X/../Y/e.md", nil),
        ]
        for c in cases {
            #expect(
                MirrorCoordinator.relativePath(of: URL(fileURLWithPath: c.url), in: URL(fileURLWithPath: c.folder)) == c.expected,
                "\(c.folder) + \(c.url)"
            )
        }
    }

    @Test("relativePath compares the raw paths, so a renamed-away previous path still resolves")
    func relativePathIgnoresStandardization() throws {
        // A real directory under the platform's temp root — the macOS test host cannot write
        // `/private/var/tmp` — addressed through its `/private` twin so both root forms exist
        // on disk and the raw-path comparison is exercised on both platforms.
        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("KM_Mirror_Private_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }

        let realPath = real.path
        let prefixedPath: String
        if realPath.hasPrefix("/private/") {
            prefixedPath = realPath
        } else if realPath.hasPrefix("/var/") || realPath.hasPrefix("/tmp/") {
            prefixedPath = "/private" + realPath
        } else {
            prefixedPath = realPath
        }
        let root = URL(fileURLWithPath: prefixedPath)
        let rawRoot = URL(fileURLWithPath: realPath)
        let present = root.appendingPathComponent("Present.md")
        try "x".write(to: present, atomically: true, encoding: .utf8)

        #expect(MirrorCoordinator.relativePath(of: root.appendingPathComponent("Missing.md"), in: root) == "Missing.md")
        #expect(MirrorCoordinator.relativePath(of: present, in: root) == "Present.md")
        // The Folder's form and the Document's form can differ (bookmark vs enumerator).
        #expect(MirrorCoordinator.relativePath(of: root.appendingPathComponent("Missing.md"), in: rawRoot) == "Missing.md")
    }

    @Test("mirrorAll does not walk into a target that lives inside the Folder")
    func mirrorAllSkipsInsideTargetContents() throws {
        let folder = try makeDir("folder"), outside = try makeDir("outside")
        let inside = folder.appendingPathComponent("Mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let (defaults, suite) = try makeDefaults()
        defer { [folder, outside].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        try "# stale".write(to: inside.appendingPathComponent("Stale.md"), atomically: true, encoding: .utf8)
        let directoryNamedMD = folder.appendingPathComponent("Dir.md", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryNamedMD, withIntermediateDirectories: true)
        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: inside)
        _ = try mirror.add(fromPicked: outside)

        mirror.mirrorAll(from: SelectedFolder(url: folder, bookmarkData: Data()))

        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("Mirror/Stale.md").path))
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("Dir.md").path))
        #expect(FileManager.default.fileExists(atPath: inside.appendingPathComponent("Stale.md").path))
    }

    @Test("A target inside the Folder is skipped, and paths never escape")
    func targetInsideFolderIsSkipped() throws {
        let folder = try makeDir("folder"), outside = try makeDir("outside")
        let inside = folder.appendingPathComponent("Mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let (defaults, suite) = try makeDefaults()
        defer { [folder, outside].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        let mirror = MirrorCoordinator(defaults: defaults)
        let insideTarget = try mirror.add(fromPicked: inside)
        _ = try mirror.add(fromPicked: outside)
        let selected = SelectedFolder(url: folder, bookmarkData: Data())

        try "# A".write(to: folder.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        mirror.mirrorAll(from: selected)
        #expect(!FileManager.default.fileExists(atPath: inside.appendingPathComponent("A.md").path))
        #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("A.md").path))
        if case .failed = mirror.lastResults[insideTarget.id] {} else { Issue.record("inside target should be failed") }

        let escaping = folder.deletingLastPathComponent().appendingPathComponent("Escape.md")
        mirror.mirror(.init(documentURL: escaping, text: "x", previousDocumentURL: nil), from: selected)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("Escape.md").path))
        #expect(!FileManager.default.fileExists(atPath: outside.deletingLastPathComponent().appendingPathComponent("Escape.md").path))
    }

    @Test("A target that contains the Folder is refused and the source is untouched")
    func ancestorTargetIsRefused() throws {
        let base = try makeDir("base")
        let folder = base.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (defaults, suite) = try makeDefaults()
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
        // Document `Notes/A.md` under the target `base` lands on `base/Notes/A.md` — the Folder's own `A.md`.
        let victim = folder.appendingPathComponent("A.md")
        try "source".write(to: victim, atomically: true, encoding: .utf8)
        let mirror = MirrorCoordinator(defaults: defaults)
        let target = try mirror.add(fromPicked: base)

        let failed = mirror.mirror(.init(documentURL: folder.appendingPathComponent("Notes/A.md"), text: "overwritten",
                                         previousDocumentURL: nil),
                                   from: SelectedFolder(url: folder, bookmarkData: Data()))

        #expect(failed.map(\.id) == [target.id])
        #expect(try String(contentsOf: victim, encoding: .utf8) == "source")
        #expect(mirror.lastResults[target.id]?.isFailure == true)
    }

    @Test("A directory symlink inside a target never carries a write or delete into the Folder")
    func symlinkedSubdirectoryIntoFolderFails() throws {
        let folder = try makeDir("folder"), a = try makeDir("a")
        let (defaults, suite) = try makeDefaults()
        defer { [folder, a].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        let inner = folder.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "keep".write(to: inner.appendingPathComponent("Old.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: a.appendingPathComponent("Link"), withDestinationURL: inner)
        let mirror = MirrorCoordinator(defaults: defaults)
        let target = try mirror.add(fromPicked: a)
        let selected = SelectedFolder(url: folder, bookmarkData: Data())

        let failed = mirror.mirror(.init(documentURL: folder.appendingPathComponent("Link/A.md"), text: "x", previousDocumentURL: nil), from: selected)
        #expect(failed.map(\.id) == [target.id])
        #expect(!FileManager.default.fileExists(atPath: inner.appendingPathComponent("A.md").path))

        mirror.mirror(.init(documentURL: folder.appendingPathComponent("Top.md"), text: "x",
                            previousDocumentURL: folder.appendingPathComponent("Link/Old.md")), from: selected)
        #expect(try String(contentsOf: inner.appendingPathComponent("Old.md"), encoding: .utf8) == "keep")
        if case .failed = mirror.lastResults[target.id] {} else { Issue.record("target should be failed") }
    }

    @Test("A rename never deletes an old copy that is a symlink")
    func oldCopySymlinkIsNotDeleted() throws {
        let folder = try makeDir("folder"), a = try makeDir("a"), elsewhere = try makeDir("elsewhere")
        let (defaults, suite) = try makeDefaults()
        defer { [folder, a, elsewhere].forEach { try? FileManager.default.removeItem(at: $0) }; defaults.removePersistentDomain(forName: suite) }
        let outside = elsewhere.appendingPathComponent("Outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        let link = a.appendingPathComponent("Old.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: a)

        mirror.mirror(.init(documentURL: folder.appendingPathComponent("New.md"), text: "x",
                            previousDocumentURL: folder.appendingPathComponent("Old.md")),
                      from: SelectedFolder(url: folder, bookmarkData: Data()))

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == outside.path)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
        #expect(FileManager.default.fileExists(atPath: a.appendingPathComponent("New.md").path))
    }

    @Test("mirrorAll reports Documents it could not read", .enabled(if: getuid() != 0))
    func mirrorAllReportsUnreadable() throws {
        let folder = try makeDir("folder"), a = try makeDir("a")
        let (defaults, suite) = try makeDefaults()
        let locked = folder.appendingPathComponent("Locked.md")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
            [folder, a].forEach { try? FileManager.default.removeItem(at: $0) }
            defaults.removePersistentDomain(forName: suite)
        }
        try "ok".write(to: folder.appendingPathComponent("Open.md"), atomically: true, encoding: .utf8)
        try "secret".write(to: locked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: a)

        let summary = mirror.mirrorAll(from: SelectedFolder(url: folder, bookmarkData: Data()))

        #expect(summary.unreadable == ["Locked.md"])
        #expect(summary.newlyFailed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: a.appendingPathComponent("Open.md").path))
    }
}
