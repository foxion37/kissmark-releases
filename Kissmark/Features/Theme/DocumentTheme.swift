import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A Document color palette (upstream theme values). It also drives the whole
/// main-window chrome when a non-system theme is chosen; `nil`
/// (`DocumentTheme.system`) means "follow the system window colors" (ADR 0021).
nonisolated struct ThemePalette: Equatable {
    let bg: String
    let bgElevated: String
    let codeBg: String
    let codeFg: String
    let text: String
    let muted: String
    let border: String
    let accent: String
    let danger: String
    let success: String
    let warn: String
}

/// One resolver for SwiftUI chrome colors from the selected `DocumentTheme`:
/// when a non-system theme is chosen, the whole main window — action bar,
/// sidebar, tree, separators, selection highlight, title text, icon buttons, and
/// window background — uses the theme palette resolved for the Appearance scheme.
/// `nil` (시스템) keeps the system chrome unchanged (ADR 0021).
extension ThemePalette {
    var chromeBackground: Color { Color(kissmarkHex: bg) ?? .clear }
    var chromeElevatedBackground: Color { Color(kissmarkHex: bgElevated) ?? .clear }
    var chromePrimary: Color { Color(kissmarkHex: text) ?? .primary }
    var chromeMuted: Color { Color(kissmarkHex: muted) ?? .secondary }
    var chromeBorder: Color { Color(kissmarkHex: border) ?? .clear }
    var chromeAccentSoft: Color { Color(kissmarkHex: DocumentThemeResolver.blend(accent, over: bg, ratio: 0.14)) ?? .accentColor }
}

private struct ChromePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette? = nil
}

extension EnvironmentValues {
    /// The theme palette for the whole main window, or `nil` to follow the system.
    var chromePalette: ThemePalette? {
        get { self[ChromePaletteKey.self] }
        set { self[ChromePaletteKey.self] = newValue }
    }
}

extension View {
    /// A separator that follows the window theme when one is set.
    @ViewBuilder
    func kissmarkChromeDivider(_ palette: ThemePalette?) -> some View {
        if let palette {
            Divider().background(palette.chromeBorder)
        } else {
            Divider()
        }
    }
}

/// Document theme. The stored case is the user's pick; `variant(for:)` and
/// `palette(for:)` adapt it to the Appearance scheme. Palette sources are
/// recorded below; the Monokai Light adaptation is explicitly labelled.
nonisolated enum DocumentTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case catppuccinLatte
    case catppuccinFrappe
    case catppuccinMacchiato
    case catppuccinMocha
    case dracula
    case nord
    case gruvboxLight
    case gruvboxDark
    case solarizedLight
    case solarizedDark
    case oneDark
    case tokyoNight
    case rosePine
    case monokai

    static let storageKey = "kissmark.theme"

    var id: String { rawValue }

    /// The name of the theme as shown in `scheme` (adaptive themes name their Light sibling).
    func displayName(for scheme: ColorScheme) -> LocalizedStringKey {
        let shown = variant(for: scheme)
        if scheme == .light {
            switch shown {
            case .dracula: return "Dracula Alucard"
            case .nord: return "Nord Snow Storm"
            case .oneDark: return "One Light"
            case .tokyoNight: return "Tokyo Night Day"
            case .rosePine: return "Rosé Pine Dawn"
            case .monokai: return "Monokai Light (Kissmark 조정)"
            default: break
            }
        }
        switch shown {
        case .system: return "시스템"
        case .catppuccinLatte: return "Catppuccin Latte"
        case .catppuccinFrappe: return "Catppuccin Frappé"
        case .catppuccinMacchiato: return "Catppuccin Macchiato"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .gruvboxLight: return "Gruvbox Light"
        case .gruvboxDark: return "Gruvbox Dark"
        case .solarizedLight: return "Solarized Light"
        case .solarizedDark: return "Solarized Dark"
        case .oneDark: return "One Dark"
        case .tokyoNight: return "Tokyo Night"
        case .rosePine: return "Rosé Pine"
        case .monokai: return "Monokai"
        }
    }

    /// The palette written for this exact case; Light variants of dark-only themes
    /// live in `adaptiveLightPalette`.
    private var nativePalette: ThemePalette? {
        switch self {
        case .system:
            nil
        // https://catppuccin.com/palette
        case .catppuccinLatte:
            ThemePalette(
                bg: "#EFF1F5", bgElevated: "#CCD0DA", codeBg: "#E6E9EF", codeFg: "#4C4F69",
                text: "#4C4F69", muted: "#6C6F85", border: "#ACB0BE",
                accent: "#1E66F5", danger: "#D20F39", success: "#40A02B", warn: "#DF8E1D"
            )
        case .catppuccinFrappe:
            ThemePalette(
                bg: "#303446", bgElevated: "#414559", codeBg: "#292C3C", codeFg: "#C6D0F5",
                text: "#C6D0F5", muted: "#A5ADCE", border: "#626880",
                accent: "#8CAAEE", danger: "#E78284", success: "#A6D189", warn: "#E5C890"
            )
        case .catppuccinMacchiato:
            ThemePalette(
                bg: "#24273A", bgElevated: "#363A4F", codeBg: "#1E2030", codeFg: "#CAD3F5",
                text: "#CAD3F5", muted: "#A5ADCB", border: "#5B6078",
                accent: "#8AADF4", danger: "#ED8796", success: "#A6DA95", warn: "#EED49F"
            )
        case .catppuccinMocha:
            ThemePalette(
                bg: "#1E1E2E", bgElevated: "#313244", codeBg: "#181825", codeFg: "#CDD6F4",
                text: "#CDD6F4", muted: "#A6ADC8", border: "#585B70",
                accent: "#89B4FA", danger: "#F38BA8", success: "#A6E3A1", warn: "#F9E2AF"
            )
        // https://draculatheme.com/contribute
        case .dracula:
            ThemePalette(
                bg: "#282A36", bgElevated: "#44475A", codeBg: "#21222C", codeFg: "#F8F8F2",
                text: "#F8F8F2", muted: "#6272A4", border: "#44475A",
                accent: "#BD93F9", danger: "#FF5555", success: "#50FA7B", warn: "#F1FA8C"
            )
        // https://www.nordtheme.com/docs/colors-and-palettes
        case .nord:
            ThemePalette(
                bg: "#2E3440", bgElevated: "#3B4252", codeBg: "#3B4252", codeFg: "#D8DEE9",
                text: "#D8DEE9", muted: "#4C566A", border: "#434C5E",
                accent: "#88C0D0", danger: "#BF616A", success: "#A3BE8C", warn: "#EBCB8B"
            )
        // https://github.com/morhetz/gruvbox
        case .gruvboxLight:
            ThemePalette(
                bg: "#FBF1C7", bgElevated: "#F2E5BC", codeBg: "#EBDBB2", codeFg: "#3C3836",
                text: "#3C3836", muted: "#7C6F64", border: "#D5C4A1",
                accent: "#076678", danger: "#9D0006", success: "#79740E", warn: "#B57614"
            )
        case .gruvboxDark:
            ThemePalette(
                bg: "#282828", bgElevated: "#3C3836", codeBg: "#32302F", codeFg: "#EBDBB2",
                text: "#EBDBB2", muted: "#A89984", border: "#504945",
                accent: "#458588", danger: "#CC241D", success: "#98971A", warn: "#D79921"
            )
        // https://ethanschoonover.com/solarized
        case .solarizedLight:
            ThemePalette(
                bg: "#FDF6E3", bgElevated: "#EEE8D5", codeBg: "#EEE8D5", codeFg: "#586E75",
                text: "#657B83", muted: "#93A1A1", border: "#EEE8D5",
                accent: "#268BD2", danger: "#DC322F", success: "#859900", warn: "#B58900"
            )
        case .solarizedDark:
            ThemePalette(
                bg: "#002B36", bgElevated: "#073642", codeBg: "#073642", codeFg: "#93A1A1",
                text: "#93A1A1", muted: "#657B83", border: "#586E75",
                accent: "#268BD2", danger: "#DC322F", success: "#859900", warn: "#B58900"
            )
        // https://github.com/joshdick/onedark.vim
        case .oneDark:
            ThemePalette(
                bg: "#282C34", bgElevated: "#2C323C", codeBg: "#21252B", codeFg: "#ABB2BF",
                text: "#ABB2BF", muted: "#5C6370", border: "#3E4451",
                accent: "#61AFEF", danger: "#E06C75", success: "#98C379", warn: "#E5C07B"
            )
        // https://github.com/enkia/tokyo-night-vscode-theme
        case .tokyoNight:
            ThemePalette(
                bg: "#1A1B26", bgElevated: "#292E42", codeBg: "#16161E", codeFg: "#C0CAF5",
                text: "#C0CAF5", muted: "#565F89", border: "#414868",
                accent: "#7AA2F7", danger: "#F7768E", success: "#9ECE6A", warn: "#E0AF68"
            )
        // https://rosepinetheme.com/palette
        case .rosePine:
            ThemePalette(
                bg: "#191724", bgElevated: "#1F1D2E", codeBg: "#26233A", codeFg: "#E0DEF4",
                text: "#E0DEF4", muted: "#6E6A86", border: "#524F67",
                accent: "#C4A7E7", danger: "#EB6F92", success: "#9CCFD8", warn: "#F6C177"
            )
        // https://monokai.pro (classic Monokai scheme)
        case .monokai:
            ThemePalette(
                bg: "#272822", bgElevated: "#3E3D32", codeBg: "#1E1F1C", codeFg: "#F8F8F2",
                text: "#F8F8F2", muted: "#75715E", border: "#49483E",
                accent: "#A6E22E", danger: "#F92672", success: "#A6E22E", warn: "#E6DB74"
            )
        }
    }

    /// Light counterparts for themes that only ship a dark palette. Values come from
    /// each theme's own light sibling; the Monokai one is a Kissmark adaptation.
    private var adaptiveLightPalette: ThemePalette? {
        switch self {
        // Alucard Classic: https://draculatheme.com/spec (UI Color Palette for surfaces)
        case .dracula:
            ThemePalette(
                bg: "#FFFBEB", bgElevated: "#EFEDDC", codeBg: "#ECE9DF", codeFg: "#1F1F1F",
                text: "#1F1F1F", muted: "#6C664B", border: "#CECCC0",
                accent: "#644AC9", danger: "#CB3A2A", success: "#14710A", warn: "#846E15"
            )
        // Snow Storm (bright ambiance): https://www.nordtheme.com/docs/colors-and-palettes
        case .nord:
            ThemePalette(
                bg: "#ECEFF4", bgElevated: "#E5E9F0", codeBg: "#E5E9F0", codeFg: "#2E3440",
                text: "#2E3440", muted: "#4C566A", border: "#D8DEE9",
                accent: "#5E81AC", danger: "#BF616A", success: "#A3BE8C", warn: "#EBCB8B"
            )
        // Atom One Light syntax + UI: https://github.com/atom/atom/tree/master/packages/one-light-syntax
        // and https://github.com/atom/atom/tree/master/packages/one-light-ui (hsl values converted to hex)
        case .oneDark:
            ThemePalette(
                bg: "#FAFAFA", bgElevated: "#EAEBEB", codeBg: "#EAEBEB", codeFg: "#383A42",
                text: "#383A42", muted: "#696C77", border: "#DBDBDC",
                accent: "#4078F2", danger: "#E45649", success: "#50A14F", warn: "#B76B01"
            )
        // Tokyo Night Day: https://github.com/folke/tokyonight.nvim/blob/main/extras/lua/tokyonight_day.lua
        case .tokyoNight:
            ThemePalette(
                bg: "#E1E2E7", bgElevated: "#C4C8DA", codeBg: "#D0D5E3", codeFg: "#3760BF",
                text: "#3760BF", muted: "#68709A", border: "#B4B5B9",
                accent: "#2E7DE9", danger: "#F52A65", success: "#587539", warn: "#8C6C3E"
            )
        // Rosé Pine Dawn: https://rosepinetheme.com/palette
        case .rosePine:
            ThemePalette(
                bg: "#FAF4ED", bgElevated: "#FFFAF3", codeBg: "#F2E9E1", codeFg: "#464261",
                text: "#464261", muted: "#797593", border: "#DFDAD9",
                accent: "#907AA9", danger: "#B4637A", success: "#56949F", warn: "#EA9D34"
            )
        // Kissmark adaptation, NOT an official Monokai palette: classic Monokai's
        // background/comment inks on a warm paper, with its accent hues darkened for contrast.
        case .monokai:
            ThemePalette(
                bg: "#FAF8F0", bgElevated: "#EFEDE2", codeBg: "#EFEDE2", codeFg: "#272822",
                text: "#272822", muted: "#75715E", border: "#D6D3C4",
                accent: "#5F8F00", danger: "#C4145A", success: "#5F8F00", warn: "#8A7F1F"
            )
        default:
            nil
        }
    }

    /// The concrete theme shown in `scheme`. Paired themes swap sides (Latte ↔ the
    /// Catppuccin dark flavor, Gruvbox and Solarized Light ↔ Dark); a Catppuccin dark
    /// flavor falls back to Latte in Light, and Latte falls back to Mocha in Dark.
    /// Themes without a sibling stay and take `palette(for:)`'s Light variant.
    /// The stored raw value is never rewritten.
    func variant(for scheme: ColorScheme) -> DocumentTheme {
        switch (self, scheme) {
        case (.catppuccinLatte, .dark): .catppuccinMocha
        case (.catppuccinFrappe, .light), (.catppuccinMacchiato, .light), (.catppuccinMocha, .light): .catppuccinLatte
        case (.gruvboxLight, .dark): .gruvboxDark
        case (.gruvboxDark, .light): .gruvboxLight
        case (.solarizedLight, .dark): .solarizedDark
        case (.solarizedDark, .light): .solarizedLight
        default: self
        }
    }

    /// `nil` = follow the platform palette.
    func palette(for scheme: ColorScheme) -> ThemePalette? {
        let resolved = variant(for: scheme)
        if scheme == .light, let light = resolved.adaptiveLightPalette { return light }
        return resolved.nativePalette
    }

    /// One row per theme family in `scheme`: paired themes collapse to the side that is shown.
    static func choices(for scheme: ColorScheme) -> [DocumentTheme] {
        allCases.filter { $0.variant(for: scheme) == $0 }
    }
}

/// Turns the chosen theme (or the system palette) into the `--km-theme-*`
/// variables the Document surface stylesheet reads. `scheme` is the effective
/// Appearance scheme, shared with the native chrome so both always agree.
nonisolated enum DocumentThemeResolver {
    static let schemeKey = "--km-theme-scheme"

    /// The palette the whole app shows for `theme` in `scheme` (`system` = the platform palette).
    static func palette(theme: DocumentTheme, scheme: ColorScheme, system: ThemePalette) -> ThemePalette {
        theme.palette(for: scheme) ?? system
    }

    /// The exact chosen accent; an unset System theme keeps the platform tint.
    static func chromeAccentHex(theme: DocumentTheme, scheme: ColorScheme, override: String?) -> String? {
        validHex(override) ?? theme.palette(for: scheme)?.accent
    }

    static func cssVariables(
        theme: DocumentTheme,
        accentHex: String?,
        scheme: ColorScheme,
        system: ThemePalette
    ) -> [String: String] {
        let palette = Self.palette(theme: theme, scheme: scheme, system: system)
        let accent = validHex(accentHex) ?? palette.accent
        return [
            "--km-theme-bg": palette.bg,
            "--km-theme-bg-elevated": palette.bgElevated,
            "--km-theme-code-bg": palette.codeBg,
            "--km-theme-code-fg": palette.codeFg,
            "--km-theme-text": palette.text,
            "--km-theme-muted": palette.muted,
            "--km-theme-border": palette.border,
            "--km-theme-accent": accent,
            "--km-theme-accent-soft": blend(accent, over: palette.bg, ratio: 0.14),
            "--km-theme-danger": palette.danger,
            "--km-theme-success": palette.success,
            "--km-theme-warn": palette.warn,
            schemeKey: scheme == .dark ? "dark" : "light",
        ]
    }

    static func validHex(_ value: String?) -> String? {
        // Reuse the Stage 3 check: it rejects fullwidth "hex" digits, which
        // `Character.isHexDigit` would accept.
        guard let value, DesignOverrides.isHexColor(value) else { return nil }
        return value.uppercased()
    }

    /// Linear sRGB blend of `hex` over `background` at `ratio` (0...1).
    static func blend(_ hex: String, over background: String, ratio: Double) -> String {
        guard let fg = components(hex), let bg = components(background) else { return hex.uppercased() }
        let r = min(max(ratio, 0), 1)
        func mix(_ a: Double, _ b: Double) -> Int {
            min(max(Int((((a * r) + (b * (1 - r))) * 255).rounded()), 0), 255)
        }
        return String(format: "#%02X%02X%02X", mix(fg.0, bg.0), mix(fg.1, bg.1), mix(fg.2, bg.2))
    }

    private static func components(_ hex: String) -> (Double, Double, Double)? {
        guard let value = validHex(hex), let raw = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return (
            Double((raw >> 16) & 0xFF) / 255,
            Double((raw >> 8) & 0xFF) / 255,
            Double(raw & 0xFF) / 255
        )
    }

    /// "시스템" palette: the surface colors for the current Appearance, with dark
    /// body text pinned to `#FFFFFF` (ADR 0021).
    ///
    /// System colors carry alpha (`separatorColor` is white at ~10% in dark, and
    /// the label colors are translucent too), so every value is resolved as RGBA
    /// and composited over the window background. Without that, the dark
    /// separator reads as a pure-white border.
    static func systemPalette(for scheme: ColorScheme) -> ThemePalette {
        #if os(macOS)
        let background = hex(.windowBackgroundColor, scheme: scheme, over: "#000000")
        let elevated = hex(.controlBackgroundColor, scheme: scheme, over: background)
        let text = scheme == .dark ? "#FFFFFF" : hex(.labelColor, scheme: scheme, over: background)
        return ThemePalette(
            bg: background,
            bgElevated: elevated,
            codeBg: elevated,
            codeFg: text,
            text: text,
            muted: hex(.secondaryLabelColor, scheme: scheme, over: background),
            border: hex(.separatorColor, scheme: scheme, over: background),
            accent: hex(.controlAccentColor, scheme: scheme, over: background),
            danger: scheme == .dark ? "#D14D41" : "#AF3029",
            success: scheme == .dark ? "#879A39" : "#66800B",
            warn: scheme == .dark ? "#D0A215" : "#AD8301"
        )
        #else
        let background = hex(.systemBackground, scheme: scheme, over: "#000000")
        let elevated = hex(.secondarySystemBackground, scheme: scheme, over: background)
        let text = scheme == .dark ? "#FFFFFF" : hex(.label, scheme: scheme, over: background)
        return ThemePalette(
            bg: background,
            bgElevated: elevated,
            codeBg: elevated,
            codeFg: text,
            text: text,
            muted: hex(.secondaryLabel, scheme: scheme, over: background),
            border: hex(.separator, scheme: scheme, over: background),
            accent: hex(.tintColor, scheme: scheme, over: background),
            danger: scheme == .dark ? "#D14D41" : "#AF3029",
            success: scheme == .dark ? "#879A39" : "#66800B",
            warn: scheme == .dark ? "#D0A215" : "#AD8301"
        )
        #endif
    }

    #if os(macOS)
    static func hex(_ color: NSColor, scheme: ColorScheme, over background: String) -> String {
        var resolved = color
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Self.compositeHex(r: r, g: g, b: b, a: a, over: background)
    }
    #else
    static func hex(_ color: UIColor, scheme: ColorScheme, over background: String) -> String {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = color.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Self.compositeHex(r: r, g: g, b: b, a: a, over: background)
    }
    #endif

    /// `src` at alpha over `background`, as an opaque `#RRGGBB`.
    private static func compositeHex(
        r: CGFloat,
        g: CGFloat,
        b: CGFloat,
        a: CGFloat,
        over background: String
    ) -> String {
        let alpha = min(max(Double(a), 0), 1)
        let base = components(background) ?? (0, 0, 0)
        func channel(_ value: CGFloat, _ backdrop: Double) -> Int {
            let blended = min(max(Double(value), 0), 1) * alpha + backdrop * (1 - alpha)
            return min(max(Int((blended * 255).rounded()), 0), 255)
        }
        return String(
            format: "#%02X%02X%02X",
            channel(r, base.0),
            channel(g, base.1),
            channel(b, base.2)
        )
    }
}

