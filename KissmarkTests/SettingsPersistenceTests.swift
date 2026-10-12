import Testing
@testable import Kissmark

struct SettingsPersistenceTests {
    @Test("Typography settings use stable keys across app versions")
    func settingsKeysAreNotVersionScoped() {
        #expect(KissmarkTextSize.storageKey == "kissmark.textSize")
        #expect(KissmarkTextAlignment.storageKey == "kissmark.textAlign")
        #expect(DesignOverrides.storageKey == "kissmark.design-overrides")
        #expect(DocumentTheme.storageKey == "kissmark.theme")
        #expect(ThemeAccentOverrides.storageKey == "kissmark.theme-accents")
    }
}
