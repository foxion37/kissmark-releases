import Foundation
import Observation

enum WorkspaceConfirmation: Equatable {
    case discardChanges
}

struct WorkspaceNotice: Equatable {
    let title: String
    let message: String
}

@MainActor
@Observable
final class FolderBrowserWorkspace {
    static let noDocumentTitle = String.kissmarkLocalized("문서 없음")

    let folder: SelectedFolder

    private(set) var selectedDocumentURL: URL?
    private(set) var session: DocumentSession?
    private(set) var expandedFolderURLs: Set<URL> = []
    private(set) var errorMessage: String?
    /// Filename field text. Owned here so every action can commit it first.
    var titleDraft = FolderBrowserWorkspace.noDocumentTitle
    private(set) var pendingConfirmation: WorkspaceConfirmation?
    private(set) var notice: WorkspaceNotice?
    /// 검토 card payload for the open Document; `nil` without memory or a Document.
    private(set) var review: DocumentReview?

    /// Direct children of every Folder listed so far, keyed by Folder URL. The root is listed
    /// by `start()`; any other Folder is listed the first time it is expanded.
    private var childrenByFolder: [URL: [FolderTreeNode]] = [:]
    /// The background load each Folder waits on. A load whose id is gone from here is stale.
    @ObservationIgnored private var currentLoadIDs: [URL: Int] = [:]
    /// Every load still running, stale ones included, so `folderLoadsSettled()` can await them.
    @ObservationIgnored private var loadTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextLoadID = 0

    private var access: FolderAccess?
    private var hasStarted = false
    /// Old Folder-relative path of a Document renamed while dirty; consumed by the next flush's mirror.
    private var pendingMirrorPreviousURL: URL?
    private let initialDocumentURL: URL?
    private let bookmarks: FolderBookmarks
    private let mirror: MirrorCoordinator?
    private let memory: MemoryStore?
    private let openOutside: (URL) -> Void

    init(
        folder: SelectedFolder,
        initialDocumentURL: URL? = nil,
        bookmarks: FolderBookmarks? = nil,
        mirror: MirrorCoordinator? = nil,
        memory: MemoryStore? = nil,
        openOutside: @escaping (URL) -> Void = { _ in }
    ) {
        self.folder = folder
        self.initialDocumentURL = initialDocumentURL
        self.bookmarks = bookmarks ?? FolderBookmarks()
        self.mirror = mirror
        self.memory = memory
        self.openOutside = openOutside
    }

    /// Up to 8 most recently opened Documents, newest first; refreshed after every recorded open.
    private(set) var recentDocuments: [RecentDocument] = []

    /// Root Folders; an expanded Folder carries its listed children, a collapsed one `[]`.
    var rootFolders: [FolderTreeNode] {
        rootNodes.filter { $0.kind == .folder }.map(attachingListedChildren)
    }

    var rootDocuments: [FolderTreeNode] {
        rootNodes.filter { $0.kind == .document }
    }

    private var rootNodes: [FolderTreeNode] {
        childrenByFolder[folder.rootURL] ?? []
    }

    /// Fills in cached children of expanded Folders. Walks memory only, never the disk.
    private func attachingListedChildren(_ node: FolderTreeNode) -> FolderTreeNode {
        guard expandedFolderURLs.contains(node.url), let children = childrenByFolder[node.url] else { return node }
        var node = node
        node.children = children.map(attachingListedChildren)
        return node
    }

    /// Folder control label: the browsed Folder (the picked Document's parent in a
    /// single-file workspace).
    var folderDisplayName: String {
        folder.rootURL.lastPathComponent
    }

    /// The grant covers one Document only (its parent Folder is not granted).
    var isSingleFileWorkspace: Bool { folder.isSingleFile }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        access = folder.acquire()
        loadTree()
        refreshRecents()
        if let failed = mirror?.takeUndeliveredFailures(), !failed.isEmpty {
            reportMirrorFailures(failed)
        }
        if let initialDocumentURL {
            selectDocument(initialDocumentURL)
        }
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        // Loads still running finish after the grant is released; their results are dropped.
        currentLoadIDs.removeAll()
        session?.flushToDisk()
        // This workspace is going away; the next one's `start()` shows what failed here.
        mirror?.deferFailures(mirror(session: session))
        access?.release()
        access = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func toggleFolder(_ url: URL) {
        if expandedFolderURLs.contains(url) {
            expandedFolderURLs.remove(url)
        } else {
            expandedFolderURLs.insert(url)
            loadChildren(of: url)
        }
    }

    func isFolderExpanded(_ url: URL) -> Bool {
        expandedFolderURLs.contains(url)
    }

    /// The contract tap rule: inside the browsed root opens in place; anywhere else
    /// resolves the stored bookmark and hands the file to the app model.
    func openRecent(_ recent: RecentDocument, undoManager: UndoManager? = nil) {
        let url = URL(fileURLWithPath: recent.path)
        let root = folder.rootURL.resolvingSymlinksInPath().path
        if recent.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") {
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = String.kissmarkLocalized("파일을 찾을 수 없습니다.")
                return
            }
            selectDocument(url, undoManager: undoManager)
            return
        }
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let data = recent.bookmark,
              let resolved = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
        else {
            errorMessage = String.kissmarkLocalized("파일을 찾을 수 없습니다.")
            return
        }
        // The opened selection re-acquires its own grant; this one only covers the handoff.
        let didStart = resolved.startAccessingSecurityScopedResource()
        defer { if didStart { resolved.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            errorMessage = String.kissmarkLocalized("파일을 찾을 수 없습니다.")
            return
        }
        openOutside(resolved)
    }

    private func refreshRecents() {
        recentDocuments = memory?.recentDocuments(limit: 8) ?? []
    }

    func selectDocument(_ url: URL, undoManager: UndoManager? = nil, recordsOpen: Bool = false) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return
        }
        commitTitle(undoManager: undoManager)
        guard session?.sourceURL != url else {
            selectedDocumentURL = url
            // External request for the already-open Document still records an
            // open; a tree click on the selected Document does not.
            if recordsOpen, let session {
                memory?.recordOpen(url: url, text: session.text)
                refreshRecents()
                refreshReview()
            }
            return
        }

        session?.flushToDisk()
        reportMirrorFailures(mirror(session: session))
        pendingMirrorPreviousURL = nil
        do {
            let openedSession = try DocumentSession(
                snapshot: DocumentFileStore().load(from: url)
            )
            installLockedWriteMirror(on: openedSession)
            session = openedSession
            selectedDocumentURL = url
            memory?.recordOpen(url: url, text: openedSession.text)
            refreshRecents()
        } catch UbiquitousFileAccessError.downloadInProgress {
            session = nil
            selectedDocumentURL = nil
            errorMessage = String.kissmarkLocalized("iCloud에서 문서를 내려받는 중입니다.")
        } catch {
            session = nil
            selectedDocumentURL = nil
            errorMessage = String.kissmarkLocalized("이 문서를 열 수 없습니다.")
        }
        syncTitleDraft()
        refreshReview()
    }

    /// ⌘R gate: the window is about to be rebuilt from disk. Unsaved edits win: a dirty
    /// Document refuses, because re-reading would drop them and saving first would
    /// overwrite changes an agent made on disk.
    func prepareReload(undoManager: UndoManager? = nil) -> Bool {
        commitTitle(undoManager: undoManager)
        guard let session, session.isDirty else { return true }
        notice = WorkspaceNotice(
            title: String.kissmarkLocalized("새로고침"),
            message: String.kissmarkLocalized("저장되지 않은 변경이 있어 새로고침하지 않았습니다.")
        )
        return false
    }

    func createDocument(named name: String, undoManager: UndoManager? = nil) -> Bool {
        commitTitle(undoManager: undoManager)
        guard !folder.isSingleFile else {
            errorMessage = String.kissmarkLocalized("상위 폴더를 열어야 새 문서를 만들 수 있습니다.")
            return false
        }
        session?.flushToDisk()
        reportMirrorFailures(mirror(session: session))
        pendingMirrorPreviousURL = nil
        do {
            let snapshot = try FolderBrowserStore().createDocument(
                named: name,
                in: folder.rootURL,
                within: folder.rootURL
            )
            let newSession = DocumentSession(snapshot: snapshot)
            installLockedWriteMirror(on: newSession)
            newSession.setMode(.edit)
            refreshChildren(of: folder.rootURL)
            session = newSession
            selectedDocumentURL = snapshot.url
            syncTitleDraft()
            refreshReview()
            return true
        } catch {
            errorMessage = String.kissmarkLocalized("새 문서 이름을 다시 확인하세요.")
            return false
        }
    }

    func toggleDocumentMode(undoManager: UndoManager? = nil) {
        commitTitle(undoManager: undoManager)
        guard let session else { return }
        session.setMode(session.mode == .read ? .edit : .read)
        syncTitleDraft()
        if session.mode == .read {
            reportMirrorFailures(mirror(session: session))
        }
    }

    /// 코드 보기 / 렌더 보기. Read/Edit alone decides editability; this only picks the
    /// surface, and a newly opened Document always starts rendered.
    func toggleDocumentViewMode(undoManager: UndoManager? = nil) {
        commitTitle(undoManager: undoManager)
        guard let session else { return }
        session.viewMode = session.viewMode == .render ? .source : .render
    }

    /// The surface's `final` change arrives after Lock returned, so the Lock-time mirror can miss it.
    /// The session calls back once the Read-Mode write reached the disk; the existing `isDirty`
    /// guard then keeps a failed save out of the target.
    private func installLockedWriteMirror(on session: DocumentSession) {
        // Bound to this session: by the time a late final change lands, `self.session` may be another Document.
        session.onLockedWrite = { [weak self, weak session] in
            guard let self, let session else { return }
            self.reportMirrorFailures(self.mirror(session: session))
        }
    }

    func requestClose(undoManager: UndoManager? = nil) {
        commitTitle(undoManager: undoManager)
        guard let session else { return }
        switch session.requestClose() {
        case .close:
            closeDocument()
        case .confirmDiscard:
            pendingConfirmation = .discardChanges
        }
    }

    func confirmDiscard() {
        pendingConfirmation = nil
        session?.discardChanges()
        session = nil
        selectedDocumentURL = nil
        pendingMirrorPreviousURL = nil
        syncTitleDraft()
        refreshReview()
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
    }

    func closeDocument() {
        session?.flushToDisk()
        reportMirrorFailures(mirror(session: session))
        session = nil
        selectedDocumentURL = nil
        pendingMirrorPreviousURL = nil
        syncTitleDraft()
        refreshReview()
    }

    /// Commits the filename field. Read Mode and blank drafts revert to the current title.
    func commitTitle(undoManager: UndoManager? = nil) {
        guard let session else {
            titleDraft = Self.noDocumentTitle
            return
        }
        guard session.mode == .edit else {
            titleDraft = session.title
            return
        }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.title else {
            titleDraft = session.title
            return
        }

        let previousTitle = session.title
        guard let renamedURL = renameDocument(to: trimmed) else {
            titleDraft = session.title
            return
        }
        titleDraft = session.title

        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                guard target.session?.sourceURL == renamedURL else { return }
                _ = target.renameDocument(to: previousTitle)
                target.syncTitleDraft()
            }
        }
        undoManager?.setActionName(String.kissmarkLocalized("이름 바꾸기"))
    }

    func archive(undoManager: UndoManager? = nil) {
        let noticeBefore = notice
        commitTitle(undoManager: undoManager)
        // A mirror failure from the rename just committed must survive the Archive notice.
        let renameNotice = notice != noticeBefore ? notice?.message : nil
        let message = [archiveMessage(), renameNotice].compactMap { $0 }.joined(separator: "\n")
        notice = WorkspaceNotice(title: String.kissmarkLocalized("보관"), message: message)
        reportMirrorFailures(mirror(session: session))
    }

    func dismissNotice() {
        notice = nil
    }

    private func archiveMessage() -> String {
        guard let session else { return String.kissmarkLocalized("열린 문서가 없습니다.") }
        session.flushToDisk()
        guard let source = session.sourceURL else {
            return String.kissmarkLocalized("이 문서는 아직 디스크에 없습니다.")
        }

        do {
            guard let archiveFolder = try bookmarks.load(.archive) else {
                return String.kissmarkLocalized("설정에서 보관 폴더를 먼저 고르세요.")
            }
            _ = try archiveFolder.withAccess { try ArchiveStore.copy(source, into: $0) }
            return String.kissmarkLocalized("Obsidian 보관 폴더로 복사했습니다.")
        } catch {
            return String.kissmarkLocalized("문서를 보관하지 못했습니다.")
        }
    }

    private func syncTitleDraft() {
        titleDraft = session?.title ?? Self.noDocumentTitle
    }

    // MARK: Review

    func performReviewAction(_ action: ReviewAction) {
        guard let memory, let url = session?.sourceURL else { return }
        switch action {
        case .check(let id): memory.checkPoint(id: id, comment: nil)
        case .uncheck(let id): memory.uncheckPoint(id: id)
        case .comment(let id, let comment):
            // Commenting only exists on a checked point; keep it checked.
            let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            memory.checkPoint(id: id, comment: text.isEmpty ? nil : text)
        case .complete:
            if let session { memory.completeReview(url: url, text: session.text) }
        }
        refreshReview()
    }

    private func refreshReview() {
        guard let memory, let url = session?.sourceURL else {
            review = nil
            return
        }
        review = DocumentReview(
            points: memory.reviewPoints(for: url).map(DocumentReview.Point.init),
            completedLabel: memory.reviewCompletion(for: url).map { DocumentEditorScreen.dateText($0) },
            expanded: true
        )
    }

    @discardableResult
    func renameDocument(to title: String) -> URL? {
        guard let session else { return nil }
        let previousURL = session.sourceURL
        guard session.rename(to: title) else { return nil }
        guard let newURL = session.sourceURL else { return nil }

        if newURL != previousURL {
            selectedDocumentURL = newURL
            refreshChildren(of: newURL.deletingLastPathComponent())
            if session.isDirty {
                // The rename outran the flush; the next successful mirror still has to drop the old copy.
                pendingMirrorPreviousURL = pendingMirrorPreviousURL ?? previousURL
            } else {
                reportMirrorFailures(mirror(session: session, previousURL: previousURL))
            }
        }
        return newURL
    }

    /// Mirrors `session` if its last flush succeeded; returns the newly failing targets.
    /// The pending rename path belongs to the current session only.
    private func mirror(session: DocumentSession?, previousURL: URL? = nil) -> [MirrorTarget] {
        guard let mirror, let session, !session.isDirty, let url = session.sourceURL else { return [] }
        let isCurrent = session === self.session
        // A rename that outran its flush (or a failed batch) still owns the copy the target holds.
        let previous = (isCurrent ? pendingMirrorPreviousURL : nil) ?? previousURL
        let failed = mirror.mirror(
            MirrorJob(documentURL: url, text: session.text, previousDocumentURL: previous),
            from: folder
        )
        if isCurrent {
            // Keep the old path until every target has dropped its copy.
            pendingMirrorPreviousURL = mirror.allTargetsOK ? nil : previous
        }
        return failed
    }

    /// Newly failing targets become one notice line.
    private func reportMirrorFailures(_ failed: [MirrorTarget]) {
        guard !failed.isEmpty else { return }
        let names = failed.map(\.displayName).joined(separator: ", ")
        let line = String.kissmarkLocalized("미러 폴더에 쓰지 못했습니다: \(names)")
        if let notice {
            self.notice = WorkspaceNotice(title: notice.title, message: notice.message + "\n" + line)
        } else {
            notice = WorkspaceNotice(title: String.kissmarkLocalized("미러"), message: line)
        }
    }

    /// Lists the root now, so the sidebar is filled when `start()` returns; that is one
    /// directory, never its subfolders. Folders still expanded from an earlier start reload
    /// in the background.
    private func loadTree() {
        childrenByFolder = [:]
        // A single-file grant has no Folder to list; the tree holds just that Document.
        if folder.isSingleFile {
            childrenByFolder[folder.rootURL] = [FolderTreeNode(url: folder.url, kind: .document, children: nil)]
            return
        }
        refreshChildren(of: folder.rootURL)
        for url in expandedFolderURLs {
            loadChildren(of: url)
        }
    }

    /// Re-lists one Folder synchronously after this workspace changed it (create, rename),
    /// and drops any background load for it that started earlier. Folders never listed stay
    /// unlisted; they read fresh when expanded.
    private func refreshChildren(of changedDirectory: URL) {
        guard !folder.isSingleFile else { return }
        // Matched by path: a Document's parent URL and the listed Folder URL can differ by a trailing slash.
        let path = changedDirectory.standardizedFileURL.path
        let known = [folder.rootURL] + Array(childrenByFolder.keys) + Array(currentLoadIDs.keys)
        guard let directory = known.first(where: { $0.standardizedFileURL.path == path }) else { return }
        currentLoadIDs[directory] = nil
        do {
            childrenByFolder[directory] = try FolderBrowserStore().children(of: directory, within: folder.rootURL)
        } catch {
            errorMessage = Self.readFailureMessage(error)
        }
    }

    /// Lists an expanded Folder's direct children off the main actor, once; later expansions use
    /// the cache. A failed load is not cached, so collapsing and expanding again retries.
    private func loadChildren(of directory: URL) {
        guard hasStarted, childrenByFolder[directory] == nil, currentLoadIDs[directory] == nil else { return }
        nextLoadID += 1
        let id = nextLoadID
        let root = folder.rootURL
        currentLoadIDs[directory] = id
        loadTasks[id] = Task {
            defer { loadTasks[id] = nil }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FolderBrowserStore().children(of: directory, within: root) }
            }.value
            // `stop()` or a synchronous refresh took this Folder over; success or failure, drop it.
            guard currentLoadIDs[directory] == id else { return }
            currentLoadIDs[directory] = nil
            switch result {
            case .success(let children):
                childrenByFolder[directory] = children
            case .failure(let error):
                errorMessage = Self.readFailureMessage(error)
            }
        }
    }

    /// Resolves once every Folder load started so far, stale ones included, has finished.
    func folderLoadsSettled() async {
        while let task = loadTasks.values.first {
            await task.value
        }
    }

    private static func readFailureMessage(_ error: Error) -> String {
        String.kissmarkLocalized("이 폴더를 읽지 못했습니다: \(error.localizedDescription)")
    }
}
