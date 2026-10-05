import SwiftUI

/// Folder browser for every platform. Only the window header differs; tree, detail, dialogs, and actions are shared.
struct FolderBrowserView: View {
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var workspace: FolderBrowserWorkspace
    @State private var sidebar = KissmarkSidebarPresentation()
    @State private var isNewDocumentPresented = false
    @State private var newDocumentName = ""
    @FocusState private var isTitleFocused: Bool
    #if os(iOS)
    @Environment(\.chromePalette) private var chromePalette
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var windowWidth: CGFloat = KissmarkMetrics.sidebarAutoCollapseWidth + 1
    @State private var isSettingsPresented = false
    #else
    @Environment(\.openWindow) private var openWindow
    #endif

    /// A Document to show; a new value after appearing (an external open that lands in
    /// the same browsed root) selects it in place.
    private let documentRequest: URL?
    private let consumeDocumentRequest: () -> Void
    /// ⌘R: asks the app to rebuild this window, reopening the given Document.
    private let requestReload: (URL?) -> Void

    init(
        folder: SelectedFolder,
        initialDocumentURL: URL? = nil,
        mirror: MirrorCoordinator? = nil,
        consumeDocumentRequest: @escaping () -> Void = {},
        openExternalDocument: @escaping (URL) -> Void = { _ in },
        requestReload: @escaping (URL?) -> Void = { _ in }
    ) {
        // UI-test runs share the app container; they get a throwaway store, never the user's memory.
        let memory = AppLaunchRoute.isUITestGate()
            ? MemoryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("kissmark-ui-test-\(UUID().uuidString)", isDirectory: true))
            : MemoryStore.live
        _workspace = State(initialValue: FolderBrowserWorkspace(folder: folder, initialDocumentURL: initialDocumentURL, mirror: mirror, memory: memory, openOutside: openExternalDocument))
        documentRequest = initialDocumentURL
        self.consumeDocumentRequest = consumeDocumentRequest
        self.requestReload = requestReload
    }

    var body: some View {
        platformLayout
            .modifier(FolderBrowserDialogs(
                workspace: workspace,
                isNewDocumentPresented: $isNewDocumentPresented,
                newDocumentName: $newDocumentName,
                createDocument: createDocument
            ))
            .onAppear {
                workspace.start()
                #if DEBUG
                applyRenderedFixtureIfRequested()
                #endif
            }
            .onChange(of: documentRequest) { _, url in
                guard let url else { return }
                workspace.selectDocument(url, undoManager: undoManager, recordsOpen: true)
                consumeDocumentRequest()
            }
            .onDisappear { workspace.stop() }
            .onReceive(NotificationCenter.default.publisher(for: .kissmarkReload)) { _ in
                guard workspace.prepareReload(undoManager: undoManager) else { return }
                requestReload(workspace.session?.sourceURL)
            }
            .onChange(of: workspace.session?.mode) { _, mode in
                if mode == .read { isTitleFocused = false }
            }
            .onChange(of: isTitleFocused) { _, focused in
                if !focused { workspace.commitTitle(undoManager: undoManager) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("folder-browser")
    }

    // MARK: Shared pieces

    private var tree: some View {
        FolderBrowserTree(
            folders: workspace.rootFolders,
            documents: workspace.rootDocuments,
            selectedDocumentURL: workspace.selectedDocumentURL,
            isExpanded: workspace.isFolderExpanded,
            toggleFolder: workspace.toggleFolder,
            selectDocument: { workspace.selectDocument($0, undoManager: undoManager) },
            recents: workspace.recentDocuments,
            selectRecent: { workspace.openRecent($0, undoManager: undoManager) }
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let session = workspace.session {
            DocumentEditorScreen(
                session: session,
                folderRoot: workspace.folder.rootURL,
                review: workspace.review,
                onReviewAction: workspace.performReviewAction
            )
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            KissmarkEmptyState(
                icon: .fileText,
                title: "문서를 선택하세요",
                message: "폴더 트리에서 Markdown 문서를 고르거나, 새로 만드세요.",
                actionTitle: "새 문서",
                actionIcon: .plus,
                action: presentNewDocument
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(KissmarkMetrics.documentPadding(idiom: .current))
            .accessibilityIdentifier("folder-browser-empty-detail")
        }
    }

    private func presentNewDocument() {
        workspace.commitTitle(undoManager: undoManager)
        isNewDocumentPresented = true
    }

    private func chooseRootFolder() {
        NotificationCenter.default.post(name: .kissmarkChooseFolder, object: nil)
    }

    private func openParentFolder() {
        NotificationCenter.default.post(name: .kissmarkOpenParentFolder, object: nil)
    }

    private func createDocument() {
        if workspace.createDocument(named: newDocumentName, undoManager: undoManager) {
            newDocumentName = ""
        }
    }

    // MARK: Platform layouts

    #if os(macOS)
    private var platformLayout: some View {
        FolderBrowserMacLayout(
            workspace: workspace,
            sidebar: $sidebar,
            isTitleFocused: $isTitleFocused,
            undoManager: undoManager,
            newDocument: presentNewDocument,
            settings: { openWindow(id: KissmarkWindowChrome.settingsWindowID) },
            chooseFolder: chooseRootFolder,
            openParentFolder: openParentFolder,
            sidebarContent: { tree },
            detailContent: { detail }
        )
        // The native title bar names the product; the action bar's filename field
        // already shows (and renames) the open Document. Verbatim: a product name,
        // not a String Catalog key.
        .navigationTitle(Text(verbatim: "Kissmark"))
    }
    #else
    @ViewBuilder
    private var platformLayout: some View {
        Group {
            if KissmarkIdiom.current == .phone { phoneStack } else { splitBrowser }
        }
        .sheet(isPresented: $isSettingsPresented) { settingsSheet }
    }
    #endif

    #if DEBUG
    private func applyRenderedFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-test-rendered-fixture") else { return }
        if let document = workspace.rootDocuments.first {
            workspace.selectDocument(document.url)
        }
    }
    #endif
}

#if os(iOS)
extension FolderBrowserView {

    /// Collapse actions into plain `>` before the system invents a glass `>>`.
    private var collapsesToolbarOverflow: Bool {
        let limit = KissmarkIdiom.current == .phone
            ? KissmarkMetrics.phoneToolbarOverflowWidth
            : KissmarkMetrics.toolbarOverflowWidth
        return windowWidth < limit
    }

    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    private var phoneStack: some View {
        NavigationStack {
            sidebarColumn
                .navigationTitle(workspace.folder.rootURL.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        windowToolbarActions
                    }
                }
                .navigationDestination(item: Binding(
                    get: { workspace.selectedDocumentURL },
                    set: { url in
                        if let url {
                            workspace.selectDocument(url, undoManager: undoManager)
                        } else {
                            workspace.closeDocument()
                        }
                    }
                )) { _ in
                    if let session = workspace.session {
                        DocumentEditorScreen(
                            session: session,
                            folderRoot: workspace.folder.rootURL,
                            review: workspace.review,
                            onReviewAction: workspace.performReviewAction
                        )
                            .id(session.id)
                            .toolbar {
                                DocumentChromeToolbar(
                                    workspace: workspace,
                                    isTitleFocused: $isTitleFocused,
                                    collapsesOverflow: collapsesToolbarOverflow,
                                    undoManager: undoManager,
                                    newDocument: presentNewDocument,
                                    settings: { isSettingsPresented = true }
                                )
                            }
                    }
                }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: KissmarkWindowWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(KissmarkWindowWidthKey.self) { windowWidth = $0 }
        .onChange(of: windowWidth) { _, width in
            updateResponsiveLayout(for: width)
        }
    }

    private var splitBrowser: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
                // Must live on the sidebar column or the system glass toggle stays.
                .toolbar(removing: .sidebarToggle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationSplitViewColumnWidth(
                    min: KissmarkMetrics.sidebarWidth(idiom: .current).min,
                    ideal: KissmarkMetrics.sidebarWidth(idiom: .current).ideal,
                    max: KissmarkMetrics.sidebarWidth(idiom: .current).max
                )
        } detail: {
            NavigationStack {
                detail
            }
            .toolbar {
                windowToolbar
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: KissmarkWindowWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(KissmarkWindowWidthKey.self) { windowWidth = $0 }
        .onChange(of: windowWidth) { _, width in
            updateResponsiveLayout(for: width)
        }
    }

    /// Compact tree: matched horizontal insets; outline folder → open when expanded.
    private var folderSidebar: some View {
        tree
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, KissmarkMetrics.treeRowHeight)
            .contentMargins(
                .top,
                KissmarkMetrics.sidebarSectionGap,
                for: .scrollContent
            )
    }

    private var sidebarColumn: some View {
        folderSidebar
            .safeAreaInset(edge: .top, spacing: 0) {
                if KissmarkIdiom.current != .phone {
                    sidebarChromeHeader
                }
            }
    }

    private var sidebarChromeHeader: some View {
        HStack(spacing: KissmarkMetrics.iconLabelGap) {
            windowSidebarToggle
            folderRootControl
        }
        .padding(.horizontal, KissmarkMetrics.sidebarInset)
        .frame(height: KissmarkMetrics.sidebarHeaderHeight)
        .background(chromePalette?.chromeBackground ?? Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider().kissmarkChromeDivider(chromePalette)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-chrome-header")
    }

    private var folderRootControl: some View {
        KissmarkFolderControl(
            folderName: workspace.folderDisplayName,
            isSingleFileWorkspace: workspace.isSingleFileWorkspace,
            action: chooseRootFolder,
            openParentFolder: openParentFolder
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ToolbarContentBuilder
    private var windowToolbar: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            if !isSidebarVisible {
                ToolbarItem(id: "kissmark.sidebar.toggle", placement: .navigation) {
                    windowSidebarToggle
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItem(id: "kissmark.document.title", placement: .principal) {
                windowToolbarTitle
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(id: "kissmark.window.actions", placement: .primaryAction) {
                windowToolbarActions
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            if !isSidebarVisible {
                ToolbarItem(id: "kissmark.sidebar.toggle", placement: .navigation) {
                    windowSidebarToggle
                }
            }

            ToolbarItem(id: "kissmark.document.title", placement: .principal) {
                windowToolbarTitle
            }

            ToolbarItem(id: "kissmark.window.actions", placement: .primaryAction) {
                windowToolbarActions
            }
        }
    }

    private var windowSidebarToggle: some View {
        KissmarkSidebarToggleButton(
            isSidebarVisible: isSidebarVisible,
            action: toggleSidebar
        )
    }

    private var windowToolbarTitle: some View {
        @Bindable var bindableWorkspace = workspace
        return KissmarkFilenameField(
            text: $bindableWorkspace.titleDraft,
            isFocused: $isTitleFocused,
            isEditable: workspace.session?.mode == .edit,
            minWidth: collapsesToolbarOverflow
                ? KissmarkMetrics.toolbarTitleCompactMinWidth
                : KissmarkMetrics.toolbarTitleMinWidth,
            onSubmit: { workspace.commitTitle(undoManager: undoManager) }
        )
    }

    private var windowToolbarActions: some View {
        KissmarkToolbarCluster(
            items: windowToolbarItems,
            collapsesOverflow: collapsesToolbarOverflow
        )
    }

    private var windowToolbarItems: [KissmarkToolbarCluster.Item] {
        KissmarkDocumentToolbarItems.items(
            for: workspace,
            undoManager: undoManager,
            newDocument: presentNewDocument,
            settings: { isSettingsPresented = true }
        )
    }

    private var settingsSheet: some View {
        NavigationStack {
            KissmarkSettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        KissmarkIconButton(title: "닫기", lucide: .x) {
                            isSettingsPresented = false
                        }
                    }
                }
        }
    }

    private func updateResponsiveLayout(for width: CGFloat) {
        let wasVisible = sidebar.isVisible
        sidebar.update(forWindowWidth: width)
        guard wasVisible != sidebar.isVisible else { return }
        setSidebarVisible(sidebar.isVisible)
    }

    private func toggleSidebar() {
        sidebar.toggle()
        setSidebarVisible(sidebar.isVisible)
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
            columnVisibility = isVisible ? .all : .detailOnly
        }
    }
}
#endif
