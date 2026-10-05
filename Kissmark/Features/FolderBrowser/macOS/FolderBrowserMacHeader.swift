#if os(macOS)
import AppKit
import SwiftUI

/// Root-owned action bar directly under the native title bar (ADR 0020). The sidebar
/// lane leads with the sidebar toggle (a fixed position whether or not the sidebar is
/// visible) and lets the FolderControl fill the rest; the Document lane holds the
/// filename and the action cluster.
struct FolderBrowserMacHeader: View {
    @Bindable var workspace: FolderBrowserWorkspace
    let sidebarWidth: CGFloat
    let isSidebarVisible: Bool
    let actionsAreCollapsed: Bool
    var isTitleFocused: FocusState<Bool>.Binding
    let undoManager: UndoManager?
    let chooseFolder: () -> Void
    let openParentFolder: () -> Void
    let toggleSidebar: () -> Void
    let newDocument: () -> Void
    let settings: () -> Void

    @Environment(\.chromePalette) private var chromePalette

    var body: some View {
        HStack(spacing: 0) {
            sidebarLane

            if isSidebarVisible {
                Divider()
                    .kissmarkChromeDivider(chromePalette)
            }

            HStack(spacing: KissmarkMetrics.toolbarItemGap) {
                KissmarkFilenameField(
                    text: $workspace.titleDraft,
                    isFocused: isTitleFocused,
                    isEditable: workspace.session?.mode == .edit,
                    minWidth: actionsAreCollapsed
                        ? KissmarkMetrics.toolbarTitleCompactMinWidth
                        : KissmarkMetrics.toolbarTitleMinWidth,
                    onSubmit: { workspace.commitTitle(undoManager: undoManager) }
                )
                Spacer(minLength: 0)
                KissmarkToolbarCluster(
                    items: KissmarkDocumentToolbarItems.items(
                        for: workspace,
                        undoManager: undoManager,
                        newDocument: newDocument,
                        settings: settings
                    ),
                    collapsesOverflow: actionsAreCollapsed
                )
            }
            .padding(.leading, KissmarkMetrics.sidebarInset)
        }
        .frame(height: KissmarkMetrics.sidebarHeaderHeight)
        .background(chromePalette?.chromeBackground ?? Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider().kissmarkChromeDivider(chromePalette)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-browser-shell-header")
    }

    /// Occupies exactly the sidebar column's width while it is visible, so the bar's
    /// separator lines up with the split view's; collapsed, it shrinks to the toggle.
    private var sidebarLane: some View {
        HStack(spacing: KissmarkMetrics.iconLabelGap) {
            KissmarkSidebarToggleButton(isSidebarVisible: isSidebarVisible, action: toggleSidebar)

            if isSidebarVisible {
                KissmarkFolderControl(
                    folderName: workspace.folderDisplayName,
                    isSingleFileWorkspace: workspace.isSingleFileWorkspace,
                    action: chooseFolder,
                    openParentFolder: openParentFolder
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, KissmarkMetrics.sidebarInset)
        .padding(.trailing, isSidebarVisible ? KissmarkMetrics.sidebarInset : 0)
        .frame(width: isSidebarVisible ? sidebarWidth : nil, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-chrome-header")
    }
}
#endif
