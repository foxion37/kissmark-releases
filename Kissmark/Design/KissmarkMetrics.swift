import SwiftUI

private enum KissmarkSpacing {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
}

/// Platform size tokens aligned with Apple HIG (Mac / iPad / iPhone).
enum KissmarkMetrics {
    static let minimumWindowWidth: CGFloat = 430
    static let minimumWindowHeight: CGFloat = 600

    /// Minimum interactive target (HIG).
    static let minTapTarget: CGFloat = 44

    static let settingsMinimumSize = CGSize(width: 560, height: 440)
    static let settingsContentMaxWidth: CGFloat = 680
    /// One readable column, with room for longer panes to scroll.
    static let settingsDefaultSize = CGSize(width: settingsContentMaxWidth, height: 600)
    static let settingsRowGap = KissmarkSpacing.space8
    static let settingsConnectionTextGap = KissmarkSpacing.space4
    static let settingsSheetInset = KissmarkSpacing.space20
    static let iconButtonOutlineWidth: CGFloat = 1
    static let iconButtonOutlineOpacity: CGFloat = 0.35
    static let iconButtonHoverOpacity: CGFloat = 0.06
    static let themeSwatchSize: CGFloat = 14
    static let settingsThemeRowVerticalInset = KissmarkSpacing.space8
    /// Compact Settings slider: full-width track, five non-interactive reference marks.
    static let settingsSliderRowGap = KissmarkSpacing.space4
    static let settingsSliderTrackInset: CGFloat = 10
    static let settingsSliderHeight: CGFloat = 24
    static let settingsSliderTrackHeight: CGFloat = 4
    static let settingsSliderCheckpointWidth: CGFloat = 12
    static let settingsSliderCheckpointHeight: CGFloat = 10
    static let settingsSliderTrackBaseOpacity: Double = 0.16
    static let settingsSliderTrackFillOpacity: Double = 0.65
    static let settingsSliderLegendHeight: CGFloat = 24
    static let settingsSliderLegendLift = KissmarkSpacing.space4
    static let settingsSliderLegendLabelWidth: CGFloat = 64
    static let frontmatterInset: CGFloat = 12

    static let toolbarButtonSize: CGFloat = 28

    static var toolbarIconPointSize: CGFloat {
        KissmarkIdiom.current == .mac ? 15 : 18
    }

    static let toolbarItemGap = KissmarkSpacing.space12

    /// Filename field never shrinks below this (leading-aligned, wide layout).
    static let toolbarTitleMinWidth: CGFloat = 180

    /// Filename min width when the action cluster is already a single `>`.
    static let toolbarTitleCompactMinWidth: CGFloat = 120

    static let toolbarActionsReserveWidth: CGFloat = 148

    static let toolbarOverflowPopoverMinWidth: CGFloat = 180

    /// Per-glyph optical scales (1.5): fitted from measured ink volume so dense
    /// glyphs (lock, archive, settings) read at the same visual weight as sparse
    /// ones. Bounded by the design system's 0.9-1.1 optical range.
    static let toolbarPlusOpticalScale: CGFloat = 1.1
    static let toolbarArchiveOpticalScale: CGFloat = 0.9
    static let toolbarCloseOpticalScale: CGFloat = 1.1
    static let toolbarLockOpticalScale: CGFloat = 0.9
    static let toolbarSettingsOpticalScale: CGFloat = 0.9
    static let toolbarPanelOpticalScale: CGFloat = 0.95
    static let toolbarChevronOpticalScale: CGFloat = 1.1

    /// Pull the trailing action cluster in from the window edge.
    static let toolbarActionsTrailingInset = KissmarkSpacing.space12

    static var treeRowHeight: CGFloat {
        KissmarkIdiom.current == .mac ? 28 : minTapTarget
    }

    static let sidebarHeaderHeight: CGFloat = 44
    static let sidebarDividerHitWidth: CGFloat = 8
    /// Visible divider line while the resize handle is hovered or dragged (drawn
    /// over the 1pt separator; layout keeps `sidebarDividerWidth`).
    static let sidebarDividerHighlightWidth: CGFloat = 2
    static let sidebarInset = KissmarkSpacing.space12
    static let sidebarSectionGap = KissmarkSpacing.space8
    static let treeRowInlineInset = KissmarkSpacing.space4
    static let treeIndent = KissmarkSpacing.space16
    static let disclosureSlotSize: CGFloat = 16
    static let disclosureGlyphSize: CGFloat = 12
    static let treeIconSize: CGFloat = 16
    static let disclosureIconGap = KissmarkSpacing.space4
    static let iconLabelGap = KissmarkSpacing.space8
    static let treeSelectionRadius: CGFloat = 6
    static let treeHoverOpacity: CGFloat = 0.055
    static let treeSelectionOpacity: CGFloat = 0.18

    /// FolderControl height: the outline-only control matches the icon-button circle.
    static let folderControlHeight: CGFloat = toolbarButtonSize

    static let folderControlInlineInset = KissmarkSpacing.space12
    static let folderControlRadius: CGFloat = 8
    static let folderControlIconSize: CGFloat = 16
    static let folderControlSwitchIconSize: CGFloat = 14

    /// macOS hover hint: small anchored label under an icon-only chrome control.
    static let hoverHintGap = KissmarkSpacing.space4
    static let hoverHintInlineInset = KissmarkSpacing.space8
    static let hoverHintBlockInset = KissmarkSpacing.space4
    static let hoverHintRadius: CGFloat = 6

    // MARK: Document column
    //
    // The Document reading column lives in `reader.css`; these two numbers are the
    // same measurements in points at text scale 1, so Swift can size the launch
    // window to the column. Changing one side means changing the other:
    // `--km-line-width-base` (the text measure, ≥600px viewport) and `--km-pad-x`
    // (one side's padding). The column box is `measure + 2 × padding`.

    /// Default Document text measure in points at text scale 1 (`45rem` at the 16px root).
    static let defaultDocumentMeasure: CGFloat = 720

    /// One CSS `ch` at text scale 1 when 장폭 is overridden in `ch`: the column box
    /// resolves it at the 16px root, where Pretendard's "0" advances 0.5596em.
    static let documentMeasureChWidth: CGFloat = 16 * 0.5596

    /// One side's horizontal Document padding in points at text scale 1 (`1.75rem`).
    static let defaultDocumentHorizontalPadding: CGFloat = 28

    /// Air the launch window keeps on each side of the Document column. Crepe's block
    /// handle floats at the text's left edge in Edit Mode — two 32pt items plus their
    /// 2pt gap — so `padding + slack` must hold 66pt or the `+` (slash) item falls off
    /// screen. Not scaled by Text Size: the handle is fixed pixels while the padding
    /// inside the column already scales with the root rem.
    static let documentColumnSlack: CGFloat = 40

    /// Launch content height; the Document column math only decides the width.
    static let defaultWindowContentHeight: CGFloat = 720

    /// Sidebar column plus its 1pt separator, between the window edge and the Document column.
    static let sidebarDividerWidth: CGFloat = 1

    static let emptyStateIconSize: CGFloat = 32
    static let emptyStateMaxTextWidth: CGFloat = 360
    static let emptyStateIconTitleGap = KissmarkSpacing.space12
    static let emptyStateTitleBodyGap = KissmarkSpacing.space8
    static let emptyStateBodyActionGap = KissmarkSpacing.space20

    /// Collapse New·Lock·Archive·Close into plain `>` early enough that AppKit
    /// never needs its own glass `>>` overflow (filename stays on screen).
    static let toolbarOverflowWidth: CGFloat = 760

    /// Phone stacks Folder then Document; overflow earlier than iPad/Mac.
    static var phoneToolbarOverflowWidth: CGFloat { 520 }

    static let sidebarAutoCollapseWidth: CGFloat = 580

    private static var currentIdiom: KissmarkIdiom { KissmarkIdiom.current }

    /// Readable document column (points). Fluid with window — not a cramped 40rem.
    static func documentMaxWidth(horizontalSizeClass: UserInterfaceSizeClass?, idiom: KissmarkIdiom) -> CGFloat {
        switch idiom {
        case .phone:
            return .infinity
        case .pad:
            return horizontalSizeClass == .compact ? .infinity : 950
        case .mac:
            return 1230
        }
    }

    static func documentPadding(idiom: KissmarkIdiom) -> CGFloat {
        switch idiom {
        case .phone: return KissmarkSpacing.space16
        case .pad: return KissmarkSpacing.space24
        case .mac: return KissmarkSpacing.space32
        }
    }

    static func chromePadding(idiom: KissmarkIdiom) -> CGFloat {
        switch idiom {
        case .phone: return KissmarkSpacing.space16
        case .pad: return KissmarkSpacing.space20
        case .mac: return KissmarkSpacing.space20
        }
    }

    static func sidebarWidth(idiom: KissmarkIdiom) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch idiom {
        case .phone:
            return (0, 0, 0)
        case .pad:
            return (240, 280, 360)
        case .mac:
            return (220, 260, 360)
        }
    }

    static func sectionSpacing(idiom: KissmarkIdiom) -> CGFloat {
        switch idiom {
        case .phone: return KissmarkSpacing.space12
        case .pad: return KissmarkSpacing.space16
        case .mac: return KissmarkSpacing.space12
        }
    }

    /// The user's stored sidebar width clamped into the idiom's limits.
    static func clampedSidebarWidth(_ width: CGFloat, idiom: KissmarkIdiom = .current) -> CGFloat {
        let limits = sidebarWidth(idiom: idiom)
        return min(max(width, limits.min), limits.max)
    }

    /// Document text measure in points at text scale 1: the 장폭 override (`ch`,
    /// clamped like the CSS) or the default.
    static func documentMeasure(_ design: DesignOverrides) -> CGFloat {
        guard let ch = design.spacing.measureCh else { return defaultDocumentMeasure }
        let range = DesignOverrides.measureRange
        return CGFloat(min(max(ch, range.lowerBound), range.upperBound)) * documentMeasureChWidth
    }

    /// Document column box width at a text-size multiplier
    /// (`(measure + 2 × padding) × scale`) — the same box `reader.css` clamps.
    static func documentColumnWidth(textScale: Double, measure: CGFloat = defaultDocumentMeasure) -> CGFloat {
        (measure + 2 * defaultDocumentHorizontalPadding) * CGFloat(textScale)
    }
}

/// One motion family shared by SwiftUI chrome and the Document surface
/// (`reader.css` mirrors every value as `--km-dur-*` / `--km-spring*`):
/// springs for anything that moves or resizes, short ease-out fades for
/// feedback, one slower crossfade for palette changes. Reduce Motion keeps
/// only short opacity changes: no travel, scale, rotation, or blur.
enum KissmarkMotion {
    /// Hover washes, press release, hover hints, small label crossfades.
    static let quickDuration: Double = 0.16
    /// Chevrons, check marks, selection: `.snappy` spring response.
    static let standardDuration: Double = 0.24
    /// Sidebar, accordions, rows, entrances: critically damped `.smooth` spring response.
    static let spatialDuration: Double = 0.38
    /// Theme / accent / appearance crossfade, chrome and Document together.
    static let themeDuration: Double = 0.42
    static let reducedFadeDuration: Double = 0.12
    /// Hover time before a macOS chrome hover hint appears (replaces the ~1s `.help` delay).
    static let hoverHintDelay: Double = 0.1
    /// After a hint closes, the next control within this window explains itself at once.
    static let hoverHintWarmWindow: Double = 0.6
    /// Gap between staggered siblings entering together (empty state, Document blocks).
    static let staggerDelay: Double = 0.04
    /// Distance an entering element rises from, and the blur it resolves from.
    static let entranceRise: CGFloat = 6
    static let entranceBlur: CGFloat = 4
    /// Pressed icon button (small targets need a visible dip).
    static let pressedScale: CGFloat = 0.92
    /// Pressed wide control (FolderControl): a smaller dip for a larger surface.
    static let pressedWideScale: CGFloat = 0.98
    /// Starting scale of a popping mark (theme check, hover hint).
    static let popScale: CGFloat = 0.9
    /// The one ease-out curve (`--km-ease-out` in reader.css), for AppKit animators.
    static let easeOutControlPoints: (Float, Float, Float, Float) = (0.23, 1, 0.32, 1)

    /// Moves and resizes (sidebar, rows, selection glide, accordions). Reduce Motion → instant.
    static func spring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: spatialDuration)
    }

    /// Small state changes (chevrons, check marks, active outlines). Reduce Motion → short fade.
    static func snappy(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: reducedFadeDuration) : .snappy(duration: standardDuration)
    }

    /// Feedback fades (hover wash, press release, label swaps).
    static func fade(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? reducedFadeDuration : quickDuration)
    }

    /// Palette changes: theme, accent, appearance. Matches the Document's view-transition crossfade.
    static func theme(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? reducedFadeDuration : themeDuration)
    }

    /// Document open / Read-Edit fade: a short ease-out, no movement. Reduce Motion → instant.
    static func documentOpen(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: quickDuration)
    }

    /// Staggered entrance for the `index`-th sibling. Reduce Motion → one short fade, no stagger.
    static func entrance(index: Int, reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: reducedFadeDuration)
            : .smooth(duration: spatialDuration).delay(Double(index) * staggerDelay)
    }

    static let documentSurfaceFadeDelayNanoseconds: UInt64 = 16_000_000
    static let documentSurfaceTransitionOpacity = 0.88
}

enum KissmarkIdiom {
    case phone
    case pad
    case mac

    static var current: KissmarkIdiom {
        #if os(macOS)
        return .mac
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #endif
    }
}

extension EnvironmentValues {
    var kissmarkIdiom: KissmarkIdiom {
        KissmarkIdiom.current
    }
}

/// Tracks host window / split-view width for Notes-style toolbar collapse.
struct KissmarkWindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

