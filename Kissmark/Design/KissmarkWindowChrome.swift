import SwiftUI
#if os(macOS)
import AppKit
#endif

enum KissmarkWindowChrome {
    /// Identifier of the macOS Settings window scene. The app uses a plain
    /// `Window(id:)` scene (SwiftUI's `Settings` scene cannot keep a user-resized
    /// geometry) and ⌘, is wired through `.appSettings`.
    static let settingsWindowID = "kissmark-settings"

    /// Storage key for the user's macOS sidebar width. The split view owns writes;
    /// the launch window size reads it.
    static let sidebarWidthKey = "kissmark.folder-browser-shell.sidebar-width"

    static func storedSidebarWidth(defaults: UserDefaults = .standard) -> CGFloat? {
        guard let value = defaults.object(forKey: sidebarWidthKey) as? NSNumber else { return nil }
        return CGFloat(value.doubleValue)
    }

    static func storeSidebarWidth(_ width: CGFloat, defaults: UserDefaults = .standard) {
        defaults.set(Double(width), forKey: sidebarWidthKey)
    }

    /// Content width that fits the Document reading column:
    /// sidebar + separator + (measure + 2 × horizontal padding) × text scale, plus the
    /// column slack on both sides so the Edit-Mode block handle stays on screen.
    static func defaultContentWidth(
        sidebarWidth: CGFloat,
        textScale: Double,
        measure: CGFloat = KissmarkMetrics.defaultDocumentMeasure,
        horizontalPadding: CGFloat = KissmarkMetrics.defaultDocumentHorizontalPadding,
        columnSlack: CGFloat = KissmarkMetrics.documentColumnSlack
    ) -> CGFloat {
        let scale = CGFloat(textScale)
        return sidebarWidth
            + KissmarkMetrics.sidebarDividerWidth
            + (measure + 2 * horizontalPadding) * scale
            + 2 * columnSlack
    }

    /// Keeps a launch size inside the screen's usable area without dropping below the
    /// window minimum. The usable area wins when even the minimum does not fit there.
    static func clampedContentSize(
        _ size: CGSize,
        to visibleFrame: CGSize,
        minimum: CGSize
    ) -> CGSize {
        CGSize(
            width: min(max(size.width, minimum.width), max(minimum.width, visibleFrame.width)),
            height: min(max(size.height, minimum.height), max(minimum.height, visibleFrame.height))
        )
    }

    #if os(macOS)
    /// Content size the main window opens with: the stored sidebar width and text size
    /// decide the Document column, and the screen's usable area caps the result.
    @MainActor
    static func launchContentSize(
        defaults: UserDefaults = .standard,
        visibleFrame: CGSize? = NSScreen.main?.visibleFrame.size
    ) -> CGSize {
        let storedWidth = storedSidebarWidth(defaults: defaults)
            ?? KissmarkMetrics.sidebarWidth(idiom: .mac).ideal
        let sidebar = KissmarkMetrics.clampedSidebarWidth(storedWidth, idiom: .mac)
        let storedID = defaults.string(forKey: KissmarkTextSize.storageKey)
        let scale = storedID.flatMap(KissmarkTextSize.init(rawValue:))?.scale
            ?? KissmarkTextSize.medium.scale
        // A 장폭 override replaces the default measure, same as the CSS.
        let measure = KissmarkMetrics.documentMeasure(
            DesignOverrides.decode(defaults.string(forKey: DesignOverrides.storageKey) ?? "")
        )
        let size = CGSize(
            width: defaultContentWidth(sidebarWidth: sidebar, textScale: scale, measure: measure),
            height: KissmarkMetrics.defaultWindowContentHeight
        )
        guard let visibleFrame else { return size }
        return clampedContentSize(size, to: visibleFrame, minimum: minimumContentSize)
    }
    #endif

    #if os(macOS)
    @MainActor
    static var minimumContentSize: NSSize {
        NSWindow.contentRect(
            forFrameRect: NSRect(
                x: 0,
                y: 0,
                width: KissmarkMetrics.minimumWindowWidth,
                height: KissmarkMetrics.minimumWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable]
        )
        .size
    }

    /// The SwiftUI `Settings` scene ignores `windowResizability` and comes up as a
    /// size-to-fit window without `.resizable`, so the user cannot resize Settings
    /// and a tab switch re-fits the window. Add the missing flag and a content
    /// minimum once, leaving the current size and position untouched.
    static func makeSettingsWindowResizable(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.contentMinSize = KissmarkMetrics.settingsMinimumSize
        // A finite content maximum is what pinned the window at its ideal size.
        let unbounded = NSSize(width: 100_000, height: 100_000)
        window.contentMaxSize = unbounded
        window.maxSize = unbounded
    }
    #endif
}

#if os(macOS)
/// Attaches the Settings-window fix to its hosting `NSWindow` exactly once per
/// window, as soon as the view is in the hierarchy.
struct KissmarkSettingsWindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        weak var appliedWindow: NSWindow?
    }

    private final class ProbeView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView(frame: .zero)
        view.onWindow = Self.applier(context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        Self.applier(context.coordinator)(window)
    }

    private static func applier(_ coordinator: Coordinator) -> @MainActor (NSWindow) -> Void {
        { window in
            guard coordinator.appliedWindow !== window else { return }
            coordinator.appliedWindow = window
            KissmarkWindowChrome.makeSettingsWindowResizable(window)
        }
    }
}
#endif
