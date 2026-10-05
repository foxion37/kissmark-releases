//
//  KissmarkUITestsLaunchTests.swift
//  KissmarkUITests
//
//  Created by 김성규 on 7/14/26.
//

import XCTest

final class KissmarkUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        // Avoid multi-appearance launches that collide with other local daemons.
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KISSMARK_UI_TEST"] = "1"
        app.launchArguments = ["-KISSMARK_UI_TEST", "1", "-ui-test-state", "none"]
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: 10)
        app.activate()
        XCTAssertTrue(app.buttons["choose-folder-button"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
