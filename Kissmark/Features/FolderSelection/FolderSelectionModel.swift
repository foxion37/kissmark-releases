import Foundation
import Observation
import UniformTypeIdentifiers

enum FolderPickerContentTypes {
    static var types: [UTType] {
        var types: [UTType] = [.folder]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let long = UTType(filenameExtension: "markdown"), !types.contains(long) {
            types.append(long)
        }
        return types
    }
}

nonisolated enum FolderImportOutcome: Equatable {
    case selected(url: URL)
    case cancelled
    case failed

    static func map(_ result: Result<[URL], any Error>) -> Self {
        switch result {
        case .success(let urls) where urls.count == 1:
            return .selected(url: urls[0])
        case .success, .failure:
            return .failed
        }
    }

    static func folderURL(from url: URL) -> URL {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            || url.hasDirectoryPath
        return isDirectory ? url : url.deletingLastPathComponent()
    }

    static func documentURL(from url: URL) -> URL? {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            || url.hasDirectoryPath
        return isDirectory ? nil : url
    }
}

nonisolated struct FolderSelectionError: Equatable {
    let title: String
    let message: String

    static let grantMissesDocument = FolderSelectionError(
        title: String.kissmarkLocalized("현재 문서가 이 폴더에 없습니다"),
        message: String.kissmarkLocalized("현재 문서가 들어 있는 폴더를 고르세요. 다른 폴더를 탐색하려면 폴더 메뉴에서 ‘다른 폴더 열기’를 선택하세요.")
    )

    static let pickerFailure = FolderSelectionError(
        title: String.kissmarkLocalized("폴더를 선택하지 못했습니다"),
        message: String.kissmarkLocalized("다시 시도해 주세요.")
    )

    static let documentFailure = FolderSelectionError(
        title: String.kissmarkLocalized("문서를 열지 못했습니다"),
        message: String.kissmarkLocalized("파일 권한을 가져오지 못했습니다. 다시 시도해 주세요.")
    )
}

/// A picked Markdown Document whose parent Folder has no grant yet. The view shows a
/// folder-only picker pre-set to the parent on macOS, once per pick; the answer comes
/// back through `FolderSelectionModel.handleGrant`. Each request carries a fresh id so
/// a repeated ask for the same Document is a real change again and the presenter can
/// re-show the panel after one that never surfaced.
nonisolated enum FolderGrantRequest: Equatable {
    case parent(parent: URL, document: URL, id: UUID)

    /// Directory the picker opens at.
    var directory: URL {
        switch self {
        case .parent(let parent, _, _): parent
        }
    }

    /// The Document that stays open whichever way the prompt resolves.
    var document: URL {
        switch self {
        case .parent(_, let document, _): document
        }
    }
}

@Observable
final class FolderSelectionModel {
    private(set) var selectedFolder: SelectedFolder?
    private(set) var pendingDocumentURL: URL?
    /// Set when a picked Document needs its parent Folder granted; the view presents the
    /// picker and reports back through `handleGrant`.
    private(set) var pendingGrant: FolderGrantRequest?
    private(set) var error: FolderSelectionError?
    /// Bumped by ⌘R. Part of the Folder browser's identity, so the whole window is
    /// rebuilt: scope re-acquired, tree, Document surface, review and 최근 read fresh.
    private(set) var reloadGeneration = 0

    private let bookmarks: FolderBookmarks

    init(
        selectedFolder: SelectedFolder? = nil,
        bookmarks: FolderBookmarks = FolderBookmarks()
    ) {
        self.selectedFolder = selectedFolder
        self.bookmarks = bookmarks
    }

    func handle(_ outcome: FolderImportOutcome) {
        switch outcome {
        case .selected(let url):
            if FolderImportOutcome.documentURL(from: url) != nil {
                openPickedDocument(url)
            } else {
                openPickedFolder(FolderImportOutcome.folderURL(from: url), persist: true)
            }
        case .cancelled:
            break
        case .failed:
            error = .pickerFailure
        }
    }

    /// Applies the answer to `pendingGrant`. Granting replaces the single-file workspace
    /// with the granted Folder and keeps the picked Document open; cancelling leaves the
    /// single-file workspace in place.
    func handleGrant(_ outcome: FolderImportOutcome) {
        guard let request = pendingGrant else { return }
        pendingGrant = nil
        switch outcome {
        case .selected(let url):
            let granted = FolderImportOutcome.folderURL(from: url)
            // The panel can wander off; a Folder that does not hold the Document
            // would leave it without any scope, so keep the single-file workspace.
            guard SelectedFolder(url: granted, bookmarkData: Data()).contains(request.document) else {
                error = .grantMissesDocument
                return
            }
            openPickedFolder(granted, persist: true)
            guard selectedFolder != nil else { return }
            // The Document opens on its own scope or inside the granted Folder.
            pendingDocumentURL = request.document
        case .cancelled:
            break
        case .failed:
            error = .pickerFailure
        }
    }

    /// Sidebar menu "현재 문서의 폴더 열기…": re-asks for the single file's parent grant.
    func requestParentGrant() {
        guard let folder = selectedFolder, folder.isSingleFile else { return }
        let document = folder.url
        pendingGrant = .parent(parent: document.deletingLastPathComponent(), document: document, id: UUID())
    }

    func cancelPendingGrant() {
        pendingGrant = nil
    }

    func dismissError() {
        error = nil
    }

    func consumePendingDocument() -> URL? {
        let url = pendingDocumentURL
        pendingDocumentURL = nil
        return url
    }

    /// ⌘R: rebuilds the Folder browser and reopens `document` (the open one, if any).
    func requestReload(reopening document: URL?) {
        pendingDocumentURL = document
        reloadGeneration += 1
    }

    /// A Document or Folder handed over by another process through LaunchServices
    /// (Finder, Dock, `open`, kissmark-mcp). A Folder becomes the browsed Folder. A
    /// Document opens like a pick but never prompts for the parent Folder: the sender
    /// asked to show a file, not to change the browsed Folder. The sidebar's
    /// 현재 문서의 폴더 열기… menu action still offers the grant.
    func openExternal(_ url: URL) {
        if FolderImportOutcome.documentURL(from: url) == nil {
            openPickedFolder(url, persist: true)
        } else {
            openPickedDocument(url, requestsParentGrant: false)
        }
    }

    func restoreSavedFolder() {
        if let folder = try? bookmarks.load(.main) {
            selectedFolder = folder
            return
        }
        openCloudFolderIfAvailable()
    }

    @discardableResult
    func openCloudFolderIfAvailable(_ cloud: KissmarkCloudFolder = .live) -> Bool {
        guard selectedFolder == nil else { return false }
        do {
            let url = try cloud.prepareDocuments()
            handle(.selected(url: url))
            return selectedFolder != nil
        } catch {
            return false
        }
    }

    private func openPickedFolder(_ url: URL, persist: Bool) {
        do {
            let folder = try SelectedFolder.make(fromPicked: url)
            selectedFolder = folder
            pendingDocumentURL = nil
            pendingGrant = nil
            error = nil
            if persist {
                bookmarks.save(folder, as: .main)
            }
        } catch {
            self.error = .pickerFailure
        }
    }

    /// A picked Document opens immediately. Inside a held Folder's scope the tree roots at
    /// the Document's parent; otherwise the Document becomes a single-file workspace and
    /// its parent Folder is requested once.
    private func openPickedDocument(_ document: URL, requestsParentGrant: Bool = true) {
        let parent = document.deletingLastPathComponent()
        if let holder = heldFolder(containing: parent) {
            selectedFolder = SelectedFolder(
                url: holder.url,
                bookmarkData: holder.bookmarkData,
                browseURL: parent
            )
            pendingDocumentURL = document
            pendingGrant = nil
            error = nil
            return
        }
        do {
            selectedFolder = try SelectedFolder.make(fromPicked: document, isSingleFile: true)
            pendingDocumentURL = document
            pendingGrant = requestsParentGrant
                ? .parent(parent: parent, document: document, id: UUID())
                : nil
            error = nil
        } catch {
            self.error = .documentFailure
        }
    }

    /// First held bookmark whose scope covers `url`: current Folder, Inbox, then Archive.
    private func heldFolder(containing url: URL) -> SelectedFolder? {
        for kind in [FolderBookmarkKind.main, .inbox, .archive] {
            guard let folder = try? bookmarks.load(kind), folder.contains(url) else { continue }
            return folder
        }
        return nil
    }
}
