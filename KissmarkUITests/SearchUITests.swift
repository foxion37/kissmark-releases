import XCTest

@MainActor
final class SearchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KISSMARK_UI_TEST", "1", "-ui-test-state", "folder-browser", "-AppleLanguages", "(en)"]
        app.launch()
        app.activate()
        let toggle = element("document-search-toggle", app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertFalse(element("folder-browser-search-query", app).exists)
        toggle.click()
        XCTAssertTrue(element("folder-browser-search-button", app).waitForExistence(timeout: 5))
        return app
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func wait(_ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testSidebarQuerySurvivesSheetEditingAndReopening() {
        let app = launch()
        defer { app.terminate() }
        let sidebar = element("folder-browser-search-query", app)
        replace(sidebar, with: "Nested Layout")
        element("document-search-toggle", app).click()
        wait { !sidebar.exists }
        element("document-search-toggle", app).click()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebar.value as? String, "Nested Layout")
        sidebar.typeKey(.return, modifierFlags: [])
        let query = element("document-search-query", app)
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertEqual(query.value as? String, "Nested Layout")
        XCTAssertTrue(element("document-search-result", app).waitForExistence(timeout: 10))
        replace(query, with: "Nested Layout QA")
        element("document-search-close", app).click()
        wait { !self.element("document-search-sheet", app).exists }
        wait { sidebar.value as? String == "Nested Layout QA" }
        element("folder-browser-search-button", app).click()
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertEqual(query.value as? String, "Nested Layout QA")
        XCTAssertTrue(element("document-search-result", app).waitForExistence(timeout: 10))
    }

    func testFolderAndMemorySearchOpenDocuments() {
        let app = launch()
        defer { app.terminate() }
        app.typeKey("f", modifierFlags: [.command, .shift])
        let query = element("document-search-query", app)
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        replace(query, with: "Nested Layout")
        let result = element("document-search-result", app)
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Unopened nested document must be searchable")
        capture("folder-search-unopened-document", app)
        query.typeKey(.return, modifierFlags: [])
        wait { !self.element("document-search-sheet", app).exists }
        XCTAssertTrue(element("document-reader", app).waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        let scope = element("document-search-scope", app)
        let memoryControls = [scope.buttons["Opened Documents"], scope.radioButtons["Opened Documents"], scope.buttons["열어 본 문서"], scope.radioButtons["열어 본 문서"]]
        guard let memory = memoryControls.first(where: { $0.exists }) else {
            XCTFail("Memory scope is unavailable: \(scope.debugDescription)")
            return
        }
        memory.click()
        XCTAssertTrue(element("document-search-project", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("document-search-agent", app).exists)
        replace(query, with: "Nested Layout")
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Opened document must be searchable in Memory")
        capture("memory-search-with-filters", app)
        result.click()
        wait { !self.element("document-search-sheet", app).exists }
        XCTAssertTrue(element("document-reader", app).exists)
    }

    func testFindCommandCountsMatchesAndCloses() {
        let app = launch()
        defer { app.terminate() }
        element("folder-browser-search-button", app).click()
        let query = element("document-search-query", app)
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        replace(query, with: "Nested Layout")
        let result = element("document-search-result", app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.click()
        XCTAssertTrue(element("document-reader", app).waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: .command)
        let find = element("document-find-query", app)
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        replace(find, with: "Nested Layout")
        let status = element("document-find-status", app)
        wait {
            let value = (status.value as? String) ?? status.label
            return value.split(whereSeparator: { !$0.isNumber }).map(String.init) == ["1", "1"]
        }
        XCTAssertTrue(element("document-find-case", app).exists)
        XCTAssertTrue(element("document-find-word", app).exists)
        XCTAssertTrue(element("document-find-regex", app).exists)
        capture("document-find-result", app)
        find.typeKey(.escape, modifierFlags: [])
        wait { !self.element("document-find-bar", app).exists }
        XCTAssertTrue(element("document-reader", app).exists)
    }
}
