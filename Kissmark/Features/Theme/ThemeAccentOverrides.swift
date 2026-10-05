import Foundation
import SwiftUI

/// One saved color per displayed theme and Light/Dark appearance.
nonisolated struct ThemeAccentOverrides: Equatable {
    static let storageKey = "kissmark.theme-accents"
    private var colors: [String: String] = [:]

    init() {}

    private init(colors: [String: String]) {
        self.colors = colors
    }

    func accent(for theme: DocumentTheme, scheme: ColorScheme) -> String? {
        DocumentThemeResolver.validHex(colors[Self.key(for: theme, scheme: scheme)])
    }

    mutating func setAccent(_ color: String?, for theme: DocumentTheme, scheme: ColorScheme) {
        colors[Self.key(for: theme, scheme: scheme)] = DocumentThemeResolver.validHex(color)
    }

    static func decode(_ raw: String) -> ThemeAccentOverrides {
        guard let data = raw.data(using: .utf8),
              let colors = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ThemeAccentOverrides()
        }
        return ThemeAccentOverrides(colors: colors)
    }

    func encoded() -> String {
        guard !colors.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(colors) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func key(for theme: DocumentTheme, scheme: ColorScheme) -> String {
        "\(theme.variant(for: scheme).rawValue).\(scheme == .dark ? "dark" : "light")"
    }

    /// Move the former global choice into the current scope only, never every theme.
    @MainActor
    static func migrateLegacy(in defaults: UserDefaults, theme: DocumentTheme, scheme: ColorScheme) {
        let legacyKey = "kissmark.accent"
        guard let legacy = defaults.string(forKey: legacyKey) else { return }
        if let color = DocumentThemeResolver.validHex(legacy) {
            var accents = decode(defaults.string(forKey: storageKey) ?? "")
            if accents.accent(for: theme, scheme: scheme) == nil {
                accents.setAccent(color, for: theme, scheme: scheme)
                defaults.set(accents.encoded(), forKey: storageKey)
            }
        }
        defaults.removeObject(forKey: legacyKey)
    }
}
