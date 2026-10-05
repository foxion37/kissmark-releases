import Foundation
import Testing
@testable import Kissmark

struct FolderSelectionModelTests {
    @Test("A fresh model starts with no Folder")
    func initialStateIsNone() {
        let model = FolderSelectionModel()

        #expect(model.selectedFolder == nil)
        #expect(model.error == nil)
    }

    @Test("Selecting a Folder moves from none to its display name")
    func selectingFromNone() throws {
        let model = FolderSelectionModel(bookmarks: try emptyBookmarks())

        let url = try! temporaryFolder(named: "KM_Selected_A")
        model.handle(.selected(url: url))

        #expect(model.selectedFolder?.displayName == url.lastPathComponent)
        #expect(model.error == nil)
    }

    @Test("Cancelling from none preserves none")
    func cancellingFromNone() {
        let model = FolderSelectionModel()

        model.handle(.cancelled)

        #expect(model.selectedFolder == nil)
        #expect(model.error == nil)
    }

    @Test("Cancelling after selection preserves the selected Folder")
    func cancellingAfterSelection() throws {
        let url = try temporaryFolder(named: "KM_Selected_A")
        let model = FolderSelectionModel(
            selectedFolder: SelectedFolder(url: url, bookmarkData: Data())
        )

        model.handle(.cancelled)

        #expect(model.selectedFolder?.displayName == url.lastPathComponent)
        #expect(model.error == nil)
    }

    @Test("Selecting a second Folder replaces the first display name")
    func replacingSelection() throws {
        let model = FolderSelectionModel(
            selectedFolder: SelectedFolder(url: try temporaryFolder(named: "KM_Selected_A"), bookmarkData: Data()),
            bookmarks: try emptyBookmarks()
        )

        let url = try temporaryFolder(named: "KM_Selected_B")
        model.handle(.selected(url: url))

        #expect(model.selectedFolder?.displayName == url.lastPathComponent)
        #expect(model.error == nil)
    }

    @Test("A new model does not restore a previous selection")
    func relaunchStartsFromNone() throws {
        let url = try temporaryFolder(named: "KM_Selected_A")
        let previousModel = FolderSelectionModel(
            selectedFolder: SelectedFolder(url: url, bookmarkData: Data())
        )
        let relaunchedModel = FolderSelectionModel()

        #expect(previousModel.selectedFolder?.displayName == url.lastPathComponent)
        #expect(relaunchedModel.selectedFolder == nil)
    }

    @Test(
        "A picker failure preserves the current Folder until the error is dismissed",
        arguments: [
            nil,
            SelectedFolder(url: URL(fileURLWithPath: "/tmp/KM_Selected_A"), bookmarkData: Data()),
        ]
    )
    func failurePreservesState(state: SelectedFolder?) {
        let model = FolderSelectionModel(selectedFolder: state)

        model.handle(.failed)

        #expect(model.selectedFolder == state)
        #expect(model.error == .pickerFailure)

        model.dismissError()
        #expect(model.error == nil)
        #expect(model.selectedFolder == state)
    }

    @Test("One native URL maps only to its display name")
    func oneURLMapsToSelection() {
        let url = URL(fileURLWithPath: "/tmp/KM_Selected_A")

        let outcome = FolderImportOutcome.map(.success([url]))

        #expect(outcome == .selected(url: url))
    }

    @Test("Empty and multiple native results map to failure")
    func invalidURLCountsMapToFailure() {
        let firstURL = URL(fileURLWithPath: "/tmp/KM_Selected_A")
        let secondURL = URL(fileURLWithPath: "/tmp/KM_Selected_B")

        #expect(FolderImportOutcome.map(.success([])) == .failed)
        #expect(FolderImportOutcome.map(.success([firstURL, secondURL])) == .failed)
    }

    @Test("A picked Markdown file with no held Folder opens alone and asks for its parent")
    func pickingALoneMarkdownFileRequestsItsParent() throws {
        let folder = try temporaryFolder(named: "KM_File_Parent")
        let document = folder.appendingPathComponent("Note.md")
        try "# Note\n".write(to: document, atomically: true, encoding: .utf8)
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)

        model.handle(.selected(url: document))

        let picked = try #require(model.selectedFolder)
        #expect(picked.isSingleFile)
        #expect(picked.url.standardizedFileURL == document.standardizedFileURL)
        #expect(picked.rootURL.standardizedFileURL == document.standardizedFileURL)
        #expect(model.pendingGrant?.directory.standardizedFileURL == folder.standardizedFileURL)
        #expect(model.pendingGrant?.document.lastPathComponent == "Note.md")
        #expect(try bookmarks.load(.main) == nil, "a single file is never saved as the main Folder")
        #expect(model.pendingDocumentURL?.lastPathComponent == "Note.md")
        #expect(model.consumePendingDocument()?.lastPathComponent == "Note.md")
        #expect(model.pendingDocumentURL == nil)
    }

    @Test("An externally opened Markdown file shows alone without the parent prompt")
    func externalOpenSkipsTheParentPrompt() throws {
        let folder = try temporaryFolder(named: "KM_External")
        let document = folder.appendingPathComponent("Report.md")
        try "# Report\n".write(to: document, atomically: true, encoding: .utf8)
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)

        model.openExternal(document)

        #expect(model.selectedFolder?.isSingleFile == true)
        #expect(model.pendingGrant == nil, "an agent opening a file never pops a folder panel")
        #expect(model.pendingDocumentURL?.lastPathComponent == "Report.md")
        #expect(try bookmarks.load(.main) == nil)

        model.requestParentGrant()
        #expect(model.pendingGrant?.directory.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test("An externally opened Folder becomes the saved browsed Folder")
    func externalOpenOfAFolderBrowsesIt() throws {
        let folder = try temporaryFolder(named: "KM_External_Folder")
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)

        model.openExternal(folder)

        let opened = try #require(model.selectedFolder)
        #expect(!opened.isSingleFile)
        #expect(opened.rootURL.standardizedFileURL == folder.standardizedFileURL)
        #expect(model.pendingGrant == nil)
        #expect(try bookmarks.load(.main)?.url.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test("An app reload rebuilds the window and reopens the same Document")
    func reloadRebuildsAndKeepsTheDocument() throws {
        let folder = try temporaryFolder(named: "KM_Reload")
        let document = folder.appendingPathComponent("Report.md")
        let model = FolderSelectionModel(selectedFolder: SelectedFolder(url: folder, bookmarkData: Data()))
        let before = model.reloadGeneration

        model.requestReload(reopening: document)

        #expect(model.reloadGeneration == before + 1)
        #expect(model.pendingDocumentURL == document)
        #expect(model.selectedFolder?.url == folder)
    }

    @Test("A picked Markdown file inside a held Folder browses its parent without a prompt")
    func pickingAFileInsideAHeldFolderBrowsesTheParent() throws {
        let root = try temporaryFolder(named: "KM_Held_Root")
        let parent = root.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let document = parent.appendingPathComponent("Note.md")
        try "# Note\n".write(to: document, atomically: true, encoding: .utf8)

        let bookmarks = try emptyBookmarks()
        let held = try SelectedFolder.make(fromPicked: root)
        bookmarks.save(held, as: .inbox)
        let model = FolderSelectionModel(bookmarks: bookmarks)

        model.handle(.selected(url: document))

        let picked = try #require(model.selectedFolder)
        #expect(!picked.isSingleFile)
        #expect(picked.contains(root))
        #expect(picked.rootURL.standardizedFileURL == parent.standardizedFileURL)
        #expect(model.pendingGrant == nil, "a held scope needs no prompt")
        #expect(model.pendingDocumentURL?.lastPathComponent == "Note.md")
    }

    @Test("Granting the parent Folder replaces the single-file workspace and keeps the Document")
    func grantingTheParentFolderKeepsTheDocumentOpen() throws {
        let folder = try temporaryFolder(named: "KM_Granted")
        let document = folder.appendingPathComponent("Note.md")
        try "# Note\n".write(to: document, atomically: true, encoding: .utf8)
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)
        model.handle(.selected(url: document))
        _ = model.consumePendingDocument()

        model.handleGrant(.selected(url: folder))

        #expect(model.pendingGrant == nil)
        let picked = try #require(model.selectedFolder)
        #expect(!picked.isSingleFile)
        #expect(picked.rootURL.standardizedFileURL == folder.standardizedFileURL)
        #expect(model.pendingDocumentURL?.lastPathComponent == "Note.md")
        #expect(try bookmarks.load(.main).map { $0.contains(folder) } == true)
    }

    @Test("A granted Folder that does not hold the Document keeps the single file and says why")
    func grantingAnUnrelatedFolderKeepsTheSingleFile() throws {
        let folder = try temporaryFolder(named: "KM_Grant_Home")
        let elsewhere = try temporaryFolder(named: "KM_Grant_Elsewhere")
        let document = folder.appendingPathComponent("Note.md")
        try "# Note\n".write(to: document, atomically: true, encoding: .utf8)
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)
        model.handle(.selected(url: document))

        model.handleGrant(.selected(url: elsewhere))

        #expect(model.selectedFolder?.isSingleFile == true)
        #expect(model.error == .grantMissesDocument)
        #expect(try bookmarks.load(.main) == nil)
    }

    @Test("Cancelling the parent prompt keeps the single file open")
    func cancellingTheParentPromptKeepsTheSingleFile() throws {
        let folder = try temporaryFolder(named: "KM_Cancelled")
        let document = folder.appendingPathComponent("Note.md")
        try "# Note\n".write(to: document, atomically: true, encoding: .utf8)
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)
        model.handle(.selected(url: document))

        model.handleGrant(.cancelled)

        #expect(model.pendingGrant == nil)
        #expect(model.selectedFolder?.isSingleFile == true)
        #expect(try bookmarks.load(.main) == nil)
    }

    @Test("The Document's Folder action asks for the same parent again")
    func singleFileActionAsksAgain() throws {
        let folder = try temporaryFolder(named: "KM_Ask_Again")
        let document = folder.appendingPathComponent("Note.md")
        try "# Note\n".write(to: document, atomically: true, encoding: .utf8)
        let model = FolderSelectionModel(bookmarks: try emptyBookmarks())
        model.handle(.selected(url: document))
        model.handleGrant(.cancelled)
        #expect(model.pendingGrant == nil)

        model.requestParentGrant()

        #expect(model.pendingGrant?.directory.standardizedFileURL == folder.standardizedFileURL)
        #expect(model.pendingGrant?.document.standardizedFileURL == document.standardizedFileURL)
    }

    @Test("Choosing a Folder saves it as the main Folder")
    func choosingAFolderSavesMain() throws {
        let bookmarks = try emptyBookmarks()
        let model = FolderSelectionModel(bookmarks: bookmarks)
        let url = try temporaryFolder(named: "KM_Main_Pick")

        model.handle(.selected(url: url))

        #expect(model.selectedFolder?.rootURL.standardizedFileURL == url.standardizedFileURL)
        #expect(model.pendingGrant == nil)
        #expect(try bookmarks.load(.main).map { $0.contains(url) } == true)
    }

    @Test("A native importer error maps to failure")
    func importerErrorMapsToFailure() {
        let outcome = FolderImportOutcome.map(
            .failure(TestImporterError.accessDenied)
        )

        #expect(outcome == .failed)
    }
}

/// Throwaway bookmark store. Tests run inside the app's container, so the default
/// `FolderBookmarks()` would overwrite the user's saved Folder.
func emptyBookmarks() throws -> FolderBookmarks {
    let name = "KM_Selection_\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return FolderBookmarks(defaults: defaults)
}

private func temporaryFolder(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private enum TestImporterError: Error {
    case accessDenied
}
