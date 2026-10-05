import SwiftUI

/// One list of Document toolbar items for every shell (ADR 0011 stable slots, ADR 0016 disabled stays visible).
enum KissmarkDocumentToolbarItems {
    @MainActor
    static func items(
        for workspace: FolderBrowserWorkspace,
        undoManager: UndoManager?,
        newDocument: @escaping () -> Void,
        settings: (() -> Void)? = nil
    ) -> [KissmarkToolbarCluster.Item] {
        let session = workspace.session
        let hasDocument = session != nil
        let isEditing = session?.mode == .edit
        let isSourceView = session?.viewMode == .source
        var items: [KissmarkToolbarCluster.Item] = [
            .init(
                id: "kissmark.folder.new",
                title: "새 문서",
                icon: .lucide(.plus),
                opticalScale: KissmarkMetrics.toolbarPlusOpticalScale,
                accessibilityIdentifier: "new-document-button"
            ) {
                workspace.commitTitle(undoManager: undoManager)
                newDocument()
            },
            .init(
                id: "kissmark.document.source",
                title: isSourceView ? "렌더 보기" : "코드 보기",
                icon: .lucide(.code),
                active: isSourceView,
                disabled: !hasDocument,
                accessibilityIdentifier: "document-source-button",
                accessibilityValue: isSourceView ? "on" : "off"
            ) {
                workspace.toggleDocumentViewMode(undoManager: undoManager)
            },
            .init(
                id: "kissmark.document.mode",
                title: isEditing ? "잠금" : "잠금 해제",
                icon: .lucide(isEditing ? .lockOpen : .lock),
                active: isEditing,
                disabled: !hasDocument,
                opticalScale: KissmarkMetrics.toolbarLockOpticalScale,
                accessibilityIdentifier: "document-mode-button",
                accessibilityValue: isEditing ? "edit" : "read"
            ) {
                workspace.toggleDocumentMode(undoManager: undoManager)
            },
            .init(
                id: "kissmark.document.archive",
                title: "보관",
                icon: .lucide(.archive),
                disabled: !hasDocument,
                opticalScale: KissmarkMetrics.toolbarArchiveOpticalScale,
                accessibilityIdentifier: "document-archive-button"
            ) {
                workspace.archive(undoManager: undoManager)
            },
            .init(
                id: "kissmark.document.close",
                title: "닫기",
                icon: .lucide(.x),
                disabled: !hasDocument,
                opticalScale: KissmarkMetrics.toolbarCloseOpticalScale,
                accessibilityIdentifier: "document-close-button"
            ) {
                workspace.requestClose(undoManager: undoManager)
            },
        ]
        if let settings {
            // ADR 0020: 설정 sits immediately left of 닫기, which stays rightmost.
            items.insert(
                .init(
                    id: "kissmark.settings",
                    title: "설정",
                    icon: .lucide(.settings),
                    opticalScale: KissmarkMetrics.toolbarSettingsOpticalScale,
                    accessibilityIdentifier: "settings-button",
                    action: settings
                ),
                at: items.count - 1
            )
        }
        return items
    }
}
