import Foundation
import Testing
@testable import Kissmark

@MainActor
struct AppLanguageTests {
    @Test("Language selection changes only its app domain and System removes the override")
    func languagePreferenceStaysAppScoped() throws {
        let domain = "Kissmark.Language.\(UUID().uuidString)"
        let otherDomain = "Kissmark.Language.Other.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let other = try #require(UserDefaults(suiteName: otherDomain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            other.removePersistentDomain(forName: otherDomain)
        }
        defaults.set("saved document", forKey: "unrelated")
        other.set(["ko"], forKey: "AppleLanguages")

        KissmarkLanguage.english.store(in: defaults)
        #expect(KissmarkLanguage.preference(in: defaults, domain: domain) == .english)
        #expect(other.stringArray(forKey: "AppleLanguages") == ["ko"])

        KissmarkLanguage.korean.store(in: defaults)
        #expect(KissmarkLanguage.preference(in: defaults, domain: domain) == .korean)
        KissmarkLanguage.system.store(in: defaults)
        #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
        #expect(KissmarkLanguage.preference(in: defaults, domain: domain) == .system)
        #expect(defaults.string(forKey: "unrelated") == "saved document")
        #expect(other.stringArray(forKey: "AppleLanguages") == ["ko"])
    }
}
