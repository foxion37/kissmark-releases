import Foundation
import SwiftUI

/// The app-specific override is also the platform's per-app language preference.
nonisolated enum KissmarkLanguage: String, CaseIterable, Identifiable {
    case system
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }
    var displayName: LocalizedStringKey {
        switch self {
        case .system: "시스템"
        case .korean: "한국어"
        case .english: "English"
        }
    }

    static func preference(in defaults: UserDefaults, domain: String) -> Self {
        guard let languages = defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        let language = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        return language.flatMap(Self.init(rawValue:)) ?? .system
    }

    func store(in defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

nonisolated enum KissmarkEnglishFont: String, CaseIterable, Identifiable {
    case system
    case inter

    static let storageKey = "kissmark.englishFont"
    static let active = Self(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    var id: String { rawValue }
    var displayName: LocalizedStringKey {
        switch self {
        case .system: "OS 기본"
        case .inter: "Inter"
        }
    }
}

/// Values are captured before the first scene renders. Pending settings never
/// replace an editor/session or change its current-language messages.
nonisolated enum KissmarkLocalization {
    static let languageCode: String = {
        let preferred = Bundle.main.preferredLocalizations.first ?? "ko"
        return preferred.hasPrefix("en") ? "en" : "ko"
    }()
    static let locale = Locale(identifier: languageCode)
    static let bundle: Bundle = {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let localized = Bundle(path: path) else { return .main }
        return localized
    }()

    static func captureLaunchPreferences() {
        _ = languageCode
        _ = locale
        _ = bundle
        _ = KissmarkEnglishFont.active
    }
}

extension String {
    nonisolated static func kissmarkLocalized(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: KissmarkLocalization.bundle, locale: KissmarkLocalization.locale)
    }
}
