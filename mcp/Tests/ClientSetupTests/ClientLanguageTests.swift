import XCTest
@testable import kissmark_mcp

final class ClientLanguageTests: XCTestCase {
    func testEnvironmentWinsThenSupportedProcessLanguageThenKorean() {
        XCTAssertEqual(ClientLanguage.resolve(environment: ["KISSMARK_LANGUAGE": "en"], preferred: ["ko-KR"]), .en)
        XCTAssertEqual(ClientLanguage.resolve(environment: ["KISSMARK_LANGUAGE": "fr"], preferred: ["fr-FR", "en-US"]), .en)
        XCTAssertEqual(ClientLanguage.resolve(environment: [:], preferred: ["ko-KR", "en-US"]), .ko)
        XCTAssertEqual(ClientLanguage.resolve(environment: [:], preferred: ["fr-FR"]), .ko)
    }
}
