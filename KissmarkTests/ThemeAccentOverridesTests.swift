import Foundation
import SwiftUI
import Testing
@testable import Kissmark

@MainActor
struct ThemeAccentOverridesTests {
    @Test("Theme and appearance colors survive reload without leaking into another scope")
    func scopesSurviveReload() {
        var accents = ThemeAccentOverrides()
        accents.setAccent("#BEF91E", for: .dracula, scheme: .light)
        accents.setAccent("#11AA88", for: .dracula, scheme: .dark)
        accents.setAccent("#FF6633", for: .nord, scheme: .light)

        let restored = ThemeAccentOverrides.decode(accents.encoded())
        #expect(restored.accent(for: .dracula, scheme: .light) == "#BEF91E")
        #expect(restored.accent(for: .dracula, scheme: .dark) == "#11AA88")
        #expect(restored.accent(for: .nord, scheme: .light) == "#FF6633")
        #expect(restored.accent(for: .nord, scheme: .dark) == nil)
    }

    @Test("The visible theme variant owns its color and reset clears only that scope")
    func visibleVariantAndScopedReset() {
        var accents = ThemeAccentOverrides()
        accents.setAccent("#BEF91E", for: .catppuccinLatte, scheme: .dark)
        accents.setAccent("#006633", for: .catppuccinMacchiato, scheme: .light)
        accents.setAccent("#FF6633", for: .nord, scheme: .light)
        #expect(accents.accent(for: .catppuccinMocha, scheme: .dark) == "#BEF91E")
        #expect(accents.accent(for: .catppuccinLatte, scheme: .light) == "#006633")
        #expect(accents.accent(for: .catppuccinMacchiato, scheme: .dark) == nil)

        accents.setAccent(nil, for: .catppuccinLatte, scheme: .light)
        #expect(accents.accent(for: .catppuccinMacchiato, scheme: .light) == nil)
        #expect(accents.accent(for: .catppuccinMocha, scheme: .dark) == "#BEF91E")
        #expect(accents.accent(for: .nord, scheme: .light) == "#FF6633")
    }

    @Test("Corrupt preferences and invalid colors fall back without hiding valid entries")
    func invalidStoredColors() {
        #expect(ThemeAccentOverrides.decode("not JSON").accent(for: .dracula, scheme: .light) == nil)
        let restored = ThemeAccentOverrides.decode(##"{"dracula.light":"red","dracula.dark":"#abcdef"}"##)
        #expect(restored.accent(for: .dracula, scheme: .light) == nil)
        #expect(restored.accent(for: .dracula, scheme: .dark) == "#ABCDEF")
    }

    @Test("The former global color migrates once into the current scope and preserves other colors")
    func legacyMigration() throws {
        let suite = "KM_ThemeAccents_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var accents = ThemeAccentOverrides()
        accents.setAccent("#11AA88", for: .dracula, scheme: .dark)
        defaults.set(accents.encoded(), forKey: ThemeAccentOverrides.storageKey)
        defaults.set("#BEF91E", forKey: "kissmark.accent")

        ThemeAccentOverrides.migrateLegacy(in: defaults, theme: .dracula, scheme: .light)
        ThemeAccentOverrides.migrateLegacy(in: defaults, theme: .nord, scheme: .light)

        let restored = ThemeAccentOverrides.decode(defaults.string(forKey: ThemeAccentOverrides.storageKey) ?? "")
        #expect(restored.accent(for: .dracula, scheme: .light) == "#BEF91E")
        #expect(restored.accent(for: .dracula, scheme: .dark) == "#11AA88")
        #expect(restored.accent(for: .nord, scheme: .light) == nil)
        #expect(defaults.object(forKey: "kissmark.accent") == nil)
    }

    @Test("Legacy migration never replaces a color already saved for the current theme")
    func migrationPreservesCurrentChoice() throws {
        let suite = "KM_ThemeAccents_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var accents = ThemeAccentOverrides()
        accents.setAccent("#006633", for: .catppuccinLatte, scheme: .light)
        defaults.set(accents.encoded(), forKey: ThemeAccentOverrides.storageKey)
        defaults.set("#BEF91E", forKey: "kissmark.accent")

        ThemeAccentOverrides.migrateLegacy(in: defaults, theme: .catppuccinMacchiato, scheme: .light)

        let restored = ThemeAccentOverrides.decode(defaults.string(forKey: ThemeAccentOverrides.storageKey) ?? "")
        #expect(restored.accent(for: .catppuccinLatte, scheme: .light) == "#006633")
        #expect(defaults.object(forKey: "kissmark.accent") == nil)
    }
}
