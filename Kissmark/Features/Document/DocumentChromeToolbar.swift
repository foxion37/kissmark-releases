import SwiftUI

/// Single window-toolbar row: leading filename + icon-only actions (or plain `>`).
struct DocumentChromeToolbar: ToolbarContent {
    @Bindable var workspace: FolderBrowserWorkspace
    var isTitleFocused: FocusState<Bool>.Binding
    var collapsesOverflow: Bool = false
    var undoManager: UndoManager?
    let newDocument: () -> Void
    var settings: (() -> Void)? = nil

    var body: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(id: "kissmark.document.title", placement: .navigation) { titleField }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(id: "kissmark.document.chrome", placement: .primaryAction) { cluster }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "kissmark.document.title", placement: .navigation) { titleField }
            ToolbarItem(id: "kissmark.document.chrome", placement: .primaryAction) { cluster }
        }
    }

    private var titleField: some View {
        KissmarkFilenameField(
            text: $workspace.titleDraft,
            isFocused: isTitleFocused,
            isEditable: workspace.session?.mode == .edit,
            minWidth: collapsesOverflow
                ? KissmarkMetrics.toolbarTitleCompactMinWidth
                : KissmarkMetrics.toolbarTitleMinWidth,
            onSubmit: { workspace.commitTitle(undoManager: undoManager) }
        )
    }

    private var cluster: some View {
        KissmarkToolbarCluster(
            items: KissmarkDocumentToolbarItems.items(
                for: workspace,
                undoManager: undoManager,
                newDocument: newDocument,
                settings: settings
            ),
            collapsesOverflow: collapsesOverflow
        )
    }
}
