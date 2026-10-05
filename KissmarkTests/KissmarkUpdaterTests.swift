import Foundation
import Testing
@testable import Kissmark

struct KissmarkUpdaterTests {
    @Test("Given a higher tag When comparing Then an update is available")
    func newerTagIsAnUpdate() throws {
        let data = Data(#"{"tag_name":"v1.1.0","html_url":"https://github.com/foxion37/kissmark/releases/tag/v1.1.0"}"#.utf8)

        let check = try KissmarkUpdateClient.evaluate(current: "1.0.0", data: data)

        #expect(check.latest?.marketingVersion == "1.1.0")
        #expect(check.isUpdateAvailable)
    }

    @Test("Given the same version When comparing Then no update is available")
    func sameVersionIsNotAnUpdate() throws {
        let data = Data(#"{"tag_name":"1.1.0","html_url":"https://github.com/foxion37/kissmark/releases/tag/1.1.0"}"#.utf8)

        let check = try KissmarkUpdateClient.evaluate(current: "1.1.0", data: data)

        #expect(!check.isUpdateAvailable)
    }

    @Test("Given a lower tag When comparing Then no update is available")
    func olderTagIsNotAnUpdate() {
        #expect(!KissmarkVersionOrdering.isNewer("1.0.0", than: "1.1.0"))
        #expect(KissmarkVersionOrdering.isNewer("1.1.0", than: "1.0.9"))
        #expect(KissmarkVersionOrdering.isNewer("2.0", than: "1.9.9"))
    }

    @Test("Given invalid JSON When parsing Then evaluation fails")
    func invalidReleaseJSONFails() {
        #expect(throws: DecodingError.self) {
            try KissmarkUpdateClient.evaluate(current: "1.0.0", data: Data(#"{"tag_name":"1.0.0"}"#.utf8))
        }
    }

    @Test("Updates default to enabled")
    func updatesDefaultEnabled() {
        let suite = "kissmark-update-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        #expect(KissmarkUpdateSettings.isEnabled(in: defaults))
    }
}
