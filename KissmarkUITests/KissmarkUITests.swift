//
//  KissmarkUITests.swift
//  KissmarkUITests
//
//  Created by 김성규 on 7/14/26.
//

import XCTest

final class KissmarkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchShowsOnlyTheChooseFolderAction() throws {
        let app = launchApp(state: "none")

        let chooseFolderButton = element(identifier: "choose-folder-button", in: app)
        XCTAssertTrue(
            chooseFolderButton.waitForExistence(timeout: 8),
            "Expected choose-folder-button. Hierarchy:\n\(app.debugDescription)"
        )
        XCTAssertTrue(chooseFolderButton.isEnabled)
        XCTAssertFalse(app.staticTexts["Hello, world!"].exists)
        XCTAssertFalse(element(identifier: "folder-browser", in: app).exists)
    }

    @MainActor
    func testPickerFailureCanBeDismissedWithoutLosingSelection() throws {
        let app = launchApp(state: "picker-failure")

        #if os(macOS)
        let alert = app.sheets.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let sheetOK = alert.buttons["OK"].exists ? alert.buttons["OK"] : alert.buttons["확인"]
            XCTAssertTrue(sheetOK.waitForExistence(timeout: 2))
            sheetOK.tap()
        } else {
            let ok = app.buttons["OK"].exists ? app.buttons["OK"] : app.buttons["확인"]
            XCTAssertTrue(
                ok.waitForExistence(timeout: 5),
                "Expected OK dismiss control. Hierarchy:\n\(app.debugDescription)"
            )
            ok.tap()
        }
        #else
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        let ok = app.buttons["OK"].exists ? app.buttons["OK"] : app.buttons["확인"]
        ok.tap()
        #endif

        let chooseFolderButton = element(identifier: "choose-folder-button", in: app)
        XCTAssertTrue(chooseFolderButton.waitForExistence(timeout: 5))
        XCTAssertTrue((chooseFolderButton.value as? String ?? "").contains("KM_Selected_A"))
    }

    @MainActor
    func testReaderFixtureUsesTheDebugOnlyRoute() throws {
        let app = launchApp(state: "reader-fixture")

        let reader = element(identifier: "document-reader", in: app)
        let title = staticText(containing: "Kissmark 읽기 검증 보고서", in: app)
        XCTAssertTrue(
            reader.waitForExistence(timeout: 8) || title.waitForExistence(timeout: 8),
            "Expected reader fixture content. Hierarchy:\n\(app.debugDescription)"
        )
        XCTAssertFalse(element(identifier: "choose-folder-button", in: app).exists)
    }

    @MainActor
    func testEditorFixtureUsesTheDebugOnlyRoute() throws {
        let app = launchApp(state: "editor-fixture")

        let container = element(identifier: "editor-fixture-container", in: app)
        let mode = element(identifier: "document-mode-button", in: app)
        XCTAssertTrue(
            container.waitForExistence(timeout: 8) || mode.waitForExistence(timeout: 8),
            "Expected editor fixture. Hierarchy:\n\(app.debugDescription)"
        )
        XCTAssertFalse(element(identifier: "choose-folder-button", in: app).exists)
    }

    @MainActor
    func testEditorFixtureRendersTheDocumentInReadMode() throws {
        let app = launchApp(state: "editor-fixture")

        let reader = element(identifier: "document-reader", in: app)
        let title = staticText(containing: "Kissmark 읽기 검증 보고서", in: app)
        XCTAssertTrue(
            reader.waitForExistence(timeout: 8) || title.waitForExistence(timeout: 8),
            "Expected Read Mode content. Hierarchy:\n\(app.debugDescription)"
        )
        XCTAssertFalse(element(identifier: "reader-load-error", in: app).exists)
    }

    @MainActor
    func testReadAndEditStayInTheSameWindow() throws {
        let app = launchApp(state: "editor-fixture")

        let mode = element(identifier: "document-mode-button", in: app)
        XCTAssertTrue(
            element(identifier: "editor-fixture-container", in: app).waitForExistence(timeout: 8)
                || element(identifier: "document-reader", in: app).waitForExistence(timeout: 8)
                || mode.waitForExistence(timeout: 8),
            "Expected editor fixture shell. Hierarchy:\n\(app.debugDescription)"
        )

        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        // Starts in Read; tap Edit (pencil) → Edit Mode.
        mode.tap()
        XCTAssertTrue(element(identifier: "document-editor", in: app).waitForExistence(timeout: 8))

        // Tap Done (checkmark) → Read Mode.
        mode.tap()
        XCTAssertTrue(
            element(identifier: "document-reader", in: app).waitForExistence(timeout: 8)
                || staticText(containing: "Kissmark 읽기 검증 보고서", in: app).waitForExistence(timeout: 8)
        )
    }

    @MainActor
    func testFolderBrowserKeepsToolbarAndWindowStableAcrossTransitions() throws {
        let app = launchApp(state: "folder-browser")
        let window = app.windows.firstMatch
        let shellHeader = element(identifier: "folder-browser-shell-header", in: app)
        let sidebar = element(identifier: "sidebar-toggle-button", in: app)
        let sidebarHeader = element(identifier: "sidebar-chrome-header", in: app)
        let openFolder = element(identifier: "choose-folder-button", in: app)
        let mode = element(identifier: "document-mode-button", in: app)
        let archive = element(identifier: "document-archive-button", in: app)
        let close = element(identifier: "document-close-button", in: app)
        let document = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND (value == %@ OR label == %@)",
                "folder-browser-document",
                "Layout QA",
                "Layout QA"
            )
        ).firstMatch
        let spacingFolder = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND (value == %@ OR label == %@)",
                "folder-browser-folder",
                "Spacing QA",
                "Spacing QA"
            )
        ).firstMatch
        let nestedDocument = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND (value == %@ OR label == %@)",
                "folder-browser-document",
                "Nested Layout QA",
                "Nested Layout QA"
            )
        ).firstMatch

        XCTAssertTrue(sidebar.waitForExistence(timeout: 8))
        XCTAssertTrue(shellHeader.waitForExistence(timeout: 8))
        XCTAssertTrue(sidebarHeader.waitForExistence(timeout: 8))
        XCTAssertTrue(openFolder.waitForExistence(timeout: 8))
        XCTAssertTrue(
            ["Choose Folder", "폴더 선택"].contains(openFolder.label),
            "Expected the localized Choose Folder label, got \(openFolder.label)"
        )
        XCTAssertTrue(displayedText(of: openFolder).contains("KissmarkUITestFolder"))
        XCTAssertEqual(shellHeader.frame.height, 44, accuracy: 1)
        // Item 3 of the 1.4 spec: the toggle leads the action bar's sidebar lane, so its
        // position does not change when the sidebar collapses; the FolderControl follows it.
        XCTAssertEqual(sidebar.frame.minX - shellHeader.frame.minX, 12, accuracy: 2)
        XCTAssertEqual(
            openFolder.frame.minX - sidebar.frame.maxX,
            8,
            accuracy: 2,
            "the FolderControl sits one icon-label gap right of the toggle"
        )
        XCTAssertEqual(sidebarHeader.frame.minX, shellHeader.frame.minX, accuracy: 1)
        XCTAssertTrue(document.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(
            document.frame.minY - sidebarHeader.frame.maxY,
            7
        )
        XCTAssertTrue(spacingFolder.waitForExistence(timeout: 5))
        let collapsedFolderMinX = spacingFolder.frame.minX
        spacingFolder.tap()
        XCTAssertTrue(nestedDocument.waitForExistence(timeout: 5))
        XCTAssertEqual(spacingFolder.frame.minX, collapsedFolderMinX, accuracy: 1)
        XCTAssertEqual(nestedDocument.frame.minX, spacingFolder.frame.minX, accuracy: 2)
        XCTAssertEqual(nestedDocument.frame.width, spacingFolder.frame.width, accuracy: 2)
        XCTAssertGreaterThanOrEqual(nestedDocument.frame.minY - spacingFolder.frame.maxY, 0)
        XCTAssertFalse(mode.isEnabled)
        XCTAssertFalse(archive.isEnabled)
        XCTAssertFalse(close.isEnabled)

        let initialFrame = window.frame
        document.tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.isEnabled)
        XCTAssertTrue(archive.isEnabled)
        XCTAssertTrue(close.isEnabled)
        XCTAssertEqual(window.frame.origin.x, initialFrame.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, initialFrame.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, initialFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, initialFrame.height, accuracy: 1)

        close.tap()
        XCTAssertTrue(element(identifier: "folder-browser-empty-detail", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(mode.isEnabled)
        XCTAssertFalse(archive.isEnabled)
        XCTAssertFalse(close.isEnabled)

        document.tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.isEnabled)

        let beforeSidebarToggle = window.frame
        sidebar.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(of: sidebar), "hidden")
        XCTAssertEqual(window.frame.origin.x, beforeSidebarToggle.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, beforeSidebarToggle.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, beforeSidebarToggle.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, beforeSidebarToggle.height, accuracy: 1)

        sidebar.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(of: sidebar), "visible")
        XCTAssertEqual(window.frame.origin.x, beforeSidebarToggle.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, beforeSidebarToggle.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, beforeSidebarToggle.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, beforeSidebarToggle.height, accuracy: 1)
    }

    @MainActor
    private func launchApp(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KISSMARK_UI_TEST"] = "1"
        if state == "folder-browser" {
            app.launchEnvironment["KISSMARK_UI_TEST_WIDTH"] = "1100"
            app.launchEnvironment["KISSMARK_UI_TEST_HEIGHT"] = "720"
        }
        // Pass the gate as a launch argument too — more reliable on macOS UI tests.
        app.launchArguments = [
            "-KISSMARK_UI_TEST", "1",
            "-ui-test-state", state,
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        app.activate()
        // macOS agent/CI hosts sometimes report Application AX as Disabled until a beat passes.
        _ = element(identifier: "app-root", in: app).waitForExistence(timeout: 5)
        return app
    }

    @MainActor
    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func modeControl(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let byID = element(identifier: identifier, in: app)
        if byID.exists { return byID }

        let labels: [String]
        if identifier.hasSuffix("read") {
            labels = ["읽기", "Read"]
        } else if identifier.hasSuffix("edit") {
            labels = ["편집", "Edit"]
        } else {
            return byID
        }

        for label in labels {
            if app.radioButtons[label].exists { return app.radioButtons[label] }
            if app.buttons[label].exists { return app.buttons[label] }
            if app.segmentedControls.buttons[label].exists {
                return app.segmentedControls.buttons[label]
            }
        }
        return byID
    }

    @MainActor
    private func displayedText(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    @MainActor
    private func staticText(containing text: String, in container: XCUIElement) -> XCUIElement {
        container.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text)
        ).firstMatch
    }
}
