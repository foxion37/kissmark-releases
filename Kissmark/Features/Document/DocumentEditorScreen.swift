import SwiftUI

/// Document surface plus the two session-level alerts. Actions live in
/// `FolderBrowserWorkspace`. The document info (path, save state, dates) is pushed
/// into the surface's in-flow `#docinfo` header, not a floating overlay.
struct DocumentEditorScreen: View {
    @Bindable var session: DocumentSession
    /// Folder the tree roots at. `nil` (the DEBUG fixture) shows the absolute path.
    var folderRoot: URL?
    /// 검토 card data from the workspace (`nil` hides the card) and its action handler.
    var review: DocumentReview? = nil
    var onReviewAction: (ReviewAction) -> Void = { _ in }

    @AppStorage(DocumentInfoBar.expansionStorageKey) private var isInfoExpanded = true
    @AppStorage(DocumentReview.expansionStorageKey) private var isReviewExpanded = true
    @AppStorage(KissmarkTextSize.storageKey) private var textSizeID = KissmarkTextSize.medium.rawValue
    @AppStorage(DesignOverrides.storageKey) private var designJSON = ""

    var body: some View {
        DocumentSurfaceView(
            text: $session.text,
            mode: session.mode,
            viewMode: session.viewMode,
            info: info,
            onInfoExpanded: { isInfoExpanded = $0 },
            review: review.map { var card = $0; card.expanded = isReviewExpanded; return card },
            onReviewExpanded: { isReviewExpanded = $0 },
            onReviewAction: onReviewAction
        )
        #if os(iOS)
        // The iOS navigation bar would otherwise repeat the Folder name; the
        // macOS window title is owned by the root Folder-browser view, so an
        // empty title here would blank the native title bar.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(
            "문서가 Kissmark 밖에서 바뀌었습니다.",
            isPresented: Binding(
                get: { session.saveError == .changedExternally },
                set: { if !$0 { session.dismissSaveError() } }
            )
        ) {
            Button("확인") { session.dismissSaveError() }
        } message: {
            Text("문서를 다시 열거나, 편집 내용을 다른 곳에 복사해 두세요.")
        }
        .alert(
            "이름을 바꾸지 못했습니다",
            isPresented: Binding(
                get: { session.renameError != nil },
                set: { if !$0 { session.dismissRenameError() } }
            )
        ) {
            Button("확인", role: .cancel) { session.dismissRenameError() }
        } message: {
            Text(renameErrorMessage)
        }
    }

    /// Re-sent through the surface bridge whenever any field changes; the bridge
    /// queues it until the editor is ready and re-applies it after a crash reload.
    private var info: DocumentInfo? {
        guard session.sourceURL != nil else { return nil }
        let state = DocumentInfoBar.saveState(
            isDirty: session.isDirty,
            mode: session.mode,
            hasSaveError: session.saveError != nil
        )
        return DocumentInfo(
            path: documentPath,
            saveState: state.wireValue,
            saveLabel: state.text,
            modified: dateText(session.version?.modificationDate),
            created: dateText(session.version?.creationDate),
            expanded: isInfoExpanded
        )
    }

    /// Folder-relative path of the open Document; the absolute path when the Document
    /// sits outside the browsed root (a single-file workspace that was never granted).
    private var documentPath: String {
        guard let url = session.sourceURL else { return "" }
        if let folderRoot, let relative = MirrorCoordinator.relativePath(of: url, in: folderRoot) {
            return relative
        }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Same formatter as 문서 정보's 수정일; also used for the 검토 완료 label.
    static func dateText(_ date: Date?) -> String {
        guard let date else { return String.kissmarkLocalized("없음") }
        return date.formatted(
            Date.FormatStyle(date: .long, time: .shortened)
                .locale(KissmarkLocalization.locale)
        )
    }

    private func dateText(_ date: Date?) -> String { Self.dateText(date) }

    private var renameErrorMessage: String {
        switch session.renameError {
        case .destinationExists:
            String.kissmarkLocalized("같은 이름의 문서가 이미 있습니다.")
        case .invalidName, .changedExternally, .none:
            String.kissmarkLocalized("문서 이름을 다시 확인하세요.")
        }
    }
}
