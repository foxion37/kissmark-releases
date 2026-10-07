import Foundation
import SwiftUI
import Testing
@testable import Kissmark

struct DocumentThemeTests {
    @Test func sectionHeadersCanReadEachThemeAccentFromThePalette() {
        // 설정 섹션 머리글은 chromePalette.chromeAccent를 따르므로 테마마다 색이 바뀐다.
        let dracula = DocumentTheme.dracula.palette(for: .dark)
        #expect(dracula?.accent.lowercased() == "#bd93f9")
        let nord = DocumentTheme.nord.palette(for: .dark)
        #expect(nord?.accent.lowercased() != dracula!.accent.lowercased())
    }

    private static let systemPalette = ThemePalette(
        bg: "#101010", bgElevated: "#202020", codeBg: "#202020", codeFg: "#EEEEEE",
        text: "#EEEEEE", muted: "#909090", border: "#303030",
        accent: "#0A84FF", danger: "#FF453A", success: "#30D158", warn: "#FFD60A"
    )
    private static let schemes: [ColorScheme] = [.light, .dark]


    /// Mean sRGB channel, 0...1: enough to tell a paper from an ink background.
    private static func brightness(_ hex: String) -> Double {
        let raw = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return (Double((raw >> 16) & 0xFF) + Double((raw >> 8) & 0xFF) + Double(raw & 0xFF)) / (3 * 255)
    }


    @Test("Every theme paints a light page in Light and a dark page in Dark, with readable text")
    func paletteMatchesScheme() {
        for theme in DocumentTheme.allCases where theme != .system {
            guard let light = theme.palette(for: .light), let dark = theme.palette(for: .dark) else {
                Issue.record("\(theme.rawValue) is missing a palette")
                continue
            }
            #expect(Self.brightness(light.bg) > 0.75, "\(theme.rawValue) Light background is not light")
            #expect(Self.brightness(dark.bg) < 0.25, "\(theme.rawValue) Dark background is not dark")
            #expect(Self.brightness(light.text) < 0.5, "\(theme.rawValue) Light text is not dark ink")
            #expect(Self.brightness(dark.text) > 0.5, "\(theme.rawValue) Dark text is not light ink")
        }
    }

    @Test("A paired theme swaps sides with the scheme and returns to the same dark flavor")
    func pairedThemesRoundTrip() {
        for flavor in [DocumentTheme.catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha] {
            #expect(flavor.variant(for: .dark) == flavor)
            #expect(flavor.variant(for: .light) == .catppuccinLatte)
            // The stored value is never rewritten, so the next Dark shows the same flavor again.
            #expect(flavor.palette(for: .light) == DocumentTheme.catppuccinLatte.palette(for: .light))
        }
        #expect(DocumentTheme.catppuccinLatte.variant(for: .dark) == .catppuccinMocha)
        #expect(DocumentTheme.catppuccinLatte.variant(for: .light) == .catppuccinLatte)
        #expect(DocumentTheme.gruvboxLight.variant(for: .dark) == .gruvboxDark)
        #expect(DocumentTheme.gruvboxDark.variant(for: .light) == .gruvboxLight)
        #expect(DocumentTheme.solarizedLight.variant(for: .dark) == .solarizedDark)
        #expect(DocumentTheme.solarizedDark.variant(for: .light) == .solarizedLight)
        #expect(DocumentTheme.dracula.variant(for: .light) == .dracula)
    }

    @Test("The theme list shows one row per family for the scheme and the picked family stays selected")
    func choicesCollapsePairs() {
        let light = DocumentTheme.choices(for: .light)
        let dark = DocumentTheme.choices(for: .dark)
        #expect(light.filter { $0.rawValue.hasPrefix("catppuccin") } == [.catppuccinLatte])
        #expect(dark.filter { $0.rawValue.hasPrefix("catppuccin") }
            == [.catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha])
        #expect(light.filter { $0.rawValue.hasPrefix("gruvbox") } == [.gruvboxLight])
        #expect(dark.filter { $0.rawValue.hasPrefix("gruvbox") } == [.gruvboxDark])
        #expect(light.count == Set(light.map { $0.palette(for: .light)?.bg }).count, "no identical rows")
        for scheme in Self.schemes {
            for saved in DocumentTheme.allCases {
                let shown = DocumentTheme.choices(for: scheme).filter { $0.variant(for: scheme) == saved.variant(for: scheme) }
                #expect(shown.count == 1, "\(saved.rawValue) must select exactly one row in \(scheme)")
            }
        }
    }

    @Test("Explicit Light/Dark beats the system scheme; System follows it")
    func appearancePriority() {
        for system in Self.schemes {
            #expect(KissmarkAppearance.effectiveScheme(.light, systemScheme: system) == .light)
            #expect(KissmarkAppearance.effectiveScheme(.dark, systemScheme: system) == .dark)
            #expect(KissmarkAppearance.effectiveScheme(.system, systemScheme: system) == system)
        }
    }

    @Test("CSS scheme and palette follow the effective scheme, never the theme's own polarity")
    func cssAgreesWithNative() {
        for scheme in Self.schemes {
            for theme in DocumentTheme.allCases {
                let vars = DocumentThemeResolver.cssVariables(
                    theme: theme, accentHex: nil, scheme: scheme, system: Self.systemPalette
                )
                let native = DocumentThemeResolver.palette(theme: theme, scheme: scheme, system: Self.systemPalette)
                #expect(vars[DocumentThemeResolver.schemeKey] == (scheme == .dark ? "dark" : "light"))
                #expect(vars["--km-theme-bg"] == native.bg)
                #expect(vars["--km-theme-text"] == native.text)
            }
        }
    }


    @Test("Invalid accent overrides use the same display color as the theme default")
    func invalidAccentOverride() {
        for scheme in Self.schemes {
            let baseline = DocumentThemeResolver.cssVariables(
                theme: .dracula, accentHex: nil, scheme: scheme, system: Self.systemPalette
            )
            for bad in ["red", "#FFF", "#GGGGGG", "FF0000", "#FF00", ""] {
                let ignored = DocumentThemeResolver.cssVariables(
                    theme: .dracula, accentHex: bad, scheme: scheme, system: Self.systemPalette
                )
                #expect(ignored["--km-theme-accent"] == baseline["--km-theme-accent"], "\(bad) should be ignored")
            }
        }
        #expect(DocumentThemeResolver.chromeAccentHex(theme: .system, scheme: .dark, override: nil) == nil)
    }

    @Test("Chosen accent colors are shown exactly, without brightness remapping")
    func chosenAccentMatchesDisplay() {
        for theme in DocumentTheme.allCases {
            for scheme in Self.schemes {
                for color in ["#BEF91E", "#112233"] {
                    let vars = DocumentThemeResolver.cssVariables(
                        theme: theme, accentHex: color, scheme: scheme, system: Self.systemPalette
                    )
                    #expect(vars["--km-theme-accent"] == color)
                    #expect(DocumentThemeResolver.chromeAccentHex(theme: theme, scheme: scheme, override: color) == color)
                }
            }
        }
    }

    @Test("The system palette composites translucent system colors over the background")
    func systemPaletteCompositesAlpha() {
        let dark = DocumentThemeResolver.systemPalette(for: .dark)
        let light = DocumentThemeResolver.systemPalette(for: .light)
        #expect(dark.text == "#FFFFFF")
        for hex in [dark.bg, dark.border, dark.muted, dark.bgElevated, light.bg, light.border, light.muted] {
            #expect(DocumentThemeResolver.validHex(hex) == hex, "\(hex) is not a plain hex")
        }
        // `separatorColor` is pure white at ~10% in macOS dark and `separator` is
        // a dark grey at ~30% in iOS light. A resolve that drops alpha would emit
        // the raw channel extremes (white border in dark) here.
        #expect(dark.border != "#FFFFFF", "the dark separator must be composited over the background")
        #expect(dark.muted != "#FFFFFF")
        #expect(dark.border != "#000000")
        #expect(light.border != "#000000")
        #expect(dark.bg != dark.border)
    }

}
