import XCTest

/// Sample mode exercises the real conversation view without speech services,
/// microphone permissions, downloaded models, or live conversation data.
final class TableTalkUITests: XCTestCase {
    @MainActor
    private var app: XCUIApplication!

    // XCTestCase's synchronous setup override is nonisolated. Keep UI setup
    // in an explicitly isolated helper called by each UI test instead.
    @MainActor
    private func launchApp(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    @MainActor
    private func revealSampleButton() -> XCUIElement {
        let button = app.buttons["setup.startSample"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        return button
    }

    @MainActor
    private func openSample(arguments: [String] = []) {
        launchApp(arguments: arguments)
        revealSampleButton().tap()
        XCTAssertTrue(app.staticTexts["demo.label"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFreshLaunchRequiresSetupAndSampleNeedsNoPermissions() {
        launchApp()
        let sample = revealSampleButton()
        let realConversation = app.buttons["setup.startConversation"]
        XCTAssertTrue(realConversation.exists)
        XCTAssertFalse(realConversation.isEnabled)
        XCTAssertTrue(sample.isEnabled)
        // Reaching sample mode without dismissing a system dialog demonstrates
        // that launch/sample do not trigger microphone or speech permission UI.
        sample.tap()
        XCTAssertTrue(app.staticTexts["demo.label"].waitForExistence(timeout: 5))
    }

    @MainActor
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

    @MainActor
    func testClearRemovesBothSidesOfSampleTurn() {
        openSample()
        app.buttons["conversation.clear"].tap()
        XCTAssertFalse(app.staticTexts["Hello"].exists)
        XCTAssertFalse(app.staticTexts["Hola"].exists)
        XCTAssertTrue(app.staticTexts["demo.label"].exists)
    }

    @MainActor
    func testLeavingConversationReturnsToSetup() {
        openSample()
        app.buttons["conversation.setup"].tap()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
    }

    @MainActor
    func testSpanishSampleHasEnglishCounterpart() {
        openSample()
        app.buttons["speak.spanish"].tap()
        XCTAssertEqual(app.staticTexts["caption.source.spanish"].label, "¿Cómo está?")
        XCTAssertEqual(app.staticTexts["caption.translation.english"].label, "How are you?")
        XCTAssertTrue(app.staticTexts["demo.label"].exists)
    }

    @MainActor
    func testBackgroundingClearsConversationAndRequiresSetup() {
        openSample()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        XCTAssertFalse(app.staticTexts["caption.source.english"].exists)
        XCTAssertFalse(app.staticTexts["caption.translation.spanish"].exists)
        XCTAssertFalse(app.buttons["setup.startConversation"].isEnabled)
    }

    private let longEnglish = "Hello. Please speak slowly so I can understand each sentence. We can take a short break, ask another question, and make sure the translated words remain easy to read on this screen."
    private let longSpanish = "Hola. Por favor, hable despacio para que pueda entender cada frase. Podemos hacer una pausa breve, hacer otra pregunta y comprobar que las palabras traducidas sigan siendo fáciles de leer en esta pantalla."
    private let slowLongArguments = ["--ui-testing-long-captions", "--ui-testing-slow-reveal"]

    /// The slow fixture allows at most 32 steps of 200 ms. Wait beyond that
    /// deadline without asking the app to expose its private animation state.
    @MainActor
    private func waitBeyondSlowReveal() {
        let deadline = Date().addingTimeInterval(7)
        let elapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 8), .completed)
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Observe the entire old reveal deadline. A single immediate absence
    /// assertion could miss a delayed callback that resurrects cleared content.
    @MainActor
    private func assertCaptionsRemainAbsent() {
        let identifiers = ["caption.source.english", "caption.source.spanish",
                           "caption.translation.english", "caption.translation.spanish"]
        let reappearances = identifiers.map { identifier in
            let caption = app.staticTexts.matching(identifier: identifier).firstMatch
            XCTAssertFalse(caption.exists)
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"), object: caption)
            expectation.isInverted = true
            return expectation
        }
        XCTAssertEqual(XCTWaiter.wait(for: reappearances, timeout: 7), .completed)
    }

    @MainActor
    func testLongCaptionsKeepFullAccessibilityAndStableWrappingDuringReveal() {
        openSample(arguments: slowLongArguments)
        let source = app.staticTexts["caption.source.english"]
        let translation = app.staticTexts["caption.translation.spanish"]
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        XCTAssertEqual(source.label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        let initialHeight = translation.frame.height
        XCTAssertGreaterThan(initialHeight, 0)
        let partialTranslation = translation.screenshot().pngRepresentation
        attachScreenshot("Long portrait captions — partial reveal")

        waitBeyondSlowReveal()
        XCTAssertEqual(source.label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        XCTAssertEqual(translation.frame.height, initialHeight, accuracy: 2,
                       "Revealing a suffix must preserve the final text wrapping.")
        XCTAssertNotEqual(translation.screenshot().pngRepresentation, partialTranslation,
                          "The target caption should visibly progress while its accessible label remains complete.")
        attachScreenshot("Long portrait captions — complete reveal")
    }

    @MainActor
    func testClearCancelsAnInFlightReveal() {
        openSample(arguments: slowLongArguments)
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, longSpanish)
        app.buttons["conversation.clear"].tap()
        XCTAssertTrue(app.staticTexts["demo.label"].exists)
        assertCaptionsRemainAbsent()
    }

    @MainActor
    func testReturningToSetupCancelsAnInFlightReveal() {
        openSample(arguments: slowLongArguments)
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, longSpanish)
        app.buttons["conversation.setup"].tap()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        assertCaptionsRemainAbsent()
        // The next sample is a fresh session, not an old reveal callback.
        revealSampleButton().tap()
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, longEnglish)
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, longSpanish)
    }

    @MainActor
    func testBackgroundCancelsAnInFlightReveal() {
        openSample(arguments: slowLongArguments)
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, longSpanish)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        assertCaptionsRemainAbsent()
    }

    @MainActor
    func testNewSampleTurnsDoNotOverwriteAnotherTurnsRevealingTranslation() {
        openSample(arguments: ["--ui-testing-slow-reveal"])
        app.buttons["speak.spanish"].tap()
        app.buttons["speak.english"].tap()
        waitBeyondSlowReveal()
        let spanishSources = app.staticTexts.matching(identifier: "caption.source.spanish")
        let englishTranslations = app.staticTexts.matching(identifier: "caption.translation.english")
        let englishSources = app.staticTexts.matching(identifier: "caption.source.english")
        let spanishTranslations = app.staticTexts.matching(identifier: "caption.translation.spanish")
        XCTAssertGreaterThan(spanishSources.count, 0)
        XCTAssertGreaterThan(englishTranslations.count, 0)
        XCTAssertGreaterThan(englishSources.count, 0)
        XCTAssertGreaterThan(spanishTranslations.count, 0)
        XCTAssertTrue(spanishSources.allElementsBoundByIndex.allSatisfy { $0.label == "¿Cómo está?" })
        XCTAssertTrue(englishTranslations.allElementsBoundByIndex.allSatisfy { $0.label == "How are you?" })
        XCTAssertTrue(englishSources.allElementsBoundByIndex.allSatisfy { $0.label == "Hello" })
        XCTAssertTrue(spanishTranslations.allElementsBoundByIndex.allSatisfy { $0.label == "Hola" })
    }

    @MainActor
    func testLandscapeLargeTextKeepsControlsAndBothCaptionScrollViewsAccessible() {
        openSample(arguments: slowLongArguments + [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let english = app.scrollViews["captions.english"]
        let spanish = app.scrollViews["captions.spanish"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertTrue(spanish.exists)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(english.isHittable)
        XCTAssertTrue(spanish.isHittable)
        for identifier in ["speak.english", "speak.spanish", "conversation.clear", "conversation.setup"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, "Control \(identifier) must remain reachable at the largest text size.")
        }
        for scroll in [english, spanish] {
            XCTAssertGreaterThan(scroll.frame.width, 0)
            XCTAssertGreaterThan(scroll.frame.height, 0)
            XCTAssertTrue(app.frame.insetBy(dx: -2, dy: -2).contains(scroll.frame),
                          "The caption viewport must fit inside the landscape screen.")
        }
        XCTAssertLessThanOrEqual(spanish.frame.maxX, english.frame.minX + 2,
                                 "Landscape language panels must have independent side-by-side viewports.")
        let source = app.staticTexts["caption.source.english"]
        let translation = app.staticTexts["caption.translation.spanish"]
        XCTAssertEqual(source.label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        XCTAssertLessThanOrEqual(source.frame.width, english.frame.width + 2)
        XCTAssertLessThanOrEqual(translation.frame.width, spanish.frame.width + 2)
        attachScreenshot("Landscape largest text — partial reveal")

        let englishBeforeScroll = english.screenshot().pngRepresentation
        english.swipeUp()
        XCTAssertNotEqual(english.screenshot().pngRepresentation, englishBeforeScroll,
                          "The unrotated English caption viewport must scroll long content.")
        let spanishBeforeScroll = spanish.screenshot().pngRepresentation
        // Spanish faces the other person and is rotated 180 degrees.
        spanish.swipeDown()
        XCTAssertNotEqual(spanish.screenshot().pngRepresentation, spanishBeforeScroll,
                          "The opposing Spanish caption viewport must scroll long content.")
        let manualSourceY = source.frame.minY
        let manualTranslationY = translation.frame.minY
        let translationAfterManualScroll = translation.screenshot().pngRepresentation
        waitBeyondSlowReveal()
        XCTAssertEqual(source.label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        XCTAssertEqual(source.frame.minY, manualSourceY, accuracy: 2)
        XCTAssertEqual(translation.frame.minY, manualTranslationY, accuracy: 2)
        XCTAssertEqual(translation.screenshot().pngRepresentation, translationAfterManualScroll,
                       "Manual scrolling must expose the complete caption and stop subsequent reveal updates.")
        XCTAssertTrue(app.buttons["speak.english"].isHittable)
        XCTAssertTrue(app.buttons["speak.spanish"].isHittable)
        attachScreenshot("Landscape largest text — complete reveal after manual scrolling")
    }

    @MainActor
    func testReducedMotionShowsTheCompleteTranslationWithoutFurtherReveal() {
        openSample(arguments: slowLongArguments + ["--ui-testing-reduced-motion"])
        let translation = app.staticTexts["caption.translation.spanish"]
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        let initialTranslation = translation.screenshot().pngRepresentation
        let initialHeight = translation.frame.height
        waitBeyondSlowReveal()
        XCTAssertEqual(translation.label, longSpanish)
        XCTAssertEqual(translation.frame.height, initialHeight, accuracy: 2)
        XCTAssertEqual(translation.screenshot().pngRepresentation, initialTranslation,
                       "Reduced motion must show all translated text at arrival and leave it unchanged.")
        attachScreenshot("Reduced motion — complete long translation")
    }
}
