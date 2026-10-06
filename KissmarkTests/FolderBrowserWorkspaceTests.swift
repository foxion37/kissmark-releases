import Foundation
import Testing
@testable import Kissmark

@MainActor
struct FolderBrowserWorkspaceTests {
    @Test("Re-showing a Document exposes queued points without losing local edits or edit mode")
    func reshownDocumentRefreshesAgentReviewPoints() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Review.md")
        try "## 경고\n확인이 필요한 문장입니다.".write(to: document, atomically: true, encoding: .utf8)
        let storeDirectory = root.appendingPathComponent("memory", isDirectory: true)
        let memory = MemoryStore(directory: storeDirectory)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data()),
            memory: memory
        )
        workspace.start()
        defer { workspace.stop() }
        workspace.selectDocument(document)
        #expect(workspace.review?.points.map(\.source) == ["rule"])
        workspace.toggleDocumentMode()
        let session = try #require(workspace.session)
        let editedText = session.text + "\n\n아직 저장하지 않은 변경입니다."
        session.text = editedText

        let entry: [String: Any] = [
            "version": 1,
            "kind": "review_points",
            "path": document.resolvingSymlinksInPath().path,
            "requested_at": 0,
            "agent": "release-check",
            "points": [["quote": "확인이 필요한 문장입니다."]]
        ]
        try JSONSerialization.data(withJSONObject: entry).write(
            to: storeDirectory.appendingPathComponent("queue/agent.json")
        )
        workspace.selectDocument(document, recordsOpen: true)
        #expect(workspace.session === session)
        #expect(workspace.session?.mode == .edit)
        #expect(workspace.session?.text == editedText)
        #expect(try String(contentsOf: document, encoding: .utf8) == "## 경고\n확인이 필요한 문장입니다.")

        let point = try #require(workspace.review?.points.first)
        #expect(point.source == "agent")
        workspace.performReviewAction(.check(id: point.id))
        #expect(memory.reviewPoints(for: document).first?.checkedAt != nil)
    }

    @Test("Workspace owns Folder and Document transitions")
    func folderAndDocumentTransitionsStayLocal() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let document = nested.appendingPathComponent("Status.md")
        try "# Status".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data())
        )
        workspace.start()

        #expect(workspace.rootFolders.map(\.name) == ["Reports"])
        workspace.toggleFolder(nested)
        #expect(workspace.isFolderExpanded(nested))

        workspace.selectDocument(document)
        #expect(workspace.selectedDocumentURL == document)
        #expect(workspace.session?.title == "Status")

        workspace.selectDocument(nested)
        #expect(workspace.selectedDocumentURL == document)
        #expect(workspace.session?.title == "Status")

        workspace.closeDocument()
        #expect(workspace.selectedDocumentURL == nil)
        #expect(workspace.session == nil)
        workspace.stop()
    }

    @Test("Workspace creates a Document and opens it in Edit Mode")
    func createDocumentOpensEditableSession() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data())
        )
        workspace.start()

        #expect(workspace.createDocument(named: "Draft"))
        #expect(workspace.selectedDocumentURL?.lastPathComponent == "Draft.md")
        #expect(workspace.session?.mode == .edit)
        #expect(workspace.rootDocuments.map(\.name) == ["Draft"])
        workspace.stop()
    }

    @Test("Workspace keeps selection and tree aligned after a Document rename")
    func renameKeepsSelectionAndTreeAligned() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let document = root.appendingPathComponent("Original.md")
        try "# Original".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data())
        )
        workspace.start()
        workspace.selectDocument(document)

        let renamedURL = try #require(workspace.renameDocument(to: "Renamed"))

        #expect(renamedURL.lastPathComponent == "Renamed.md")
        #expect(workspace.selectedDocumentURL == renamedURL)
        #expect(workspace.session?.sourceURL == renamedURL)
        #expect(workspace.rootDocuments.map(\.name) == ["Renamed"])
        #expect(!FileManager.default.fileExists(atPath: document.path))
        workspace.stop()
    }

    @Test("Workspace flushes edits when closing a Document")
    func closeFlushesDocumentEdits() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let document = root.appendingPathComponent("Draft.md")
        try "# Draft".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data())
        )
        workspace.start()
        workspace.selectDocument(document)
        workspace.toggleDocumentMode()
        workspace.session?.text = "# Updated"

        workspace.closeDocument()

        #expect(try String(contentsOf: document, encoding: .utf8) == "# Updated")
        #expect(workspace.selectedDocumentURL == nil)
        #expect(workspace.session == nil)
        workspace.stop()
    }

    @Test("Workspace opens an initial Markdown file")
    func opensInitialDocument() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Opened.md")
        try "# Opened".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data()),
            initialDocumentURL: document
        )
        workspace.start()

        #expect(workspace.selectedDocumentURL == document)
        #expect(workspace.session?.title == "Opened")
        workspace.stop()
    }

    @Test("Reload is allowed for a saved Document and refused with a notice while edits are unsaved")
    func prepareReloadProtectsUnsavedEdits() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Report.md")
        try "# Disk".write(to: document, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        workspace.selectDocument(document)
        #expect(workspace.prepareReload())

        workspace.toggleDocumentMode()
        workspace.session?.text = "# Unsaved"

        #expect(!workspace.prepareReload())
        #expect(workspace.session?.text == "# Unsaved")
        #expect(try String(contentsOf: document, encoding: .utf8) == "# Disk")
        #expect(workspace.notice != nil)
        workspace.stop()
    }

    @Test("commitTitle renames the file, syncs titleDraft, and registers undo")
    func commitTitleRenamesAndUndoes() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Draft.md")
        try "# Draft".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        workspace.selectDocument(document)
        #expect(workspace.titleDraft == "Draft")

        workspace.titleDraft = "Renamed"
        workspace.commitTitle(undoManager: nil)
        #expect(workspace.titleDraft == "Draft", "Read Mode ignores the draft")

        workspace.toggleDocumentMode(undoManager: nil)
        let undo = UndoManager()
        workspace.titleDraft = "  Renamed  "
        workspace.commitTitle(undoManager: undo)
        #expect(workspace.session?.title == "Renamed")
        #expect(workspace.titleDraft == "Renamed")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Renamed.md").path))
        #expect(undo.canUndo)

        undo.undo()
        #expect(workspace.session?.title == "Draft")
        #expect(workspace.titleDraft == "Draft")
        #expect(workspace.selectedDocumentURL == document)

        workspace.titleDraft = "   "
        workspace.commitTitle(undoManager: nil)
        #expect(workspace.titleDraft == "Draft", "Blank draft reverts")
        workspace.stop()
    }

    @Test("Undo of a rename after switching Documents is a no-op")
    func undoAfterSwitchIsNoOp() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First.md")
        let second = root.appendingPathComponent("Second.md")
        try "# First".write(to: first, atomically: true, encoding: .utf8)
        try "# Second".write(to: second, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        workspace.selectDocument(first)
        workspace.toggleDocumentMode(undoManager: nil)
        let undo = UndoManager()
        workspace.titleDraft = "First-renamed"
        workspace.commitTitle(undoManager: undo)

        workspace.selectDocument(second, undoManager: undo)
        workspace.toggleDocumentMode(undoManager: nil)
        undo.undo()

        #expect(workspace.session?.title == "Second")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("First-renamed.md").path))
        workspace.stop()
    }

    @Test("requestClose asks for confirmation only when the flush fails")
    func requestCloseConfirmsOnlyWhenDirty() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Notes.md")
        try "# Notes".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        workspace.selectDocument(document)
        workspace.toggleDocumentMode(undoManager: nil)
        workspace.session?.text = "# Notes\n\nedited"
        workspace.requestClose(undoManager: nil)
        #expect(workspace.pendingConfirmation == nil)
        #expect(workspace.session == nil)
        #expect(try String(contentsOf: document, encoding: .utf8) == "# Notes\n\nedited")

        workspace.selectDocument(document)
        workspace.toggleDocumentMode(undoManager: nil)
        workspace.session?.text = "# Notes\n\nedited twice"
        // External change → version mismatch → flush fails → still dirty.
        try "# Notes (outside)".write(to: document, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: document.path
        )
        workspace.requestClose(undoManager: nil)
        #expect(workspace.pendingConfirmation == .discardChanges)
        #expect(workspace.session != nil)

        workspace.cancelConfirmation()
        #expect(workspace.pendingConfirmation == nil)
        #expect(workspace.session != nil)

        workspace.requestClose(undoManager: nil)
        workspace.confirmDiscard()
        #expect(workspace.pendingConfirmation == nil)
        #expect(workspace.session == nil)
        #expect(workspace.titleDraft == FolderBrowserWorkspace.noDocumentTitle)
        workspace.stop()
    }

    @Test("archive reports through notice and closes nothing")
    func archiveWithoutDocumentNotices() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()

        workspace.archive(undoManager: nil)
        #expect(workspace.notice == WorkspaceNotice(title: "보관", message: "열린 문서가 없습니다."))
        workspace.dismissNotice()
        #expect(workspace.notice == nil)
        workspace.stop()
    }

    @Test("archive commits the pending title before copying")
    func archiveCommitsTitleBeforeCopy() throws {
        let root = try makeFolder()
        let archive = try makeFolder()
        let suiteName = "KM_WS_\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: archive)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        let document = root.appendingPathComponent("Draft.md")
        try "# Draft".write(to: document, atomically: true, encoding: .utf8)

        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let bookmarks = FolderBookmarks(defaults: defaults)
        bookmarks.save(try SelectedFolder.make(fromPicked: archive), as: .archive)

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data()),
            bookmarks: bookmarks
        )
        workspace.start()
        workspace.selectDocument(document)
        workspace.toggleDocumentMode(undoManager: nil)
        workspace.titleDraft = "Renamed"

        workspace.archive(undoManager: nil)

        let copied = archive.appendingPathComponent("Inbox/Kissmark/Renamed.md")
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Renamed.md").path))
        workspace.stop()
    }

    @Test("Lock, switch, and close mirror the saved Document; a failed flush does not")
    func flushPointsMirror() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md"), b = fixture.root.appendingPathComponent("B.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        try "# B".write(to: b, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.session?.text = "# A\n\nlocked"
        workspace.toggleDocumentMode()                       // Lock → flush → mirror
        #expect(try fixture.text(of: "A.md") == "# A\n\nlocked")

        workspace.toggleDocumentMode()
        workspace.session?.text = "# A\n\nswitched"
        workspace.selectDocument(b)                          // switch → flush A → mirror A
        #expect(try fixture.text(of: "A.md") == "# A\n\nswitched")

        workspace.toggleDocumentMode()
        workspace.session?.text = "# B\n\nclosed"
        workspace.closeDocument()                            // close → flush B → mirror B
        #expect(try fixture.text(of: "B.md") == "# B\n\nclosed")

        workspace.selectDocument(b)
        workspace.toggleDocumentMode()
        workspace.session?.text = "# B\n\nunsaved"
        try "# B (outside)".write(to: b, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: b.path)
        workspace.toggleDocumentMode()                       // flush fails → no mirror of unsaved text
        #expect(try fixture.text(of: "B.md") == "# B\n\nclosed",
                "Review Focus 1: a failed flush must not mirror unsaved text")
    }

    @Test("A late final change after Lock mirrors through the session callback")
    func lateFinalChangeAfterLockRemirrors() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.session?.text = "# A\n\nlocked"
        workspace.toggleDocumentMode()                       // Lock → flush → mirror
        #expect(try fixture.text(of: "A.md") == "# A\n\nlocked")

        // The surface's `final` change arrives in Read Mode, after the Lock flush and its mirror;
        // the session flushes it and fires its own callback — no workspace method is called here.
        workspace.session?.text = "# A\n\nlocked + last"
        #expect(try fixture.text(of: "A.md") == "# A\n\nlocked + last")
    }

    @Test("Opening or switching to a Document does not mirror the Document being opened")
    func openingADocumentDoesNotMirror() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md"), b = fixture.root.appendingPathComponent("B.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        try "# B".write(to: b, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)                          // open only, never edited
        #expect(try fixture.names().isEmpty)

        workspace.selectDocument(b)                          // switch mirrors the outgoing A, never the opened B
        #expect(try fixture.names() == ["A.md"])
    }

    @Test("Rename mirrors the new path and removes the old copy")
    func renameMirrorsNewPathAndRemovesOld() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.toggleDocumentMode()                       // Lock → flush → mirror A
        #expect(FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("A.md").path))

        workspace.toggleDocumentMode()
        workspace.titleDraft = "Renamed"
        workspace.commitTitle(undoManager: nil)

        #expect(FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("Renamed.md").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("A.md").path))
    }

    @Test("A rename while dirty mirrors the new path at the next flush and drops the old copy")
    func renameWhileDirtyCarriesTheOldPathToTheNextFlush() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.toggleDocumentMode()                       // Lock → flush → mirror A
        #expect(FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("A.md").path))

        workspace.toggleDocumentMode()
        workspace.session?.text = "# A\n\nedited"            // dirty, autosave still pending
        workspace.titleDraft = "Renamed"
        workspace.commitTitle(undoManager: nil)              // rename outran the flush → no mirror yet
        #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("Renamed.md").path))
        #expect(FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("A.md").path))

        workspace.toggleDocumentMode()                       // Lock → flush → mirror the new path, drop the old
        #expect(try fixture.text(of: "Renamed.md") == "# A\n\nedited")
        #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("A.md").path))
    }

    @Test("A pending rename path beats a later clean rename's previous path")
    func pendingRenamePathBeatsLaterCleanRename() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.toggleDocumentMode()                       // Lock → mirror A.md
        #expect(try fixture.names() == ["A.md"])

        workspace.toggleDocumentMode()
        workspace.session?.text = "# A\n\nedited"            // dirty
        workspace.renameDocument(to: "B")                    // rename outran the flush → pending A.md
        workspace.session?.flushToDisk()                     // the autosave that lands later, still no mirror
        workspace.renameDocument(to: "C")                    // clean now, and its previous path is B.md

        // The target only ever held A.md, so the pending path is the one that has to go.
        #expect(try fixture.names() == ["C.md"])
        #expect(try fixture.text(of: "C.md") == "# A\n\nedited")
    }

    @Test("A late final change mirrors the session that wrote it, not the one open now")
    func lateFinalChangeMirrorsItsOwnSession() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md"), b = fixture.root.appendingPathComponent("B.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        try "# B".write(to: b, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.session?.text = "# A\n\nlocked"
        workspace.toggleDocumentMode()                       // Lock A
        let sessionA = try #require(workspace.session)
        workspace.selectDocument(b)                          // B is current now

        sessionA.text = "# A\n\nlate"                        // A's late final change, in Read Mode
        #expect(try fixture.text(of: "A.md") == "# A\n\nlate")
        #expect(try fixture.names() == ["A.md"])
    }

    @Test("A rename whose mirror failed keeps the old path until every target succeeds")
    func failedRenameMirrorKeepsOldPath() throws {
        let fixture = try makeMirrorFixture()
        let a = fixture.root.appendingPathComponent("A.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(a)
        workspace.toggleDocumentMode()
        workspace.toggleDocumentMode()                       // Lock → mirror A.md
        let blocker = fixture.target.appendingPathComponent("B.md", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)

        workspace.toggleDocumentMode()
        workspace.titleDraft = "B"
        workspace.commitTitle(undoManager: nil)              // clean rename, but B.md cannot be written
        #expect(FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("A.md").path))

        try FileManager.default.removeItem(at: blocker)
        workspace.toggleDocumentMode()                       // Lock → retry drops the old copy
        #expect(try fixture.names() == ["B.md"])
    }

    @Test("Archive keeps the mirror failure raised by its own title commit")
    func archiveKeepsRenameMirrorNotice() throws {
        let fixture = try makeMirrorFixture()
        let archive = try makeFolder()
        defer { try? FileManager.default.removeItem(at: archive) }
        let bookmarks = FolderBookmarks(defaults: fixture.defaults)
        bookmarks.save(try SelectedFolder.make(fromPicked: archive), as: .archive)
        let draft = fixture.root.appendingPathComponent("Draft.md")
        try "# Draft".write(to: draft, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: fixture.target.appendingPathComponent("Renamed.md", isDirectory: true),
                                                withIntermediateDirectories: true)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: fixture.root, bookmarkData: Data()),
            bookmarks: bookmarks,
            mirror: fixture.mirror
        )
        workspace.start()
        defer {
            workspace.stop()
            fixture.cleanup()
        }

        workspace.selectDocument(draft)
        workspace.toggleDocumentMode()
        workspace.titleDraft = "Renamed"
        workspace.archive(undoManager: nil)                  // commitTitle → rename → mirror fails

        let name = fixture.mirror.targets[0].displayName
        #expect(workspace.notice?.message.contains(name) == true)
    }

    @Test("A mirror failure during stop() is shown by the next workspace")
    func stopFailureReachesNextWorkspace() throws {
        let fixture = try makeMirrorFixture()
        defer { fixture.cleanup() }
        let a = fixture.root.appendingPathComponent("A.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: fixture.target.appendingPathComponent("A.md", isDirectory: true),
                                                withIntermediateDirectories: true)
        let selected = SelectedFolder(url: fixture.root, bookmarkData: Data())
        let first = FolderBrowserWorkspace(folder: selected, mirror: fixture.mirror)
        first.start()
        first.selectDocument(a)
        first.stop()                                         // mirror A fails while going away
        #expect(first.notice == nil)

        let second = FolderBrowserWorkspace(folder: selected, mirror: fixture.mirror)
        second.start()
        defer { second.stop() }
        let name = fixture.mirror.targets[0].displayName
        #expect(second.notice?.message.contains(name) == true)
        #expect(fixture.mirror.undeliveredFailures.isEmpty)
    }

    @Test("A single-file workspace holds only that Document and creates no siblings")
    func singleFileWorkspaceHoldsOneDocument() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Only.md")
        try "# Only".write(to: document, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: document, bookmarkData: Data(), isSingleFile: true)
        )
        workspace.start()

        #expect(workspace.isSingleFileWorkspace)
        #expect(workspace.rootDocuments.map(\.url) == [document])
        #expect(workspace.rootFolders.isEmpty)

        workspace.selectDocument(document)
        #expect(workspace.session?.title == "Only")

        #expect(!workspace.createDocument(named: "Sibling"))
        #expect(
            workspace.errorMessage
                == String(localized: "상위 폴더를 열어야 새 문서를 만들 수 있습니다.")
        )
        workspace.stop()
    }

    @Test("The source toggle lives on the session and a new Document starts rendered")
    func viewModeTogglesOnTheSession() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("A.md")
        let second = root.appendingPathComponent("B.md")
        try "# A".write(to: first, atomically: true, encoding: .utf8)
        try "# B".write(to: second, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        defer { workspace.stop() }

        workspace.selectDocument(first)
        #expect(workspace.session?.viewMode == .render)
        workspace.toggleDocumentViewMode()
        #expect(workspace.session?.viewMode == .source)
        workspace.toggleDocumentViewMode()
        #expect(workspace.session?.viewMode == .render)

        workspace.toggleDocumentViewMode()
        workspace.selectDocument(second)
        #expect(workspace.session?.viewMode == .render, "opening a Document returns to the rendered view")
    }

    @Test("A large Folder lists only its root at start; collapsed Folders are never read")
    func largeFolderListsOnlyTheRoot() async throws {
        let root = try makeFolder()
        let sealed = root.appendingPathComponent("Sealed", isDirectory: true)
        for index in 0..<300 {
            let child = root.appendingPathComponent(String(format: "Folder %03d", index), isDirectory: true)
            try FileManager.default.createDirectory(
                at: child.appendingPathComponent("Inner", isDirectory: true),
                withIntermediateDirectories: true
            )
            try "# Note".write(to: child.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: sealed, withIntermediateDirectories: true)
        try "# Hidden".write(to: sealed.appendingPathComponent("Hidden.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sealed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path)
            try? FileManager.default.removeItem(at: root)
        }

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        defer { workspace.stop() }
        await workspace.folderLoadsSettled()

        #expect(workspace.rootFolders.count == 301)
        #expect(workspace.rootFolders.allSatisfy { $0.children == [] })
        #expect(workspace.errorMessage == nil, "the unreadable Folder is never opened while collapsed")

        let sealedURL = try #require(workspace.rootFolders.first { $0.name == "Sealed" }).url
        workspace.toggleFolder(sealedURL)
        await workspace.folderLoadsSettled()
        #expect(workspace.errorMessage != nil)
        #expect(workspace.rootFolders.first { $0.name == "Sealed" }?.children == [])

        // The failure was not cached: collapse and expand again retries.
        workspace.dismissError()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path)
        workspace.toggleFolder(sealedURL)
        workspace.toggleFolder(sealedURL)
        await workspace.folderLoadsSettled()
        #expect(workspace.errorMessage == nil)
        #expect(workspace.rootFolders.first { $0.name == "Sealed" }?.children?.map(\.name) == ["Hidden"])
    }

    @Test("Expanding lists a Folder once; collapsing hides it; reopening shows the cache at once")
    func expandCollapseReopen() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let reports = root.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: reports.appendingPathComponent("Q1", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Plan".write(to: reports.appendingPathComponent("Q1/Plan.md"), atomically: true, encoding: .utf8)
        try "# Status".write(to: reports.appendingPathComponent("Status.md"), atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        defer { workspace.stop() }
        let reportsURL = try #require(workspace.rootFolders.first).url
        #expect(workspace.rootFolders.first?.children == [])

        workspace.toggleFolder(reportsURL)
        await workspace.folderLoadsSettled()
        let expanded = try #require(workspace.rootFolders.first)
        #expect(expanded.children?.map(\.name) == ["Q1", "Status"])
        #expect(expanded.children?.first?.children == [], "Q1 stays unread until it is expanded")

        workspace.toggleFolder(reportsURL)
        #expect(!workspace.isFolderExpanded(reportsURL))
        #expect(workspace.rootFolders.first?.children == [])

        workspace.toggleFolder(reportsURL)
        #expect(workspace.rootFolders.first?.children?.map(\.name) == ["Q1", "Status"])

        let q1URL = try #require(workspace.rootFolders.first?.children?.first).url
        workspace.toggleFolder(q1URL)
        await workspace.folderLoadsSettled()
        #expect(workspace.rootFolders.first?.children?.first?.children?.map(\.name) == ["Plan"])
    }

    @Test("A Folder load still running at stop() is dropped; the next start() reloads it")
    func loadRunningAtStopIsDropped() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let reports = root.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try "# Status".write(to: reports.appendingPathComponent("Status.md"), atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        let reportsURL = try #require(workspace.rootFolders.first).url

        workspace.toggleFolder(reportsURL)                   // load queued, cannot run before stop()
        workspace.stop()
        await workspace.folderLoadsSettled()                 // the stale load has finished by now
        #expect(workspace.isFolderExpanded(reportsURL))
        #expect(workspace.rootFolders.first?.children == [], "the stale result never reached the cache")
        #expect(workspace.errorMessage == nil)

        workspace.start()
        await workspace.folderLoadsSettled()
        #expect(workspace.rootFolders.first?.children?.map(\.name) == ["Status"])
        workspace.stop()
    }

    @Test("A rename re-lists its Folder at once, even while that Folder is still loading")
    func renameRelistsLoadingFolder() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let reports = root.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let draft = reports.appendingPathComponent("Draft.md")
        try "# Draft".write(to: draft, atomically: true, encoding: .utf8)

        let workspace = FolderBrowserWorkspace(folder: SelectedFolder(url: root, bookmarkData: Data()))
        workspace.start()
        defer { workspace.stop() }
        let reportsURL = try #require(workspace.rootFolders.first).url

        workspace.toggleFolder(reportsURL)                   // background load queued
        workspace.selectDocument(draft)
        workspace.toggleDocumentMode()
        let renamedURL = try #require(workspace.renameDocument(to: "Final"))

        #expect(workspace.rootFolders.first?.children?.map(\.name) == ["Final"], "listed synchronously")
        await workspace.folderLoadsSettled()
        #expect(workspace.rootFolders.first?.children?.map(\.url.lastPathComponent) == [renamedURL.lastPathComponent])
        #expect(workspace.errorMessage == nil)
    }

    @Test("Recents open in place inside the root, through the handoff outside, and report a missing file")
    func openRecentFollowsTapRule() throws {
        let root = try makeFolder()
        let outside = try makeFolder()
        let memoryDirectory = try makeFolder()
        defer { [root, outside, memoryDirectory].forEach { try? FileManager.default.removeItem(at: $0) } }
        let inside = root.appendingPathComponent("안.md")
        let elsewhere = outside.appendingPathComponent("밖.md")
        try "안".write(to: inside, atomically: true, encoding: .utf8)
        try "밖".write(to: elsewhere, atomically: true, encoding: .utf8)
        let memory = MemoryStore(directory: memoryDirectory)
        memory.recordOpen(url: elsewhere, text: "밖", at: Date(timeIntervalSince1970: 1))

        var handedOver: [URL] = []
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data()),
            memory: memory,
            openOutside: { handedOver.append($0) }
        )
        workspace.start()
        #expect(workspace.recentDocuments.map(\.title) == ["밖"])

        workspace.selectDocument(inside)
        #expect(workspace.recentDocuments.map(\.title) == ["안", "밖"])

        workspace.openRecent(workspace.recentDocuments[1])
        #expect(handedOver.map { $0.resolvingSymlinksInPath().path } == [elsewhere.resolvingSymlinksInPath().path])
        #expect(workspace.errorMessage == nil)

        try FileManager.default.removeItem(at: elsewhere)
        workspace.openRecent(workspace.recentDocuments[1])
        #expect(handedOver.count == 1)
        #expect(workspace.errorMessage == String(localized: "파일을 찾을 수 없습니다."))

        workspace.stop()
    }

    @Test("An open whose load fails still takes the top of the recents list")
    func failedOpenRecordsRecent() throws {
        let root = try makeFolder()
        let memoryDirectory = try makeFolder()
        defer { [root, memoryDirectory].forEach { try? FileManager.default.removeItem(at: $0) } }
        // The file exists, but its bytes are not valid UTF-8, so the load throws.
        let unreadable = root.appendingPathComponent("깨진.md")
        try Data([0xFF, 0xFE, 0x00, 0x81]).write(to: unreadable)
        let workspace = FolderBrowserWorkspace(
            folder: SelectedFolder(url: root, bookmarkData: Data()),
            memory: MemoryStore(directory: memoryDirectory)
        )
        workspace.start()
        defer { workspace.stop() }

        workspace.selectDocument(unreadable)

        #expect(workspace.errorMessage != nil)
        #expect(workspace.session == nil)
        #expect(workspace.recentDocuments.map(\.title) == ["깨진"])
    }

    @Test("Recents stay global when the browsed Folder is replaced")
    func recentsSurviveWorkspaceReplacement() throws {
        let rootA = try makeFolder()
        let rootB = try makeFolder()
        let memoryDirectory = try makeFolder()
        defer { [rootA, rootB, memoryDirectory].forEach { try? FileManager.default.removeItem(at: $0) } }
        let documentA = rootA.appendingPathComponent("에이.md")
        try "# A".write(to: documentA, atomically: true, encoding: .utf8)
        let memory = MemoryStore(directory: memoryDirectory)

        let workspaceA = FolderBrowserWorkspace(
            folder: SelectedFolder(url: rootA, bookmarkData: Data()),
            memory: memory
        )
        workspaceA.start()
        workspaceA.selectDocument(documentA)
        workspaceA.stop()

        // The user picks another Folder; a new workspace replaces the old one.
        let workspaceB = FolderBrowserWorkspace(
            folder: SelectedFolder(url: rootB, bookmarkData: Data()),
            memory: memory
        )
        workspaceB.start()
        defer { workspaceB.stop() }
        #expect(workspaceB.recentDocuments.map(\.title) == ["에이"])
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct MirrorFixture {
        let root: URL
        let target: URL
        let suiteName: String
        let defaults: UserDefaults
        let mirror: MirrorCoordinator

        func text(of relativePath: String) throws -> String {
            try String(contentsOf: target.appendingPathComponent(relativePath), encoding: .utf8)
        }

        func names() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: target.path).sorted()
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: target)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// Folder with an isolated defaults suite and one Mirror Target outside it.
    private func makeMirrorFixture() throws -> MirrorFixture {
        let root = try makeFolder()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("KM_WS_Mirror_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let suiteName = "KM_WS_Mirror_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let mirror = MirrorCoordinator(defaults: defaults)
        _ = try mirror.add(fromPicked: target)
        return MirrorFixture(root: root, target: target, suiteName: suiteName, defaults: defaults, mirror: mirror)
    }
}
