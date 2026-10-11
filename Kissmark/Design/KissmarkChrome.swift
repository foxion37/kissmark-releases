import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    func kissmarkTapTarget() -> some View {
        #if os(iOS)
        frame(minWidth: KissmarkMetrics.minTapTarget, minHeight: KissmarkMetrics.minTapTarget)
        #else
        self
        #endif
    }

    /// Glass fill for chrome controls (ADR 0024): the outline geometry and state
    /// colors stay, the fill becomes the system Liquid Glass effect on
    /// macOS/iOS 26+ and an ultra-thin material below. The fill carries no
    /// color — hover wash, active outline, and disabled states draw over it.
    @ViewBuilder
    func kissmarkGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

enum KissmarkChromeIcon: Equatable {
    /// Lucide asset (shadcn icon set) — preferred for all chrome.
    case lucide(KissmarkLucide)
}

/// Control that names the current root Folder and switches it: a glass fill under
/// the one 1pt outline (ADR 0024). A single-file workspace offers separate actions
/// for granting the Document's parent and choosing another Folder. Sits in the
/// action bar's sidebar lane (macOS) and the sidebar header (iOS).
struct KissmarkFolderControl: View {
    let folderName: String
    var isSingleFileWorkspace: Bool = false
    let action: () -> Void
    let openParentFolder: () -> Void

    private var actionTitle: LocalizedStringKey {
        isSingleFileWorkspace ? "폴더 열기" : "폴더 선택"
    }

    @Environment(\.chromePalette) private var chromePalette
    private var mutedColor: Color { chromePalette?.chromeMuted ?? .secondary }

    var body: some View {
        Group {
            if isSingleFileWorkspace {
                // AppKit flattens Menu labels, so keep the chrome outside its hit target.
                controlLabel
                    .accessibilityHidden(true)
                    .overlay {
                        Menu {
                            Button("현재 문서의 폴더 열기…", action: openParentFolder)
                                .accessibilityIdentifier("open-document-folder")
                            Button("다른 폴더 열기…", action: action)
                                .accessibilityIdentifier("choose-another-folder")
                        } label: {
                            Color.clear
                        }
                        #if os(macOS)
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        #endif
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
            } else {
                Button(action: action) {
                    controlLabel
                }
            }
        }
        .buttonStyle(KissmarkPressButtonStyle(pressedScale: KissmarkMotion.pressedWideScale))
        .kissmarkTapTarget()
        #if os(macOS)
        .kissmarkHoverHint(Text(actionTitle))
        #else
        .help(Text(actionTitle))
        #endif
        .accessibilityLabel(Text(actionTitle))
        .accessibilityValue(Text(folderName))
        .accessibilityIdentifier("choose-folder-button")
    }

    private var controlLabel: some View {
        HStack(spacing: KissmarkMetrics.iconLabelGap) {
            KissmarkLucideImage(
                icon: .folderOpen,
                pointSize: KissmarkMetrics.folderControlIconSize
            )
            .foregroundStyle(mutedColor)

            if isSingleFileWorkspace {
                Text(actionTitle)
                    .font(KissmarkType.font(.body, weight: KissmarkType.controlWeight))
                    .lineLimit(1)
            } else {
                Text(folderName)
                    .font(KissmarkType.font(.body, weight: KissmarkType.controlWeight))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            KissmarkLucideImage(
                icon: .chevronsUpDown,
                pointSize: KissmarkMetrics.folderControlSwitchIconSize
            )
            .foregroundStyle(mutedColor)
        }
        .padding(.horizontal, KissmarkMetrics.folderControlInlineInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: KissmarkMetrics.folderControlHeight)
        .contentShape(Rectangle())
        .kissmarkGlass(in: RoundedRectangle(
            cornerRadius: KissmarkMetrics.folderControlRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: KissmarkMetrics.folderControlRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.secondary.opacity(KissmarkMetrics.iconButtonOutlineOpacity),
                lineWidth: KissmarkMetrics.iconButtonOutlineWidth
            )
        }
    }
}

/// Icon-first chrome control with localized accessibility label.
struct KissmarkIconButton: View {
    let title: LocalizedStringKey
    let icon: KissmarkChromeIcon
    var disabled: Bool = false
    var active: Bool = false
    /// Per-glyph optical scale (plus reads small; × / archive read large).
    var opticalScale: CGFloat = 1
    var rotation: Angle = .zero
    var accessibilityIdentifier: String?
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chromePalette) private var chromePalette

    private var inkColor: Color { chromePalette?.chromePrimary ?? .primary }
    private var outlineColor: Color { chromePalette?.chromeMuted ?? .secondary }

    init(
        title: LocalizedStringKey,
        lucide: KissmarkLucide,
        disabled: Bool = false,
        active: Bool = false,
        opticalScale: CGFloat = 1,
        rotation: Angle = .zero,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = .lucide(lucide)
        self.disabled = disabled
        self.active = active
        self.opticalScale = opticalScale
        self.rotation = rotation
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    init(
        title: LocalizedStringKey,
        icon: KissmarkChromeIcon,
        disabled: Bool = false,
        active: Bool = false,
        opticalScale: CGFloat = 1,
        rotation: Angle = .zero,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.disabled = disabled
        self.active = active
        self.opticalScale = opticalScale
        self.rotation = rotation
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        disabled ? AnyShapeStyle(.tertiary) :
                            AnyShapeStyle(active ? Color.accentColor : outlineColor.opacity(KissmarkMetrics.iconButtonOutlineOpacity)),
                        lineWidth: KissmarkMetrics.iconButtonOutlineWidth
                    )
                Circle()
                    .fill(isHovered && !disabled ? inkColor.opacity(KissmarkMetrics.iconButtonHoverOpacity) : .clear)
                if case .lucide(let lucide) = icon {
                    KissmarkLucideImage(
                        icon: lucide,
                        pointSize: KissmarkMetrics.toolbarIconPointSize,
                        opticalScale: opticalScale
                    )
                    .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(active ? Color.accentColor : inkColor))
                    .rotationEffect(reduceMotion ? .zero : rotation)
                    .animation(KissmarkMotion.spring(reduceMotion: reduceMotion), value: rotation)
                }
            }
            .frame(width: KissmarkMetrics.toolbarButtonSize, height: KissmarkMetrics.toolbarButtonSize)
            .kissmarkGlass(in: Circle())
            .contentShape(Circle())
            .animation(KissmarkMotion.fade(reduceMotion: reduceMotion), value: isHovered)
            .animation(KissmarkMotion.snappy(reduceMotion: reduceMotion), value: active)
        }
        .buttonStyle(KissmarkPressButtonStyle(pressedScale: KissmarkMotion.pressedScale))
        .disabled(disabled)
        .onHover { isHovered = $0 && !disabled }
        .kissmarkTapTarget()
        .contentShape(Rectangle())
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        #if os(macOS)
        .kissmarkHoverHint(Text(title))
        #else
        .help(Text(title))
        #endif
    }
}

/// Plain chrome button that dips to `pressedScale` while pressed. Disabled buttons
/// and Reduce Motion keep the label still.
private struct KissmarkPressButtonStyle: ButtonStyle {
    let pressedScale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        PressedLabel(configuration: configuration, pressedScale: pressedScale)
    }

    private struct PressedLabel: View {
        let configuration: ButtonStyleConfiguration
        let pressedScale: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var isDipped: Bool { configuration.isPressed && isEnabled && !reduceMotion }

        var body: some View {
            configuration.label
                .scaleEffect(isDipped ? pressedScale : 1)
                .animation(KissmarkMotion.snappy(reduceMotion: reduceMotion), value: isDipped)
        }
    }
}

struct KissmarkActionButton: View {
    let title: LocalizedStringKey
    var icon: KissmarkLucide?
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let icon {
                Label {
                    Text(title)
                } icon: {
                    KissmarkLucideImage(icon: icon, pointSize: KissmarkMetrics.treeIconSize)
                }
            } else {
                Text(title)
            }
        }
        .modifier(ActionButtonStyleModifier(prominent: prominent))
        .disabled(disabled)
        .kissmarkTapTarget()
    }

    private struct ActionButtonStyleModifier: ViewModifier {
        let prominent: Bool

        func body(content: Content) -> some View {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

struct KissmarkEmptyState: View {
    let icon: KissmarkLucide
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var actionIcon: KissmarkLucide?
    var actionAccessibilityIdentifier: String?
    var action: (() -> Void)?
    @State private var hasEntered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: KissmarkMetrics.emptyStateIconTitleGap) {
                KissmarkLucideImage(icon: icon, pointSize: KissmarkMetrics.emptyStateIconSize)
                    .foregroundStyle(.secondary)
                    .modifier(entrance(0))
                Text(title)
                    .font(KissmarkType.font(.title2, weight: .semibold))
                    .modifier(entrance(1))
            }

            Text(message)
                .font(KissmarkType.font(.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: KissmarkMetrics.emptyStateMaxTextWidth)
                .padding(.top, KissmarkMetrics.emptyStateTitleBodyGap)
                .modifier(entrance(2))

            if let actionTitle, let action {
                KissmarkActionButton(
                    title: actionTitle,
                    icon: actionIcon,
                    prominent: true,
                    action: action
                )
                .accessibilityIdentifier(actionAccessibilityIdentifier ?? "")
                .padding(.top, KissmarkMetrics.emptyStateBodyActionGap)
                .modifier(entrance(3))
            }
        }
        .onAppear { hasEntered = true }
    }

    private func entrance(_ index: Int) -> KissmarkEntranceModifier {
        KissmarkEntranceModifier(index: index, hasEntered: hasEntered, reduceMotion: reduceMotion)
    }
}

/// Staggered entrance: rises from `entranceRise` and resolves from `entranceBlur`;
/// Reduce Motion keeps the fade only.
private struct KissmarkEntranceModifier: ViewModifier {
    let index: Int
    let hasEntered: Bool
    let reduceMotion: Bool

    private var isResting: Bool { hasEntered || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(hasEntered ? 1 : 0)
            .offset(y: isResting ? 0 : KissmarkMotion.entranceRise)
            .blur(radius: isResting ? 0 : KissmarkMotion.entranceBlur)
            .animation(KissmarkMotion.entrance(index: index, reduceMotion: reduceMotion), value: hasEntered)
    }
}

/// Icon-only toolbar row; collapses to a single `>` control when narrow.
struct KissmarkToolbarCluster: View {
    struct Item: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let icon: KissmarkChromeIcon
        var active: Bool = false
        var disabled: Bool = false
        var opticalScale: CGFloat = 1
        var accessibilityIdentifier: String?
        var accessibilityValue: String?
        let action: () -> Void
    }

    let items: [Item]
    var collapsesOverflow: Bool = false
    @State private var isOverflowPresented = false

    var body: some View {
        Group {
            if collapsesOverflow {
                overflowControl
            } else {
                iconRow
            }
        }
        // Pull the whole action package in from the trailing window edge.
        .padding(.trailing, KissmarkMetrics.toolbarActionsTrailingInset)
    }

    private var iconRow: some View {
        HStack(spacing: KissmarkMetrics.toolbarItemGap) {
            ForEach(items) { item in
                toolbarButton(item)
            }
        }
    }

    /// Narrow overflow for New · Lock · Archive · Close — one rotating `>` button.
    private var overflowControl: some View {
        KissmarkIconButton(
            title: "더보기",
            lucide: .chevronRight,
            opticalScale: KissmarkMetrics.toolbarChevronOpticalScale,
            rotation: .degrees(isOverflowPresented ? 90 : 0),
            accessibilityIdentifier: "toolbar-overflow-menu"
        ) {
            isOverflowPresented.toggle()
        }
        .accessibilityValue(Text(isOverflowPresented ? "expanded" : "collapsed"))
        .popover(isPresented: $isOverflowPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    Button {
                        item.action()
                        isOverflowPresented = false
                    } label: {
                        Label {
                            Text(item.title)
                        } icon: {
                            if case .lucide(let lucide) = item.icon {
                                KissmarkLucideImage(icon: lucide, pointSize: 15)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.disabled)
                }
            }
            .padding(6)
            .frame(minWidth: 168)
        }
    }

    @ViewBuilder
    private func toolbarButton(_ item: Item) -> some View {
        let button = KissmarkIconButton(
            title: item.title,
            icon: item.icon,
            disabled: item.disabled,
            active: item.active,
            opticalScale: item.opticalScale,
            accessibilityIdentifier: item.accessibilityIdentifier ?? item.id,
            action: item.action
        )

        if let value = item.accessibilityValue {
            button.accessibilityValue(Text(value))
        } else {
            button
        }
    }
}

/// Plain sidebar show/hide — Lucide `panel-left`, not glass ≫.
struct KissmarkSidebarToggleButton: View {
    let isSidebarVisible: Bool
    let action: () -> Void

    var body: some View {
        KissmarkIconButton(
            title: isSidebarVisible ? "사이드바 숨기기" : "사이드바 보기",
            lucide: .panelLeft,
            opticalScale: KissmarkMetrics.toolbarPanelOpticalScale,
            accessibilityIdentifier: "sidebar-toggle-button",
            action: action
        )
        .accessibilityValue(Text(isSidebarVisible ? "visible" : "hidden"))
    }
}

/// Filename field; locked in Read Mode, renamable in Edit Mode.
struct KissmarkFilenameField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isEditable: Bool = true
    var minWidth: CGFloat = KissmarkMetrics.toolbarTitleMinWidth
    let onSubmit: () -> Void
    @Environment(\.chromePalette) private var chromePalette

    var body: some View {
        Group {
            if isEditable {
                TextField("파일 이름", text: $text)
                    .textFieldStyle(.plain)
                    .font(KissmarkType.font(.headline, weight: KissmarkType.chromeTitleWeight))
                    .lineLimit(1)
                    .focused(isFocused)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier("document-title-field")
                    .help(Text("문서 이름 바꾸기"))
            } else {
                Text(text.isEmpty ? String.kissmarkLocalized("제목 없음") : text)
                    .font(KissmarkType.font(.headline, weight: KissmarkType.chromeTitleWeight))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("document-title-field")
                    .help(Text("잠금을 풀어 이름을 바꾸세요"))
            }
        }
        .frame(
            minWidth: minWidth,
            idealWidth: 280,
            maxWidth: 480,
            alignment: .leading
        )
        .layoutPriority(1)
        .foregroundStyle(chromePalette?.chromePrimary ?? .primary)
    }
}

#if os(macOS)
extension View {
    /// Small anchored explanation for an icon-only macOS chrome control, shown after
    /// `KissmarkMotion.hoverHintDelay` in place of the system `.help` tooltip's long
    /// delay. It lives in a borderless, mouse-transparent child window, so the
    /// sidebar lane's clipping, the window edge, and the Document web view cannot
    /// cut it off; it takes no clicks or focus and also explains disabled controls.
    /// VoiceOver keeps reading the control's own accessibility label.
    func kissmarkHoverHint(_ title: Text) -> some View {
        modifier(KissmarkHoverHintModifier(title: title))
    }
}

private struct KissmarkHoverHintModifier: ViewModifier {
    let title: Text
    @Environment(\.chromePalette) private var chromePalette

    func body(content: Content) -> some View {
        content.background(
            KissmarkHoverHintAnchor(label: KissmarkHoverHintLabel(title: title, palette: chromePalette))
        )
    }
}

private struct KissmarkHoverHintLabel: View {
    let title: Text
    let palette: ThemePalette?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KissmarkMetrics.hoverHintRadius, style: .continuous)
        title
            .font(KissmarkType.font(.caption))
            .environment(\.locale, KissmarkLocalization.locale)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(palette?.chromePrimary ?? Color(nsColor: .labelColor))
            .padding(.horizontal, KissmarkMetrics.hoverHintInlineInset)
            .padding(.vertical, KissmarkMetrics.hoverHintBlockInset)
            .background {
                shape.fill(palette?.chromeElevatedBackground ?? Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                shape.strokeBorder(
                    palette?.chromeBorder ?? Color(nsColor: .separatorColor),
                    lineWidth: KissmarkMetrics.iconButtonOutlineWidth
                )
            }
            .accessibilityHidden(true)
    }
}

/// Follows the pointer over its control with an `NSTrackingArea` (which fires for
/// disabled controls too) and never takes part in hit testing.
private struct KissmarkHoverHintAnchor: NSViewRepresentable {
    let label: KissmarkHoverHintLabel

    final class AnchorView: NSView {
        var label: KissmarkHoverHintLabel? {
            didSet { KissmarkHoverHintPresenter.shared.refresh(self) }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func mouseEntered(with event: NSEvent) {
            KissmarkHoverHintPresenter.shared.hover(self)
        }

        override func mouseExited(with event: NSEvent) {
            KissmarkHoverHintPresenter.shared.unhover(self)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                KissmarkHoverHintPresenter.shared.unhover(self)
            }
        }
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        view.label = label
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.label = label
    }
}

/// One shared hint window: only one control is hovered at a time. Any click, key,
/// scroll, or app switch hides it until the pointer enters a control again.
private final class KissmarkHoverHintPresenter {
    static let shared = KissmarkHoverHintPresenter()

    private weak var anchor: KissmarkHoverHintAnchor.AnchorView?
    private var pendingShow: Task<Void, Never>?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<KissmarkHoverHintLabel>?
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// Whether a hint is shown (the panel stays `isVisible` while it fades out).
    private var isShown = false
    /// Final frame of the shown hint.
    private var shownFrame: NSRect?
    /// Bumped by every show and hide so a finished fade-out never orders out a newer hint.
    private var generation = 0
    /// Uptime when a shown hint closed because the pointer left its control.
    private var warmSince: TimeInterval?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func hover(_ view: KissmarkHoverHintAnchor.AnchorView) {
        pendingShow?.cancel()
        let isWarm = warmSince.map {
            ProcessInfo.processInfo.systemUptime - $0 < KissmarkMotion.hoverHintWarmWindow
        } ?? false
        warmSince = nil
        anchor = view
        installDismissTriggers()
        // Subsequent hints right after one closed appear at once, without an entrance.
        if isWarm {
            present(view, animated: false)
            return
        }
        hidePanel()
        pendingShow = Task { [weak self, weak view] in
            try? await Task.sleep(for: .seconds(KissmarkMotion.hoverHintDelay))
            guard !Task.isCancelled, let self, let view, self.anchor === view else { return }
            self.present(view, animated: true)
        }
    }

    func unhover(_ view: KissmarkHoverHintAnchor.AnchorView) {
        guard anchor === view else { return }
        let wasShown = isShown
        dismiss()
        if wasShown { warmSince = ProcessInfo.processInfo.systemUptime }
    }

    /// Re-renders a visible hint when its control's title changes (e.g. the sidebar toggle).
    func refresh(_ view: KissmarkHoverHintAnchor.AnchorView) {
        guard anchor === view, isShown else { return }
        present(view, animated: false)
    }

    private func present(_ view: KissmarkHoverHintAnchor.AnchorView, animated: Bool) {
        guard let window = view.window,
              let label = view.label,
              NSEvent.pressedMouseButtons == 0 else { return }
        let panel = self.panel ?? makePanel()
        let hostingView: NSHostingView<KissmarkHoverHintLabel>
        if let existing = self.hostingView {
            existing.rootView = label
            hostingView = existing
        } else {
            hostingView = NSHostingView(rootView: label)
            hostingView.sizingOptions = [.intrinsicContentSize]
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        panel.appearance = window.effectiveAppearance

        // Below the control, centered; flipped above and clamped to the screen's
        // usable area so it is never cut off at a window or screen edge.
        let size = hostingView.fittingSize
        let anchorRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? window.frame
        let gap = KissmarkMetrics.hoverHintGap
        var origin = NSPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.minY - gap - size.height)
        // Screen y grows upward: below the control the hint rises from above, flipped
        // above it drops from below; either way it travels away from the control.
        var riseFromControl = KissmarkMotion.entranceRise
        if origin.y < visible.minY {
            origin.y = anchorRect.maxY + gap
            riseFromControl = -KissmarkMotion.entranceRise
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        let frame = NSRect(origin: origin, size: size)
        let entersAnimated = animated && !isShown
        // A re-render of the same hint in place must not cut its entrance short.
        let isUnchanged = isShown && shownFrame == frame
        let reduceMotion = self.reduceMotion
        generation += 1
        isShown = true
        shownFrame = frame

        if entersAnimated {
            panel.alphaValue = 0
            panel.setFrame(
                reduceMotion ? frame : frame.offsetBy(dx: 0, dy: riseFromControl),
                display: true
            )
        } else if !isUnchanged {
            // Supersedes a running fade or rise; a plain assignment can lose to the animator.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        }

        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        } else {
            panel.orderFront(nil)
        }
        panel.invalidateShadow()

        guard entersAnimated else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? KissmarkMotion.reducedFadeDuration : KissmarkMotion.quickDuration
            let curve = KissmarkMotion.easeOutControlPoints
            context.timingFunction = CAMediaTimingFunction(controlPoints: curve.0, curve.1, curve.2, curve.3)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func dismiss() {
        pendingShow?.cancel()
        pendingShow = nil
        anchor = nil
        warmSince = nil
        hidePanel()
        removeDismissTriggers()
    }

    private func hidePanel() {
        guard let panel, isShown else { return }
        isShown = false
        generation += 1
        let hidingGeneration = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? KissmarkMotion.reducedFadeDuration : KissmarkMotion.quickDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                KissmarkHoverHintPresenter.shared.finishHiding(hidingGeneration)
            }
        }
    }

    /// Orders the faded-out panel away unless a newer hint took it over during the fade.
    private func finishHiding(_ hidingGeneration: Int) {
        guard hidingGeneration == generation, let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func installDismissTriggers() {
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
            ) { event in
                MainActor.assumeIsolated { KissmarkHoverHintPresenter.shared.dismiss() }
                return event
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { KissmarkHoverHintPresenter.shared.dismiss() }
            }
        }
    }

    private func removeDismissTriggers() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }
}
#endif
