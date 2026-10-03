import XCTest

/// Sample mode exercises the real conversation view without speech services,
/// microphone permissions, downloaded models, or live conversation data.
final class TableTalkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    private func openSample() {
        let button = app.buttons["setup.startSample"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.staticTexts["demo.label"].waitForExistence(timeout: 5))
    }

    func testSampleShowsTwoLanguagePanelsAndTranslation() {
        openSample()
        XCTAssertTrue(app.descendants(matching: .any)["panel.english"].exists)
        let spanish = app.descendants(matching: .any)["panel.spanish"]
        XCTAssertTrue(spanish.exists)
        XCTAssertTrue(spanish.label.contains("Español"))
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, "Hello")
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, "Hola")
        XCTAssertTrue(app.buttons["speak.english"].exists)
        XCTAssertTrue(app.buttons["speak.spanish"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Two-sided sample conversation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testClearRemovesBothSidesOfSampleTurn() {
        openSample()
        app.buttons["conversation.clear"].tap()
        XCTAssertFalse(app.staticTexts["Hello"].exists)
        XCTAssertFalse(app.staticTexts["Hola"].exists)
        XCTAssertTrue(app.staticTexts["demo.label"].exists)
    }

    func testLeavingConversationReturnsToSetup() {
        openSample()
        app.buttons["conversation.setup"].tap()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
    }
}
