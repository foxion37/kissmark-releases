#if os(macOS)
import AppKit
import SwiftUI

/// macOS window: custom header (hidden titlebar) + resizable sidebar split.
struct FolderBrowserMacLayout<Sidebar: View, Detail: View>: View {
    @Bindable var workspace: FolderBrowserWorkspace
    @Binding var sidebar: KissmarkSidebarPresentation
    var isTitleFocused: FocusState<Bool>.Binding
    let undoManager: UndoManager?
    let newDocument: () -> Void
    let settings: () -> Void
    let chooseFolder: () -> Void
    let openParentFolder: () -> Void
    @ViewBuilder let sidebarContent: () -> Sidebar
    @ViewBuilder let detailContent: () -> Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chromePalette) private var chromePalette
    @State private var windowWidth = KissmarkMetrics.minimumWindowWidth
    @State private var storedSidebarWidth = Double(KissmarkMetrics.sidebarWidth(idiom: .mac).ideal)

    private var actionsAreCollapsed: Bool { windowWidth < KissmarkMetrics.toolbarOverflowWidth }

    private var sidebarWidth: CGFloat {
        KissmarkMetrics.clampedSidebarWidth(CGFloat(storedSidebarWidth), idiom: .mac)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Hairline under the native title bar: the browser's only top
                // boundary, so the sidebar divider meets a line instead of ending
                // in open background.
                Divider().kissmarkChromeDivider(chromePalette)

                FolderBrowserMacHeader(
                    workspace: workspace,
                    sidebarWidth: sidebarWidth,
                    isSidebarVisible: sidebar.isVisible,
                    actionsAreCollapsed: actionsAreCollapsed,
                    isTitleFocused: isTitleFocused,
                    undoManager: undoManager,
                    chooseFolder: chooseFolder,
                    openParentFolder: openParentFolder,
                    toggleSidebar: {
                        withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                            sidebar.toggle()
                        }
                    },
                    newDocument: newDocument,
                    settings: settings
                )
                // The split view stays mounted while collapsed so the WKWebView
                // identity never changes; only the sidebar column animates to 0.
                FolderBrowserSplitView(
                    sidebarWidth: $storedSidebarWidth,
                    isSidebarVisible: sidebar.isVisible,
                    sidebar: sidebarContent,
                    detail: detailContent
                )
            }
            .background(chromePalette?.chromeBackground ?? Color(nsColor: .windowBackgroundColor))
            .onAppear {
                windowWidth = proxy.size.width
                sidebar.update(forWindowWidth: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                windowWidth = width
                withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                    sidebar.update(forWindowWidth: width)
                }
            }
        }
        .onAppear(perform: loadStoredSidebarWidth)
    }

    private func loadStoredSidebarWidth() {
        guard let stored = KissmarkWindowChrome.storedSidebarWidth() else { return }
        storedSidebarWidth = KissmarkMetrics.clampedSidebarWidth(stored, idiom: .mac)
    }
}

/// Sidebar and detail share the window background (the parent's `chromeBackground`,
/// or the system window background under 시스템); the 1pt separator is the only
/// division, and only the selected row keeps a fill.
private struct FolderBrowserSplitView<Sidebar: View, Detail: View>: View {
    @Binding var sidebarWidth: Double
    let isSidebarVisible: Bool
    @State private var dragStartWidth: Double?
    @State private var isDividerHovered = false
    /// Whether this view owns one `resizeLeftRight` entry on the cursor stack, so
    /// every push is matched by exactly one pop.
    @State private var isResizeCursorPushed = false
    @Environment(\.chromePalette) private var chromePalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    private var isDividerActive: Bool { isDividerHovered || dragStartWidth != nil }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: isSidebarVisible ? clampedSidebarWidth : 0)
                .overlay { sidebar().frame(width: clampedSidebarWidth, alignment: .leading) }
                .clipped()

            if isSidebarVisible {
                resizeDivider
            }

            detail()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Stays 1pt in layout (the launch-width math and the action bar's separator
    /// depend on it). The hit region is centered across the divider, leaving
    /// the sidebar's scroll knob reachable while sharing hover, cursor, and drag.
    private var resizeDivider: some View {
        Divider()
            .kissmarkChromeDivider(chromePalette)
            .overlay {
                Rectangle()
                    .fill(.tint)
                    .frame(width: KissmarkMetrics.sidebarDividerHighlightWidth)
                    .opacity(isDividerActive ? 1 : 0)
                    .animation(KissmarkMotion.fade(reduceMotion: reduceMotion), value: isDividerActive)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .center) {
                Color.clear
                    .frame(width: KissmarkMetrics.sidebarDividerHitWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isDividerHovered = hovering
                        updateResizeCursor()
                        if hovering { NSCursor.resizeLeftRight.set() }
                    }
                    .gesture(resizeGesture)
            }
            .zIndex(1)
            .onDisappear {
                // Hiding the sidebar while hovering removes the view without a
                // hover-exit, so release the cursor here.
                isDividerHovered = false
                dragStartWidth = nil
                updateResizeCursor()
            }
    }

    private var clampedSidebarWidth: CGFloat {
        KissmarkMetrics.clampedSidebarWidth(CGFloat(sidebarWidth), idiom: .mac)
    }

    /// Pushes the resize cursor while hovered or dragging; a drag that outruns the
    /// hit region keeps it until the drag ends.
    private func updateResizeCursor() {
        if isDividerActive, !isResizeCursorPushed {
            NSCursor.resizeLeftRight.push()
            isResizeCursorPushed = true
        } else if !isDividerActive, isResizeCursorPushed {
            NSCursor.pop()
            isResizeCursorPushed = false
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartWidth == nil {
                    dragStartWidth = sidebarWidth
                    updateResizeCursor()
                }
                let initialWidth = dragStartWidth ?? sidebarWidth
                let limits = KissmarkMetrics.sidebarWidth(idiom: .mac)
                sidebarWidth = min(
                    max(initialWidth + Double(value.translation.width), Double(limits.min)),
                    Double(limits.max)
                )
            }
            .onEnded { _ in
                KissmarkWindowChrome.storeSidebarWidth(CGFloat(sidebarWidth))
                dragStartWidth = nil
                updateResizeCursor()
            }
    }
}

/// Applies the launch window size once per window: the DEBUG UI-test override when
/// one is passed, otherwise the Document-column default clamped to the screen
/// (ADR 0008 keeps later user resizes). A Folder switch or a second probe view does
/// not fire it again, so the user's own size survives the session.
struct FolderBrowserWindowConfigurator: NSViewRepresentable {
    final class ProbeView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    @MainActor private static var sizedWindows = Set<ObjectIdentifier>()

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView(frame: .zero)
        view.onWindow = Self.sizeOnce
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        Self.sizeOnce(window)
    }

    @MainActor
    private static func sizeOnce(_ window: NSWindow) {
        let identity = ObjectIdentifier(window)
        guard !sizedWindows.contains(identity) else { return }
        sizedWindows.insert(identity)
        let visibleFrame = window.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size
        let size = uiTestContentSize() ?? KissmarkWindowChrome.launchContentSize(visibleFrame: visibleFrame)
        DispatchQueue.main.async {
            window.setContentSize(size)
        }
    }

    #if DEBUG
    private static func uiTestContentSize() -> NSSize? {
        guard AppLaunchRoute.isUITestGate(),
              let rawWidth = launchValue(
                environmentKey: "KISSMARK_UI_TEST_WIDTH",
                argumentKey: "-ui-test-width"
              ),
              let width = Double(rawWidth) else {
            return nil
        }
        let rawHeight = launchValue(
            environmentKey: "KISSMARK_UI_TEST_HEIGHT",
            argumentKey: "-ui-test-height"
        )
        let height = rawHeight.flatMap(Double.init) ?? Double(KissmarkMetrics.minimumWindowHeight)
        return NSSize(width: width, height: height)
    }
    #else
    private static func uiTestContentSize() -> NSSize? { nil }
    #endif

    private static func launchValue(environmentKey: String, argumentKey: String) -> String? {
        let process = ProcessInfo.processInfo
        if let value = process.environment[environmentKey] { return value }
        guard let index = process.arguments.firstIndex(of: argumentKey),
              process.arguments.indices.contains(index + 1) else {
            return nil
        }
        return process.arguments[index + 1]
    }
}
#endif
