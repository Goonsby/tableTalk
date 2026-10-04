import XCTest
import UIKit

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
        for _ in 0..<20 where !button.isHittable { app.swipeUp() }
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
        XCTAssertTrue(app.staticTexts["Whipple Chat"].exists)
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
        XCTAssertEqual(spanish.label, "Español. Spanish viewer. No touch required.")
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, "Hello")
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, "Hola")
        assertOperatorOwnsConversationControls()
        XCTAssertFalse(app.buttons["conversation.stop"].isEnabled,
                       "Microphone-off samples must not imitate live recording.")
        XCTAssertFalse(app.buttons["conversation.stop"].label.isEmpty)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "WhippleChat operator controls and text-only Spanish viewer"
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
        completeSampleTurn("spanish")
        XCTAssertEqual(app.staticTexts["caption.source.spanish"].label, "¿Cómo está?")
        XCTAssertEqual(app.staticTexts["caption.translation.english"].label, "How are you?")
        XCTAssertTrue(app.staticTexts["demo.label"].exists)
    }

    @MainActor
    func testBackgroundingClearsConversationAndRequiresSetup() {
        openSample()
        XCUIDevice.shared.press(.home)
        assertAppIsBackgrounded()
        app.activate()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        XCTAssertFalse(app.staticTexts["caption.source.english"].exists)
        XCTAssertFalse(app.staticTexts["caption.translation.spanish"].exists)
        XCTAssertFalse(app.buttons["setup.startConversation"].isEnabled)
    }

    private let longEnglish = "Hello. Please speak slowly so I can understand each sentence. We can take a short break, ask another question, and make sure the translated words remain easy to read on this screen."
    private let longSpanish = "Hola. Por favor, hable despacio para que pueda entender cada frase. Podemos hacer una pausa, otra pregunta y comprobar que las palabras traducidas sigan siendo fáciles de leer en esta pantalla."
    private let slowLongArguments = ["--ui-testing-long-captions", "--ui-testing-slow-reveal"]

    /// The slow fixture allows at most 32 steps of 350 ms. Wait beyond that
    /// deadline without asking the app to expose its private animation state.
    @MainActor
    private func waitBeyondSlowReveal() {
        let deadline = Date().addingTimeInterval(12)
        let elapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 13), .completed)
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
        XCTAssertEqual(XCTWaiter.wait(for: reappearances, timeout: 12), .completed)
    }

    @MainActor
    func testLongCaptionsKeepFullAccessibilityAndStableWrappingDuringReveal() {
        openSample(arguments: slowLongArguments)
        // Capture before accessibility queries consume the partial-reveal window.
        let partialTranslation = app.staticTexts["caption.translation.spanish"].screenshot().pngRepresentation
        attachScreenshot("Long portrait captions — partial reveal")
        let source = app.staticTexts["caption.source.english"]
        let translation = app.staticTexts["caption.translation.spanish"]
        XCTAssertEqual(source.label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        let initialHeight = translation.frame.height
        XCTAssertGreaterThan(initialHeight, 0)

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
        assertAppIsBackgrounded()
        app.activate()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        assertCaptionsRemainAbsent()
    }

    @MainActor
    func testNewSampleTurnsDoNotOverwriteAnotherTurnsRevealingTranslation() {
        openSample(arguments: ["--ui-testing-slow-reveal"])
        completeSampleTurn("spanish")
        completeSampleTurn("english")
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
    func testLandscapeLargeTextKeepsControlsAndBothCaptionScrollViewsAccessible() throws {
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
        for identifier in ["speak.english", "speak.spanish", "conversation.stop",
                           "conversation.retry", "conversation.correct", "viewer.flip",
                           "conversation.clear", "conversation.setup"] {
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
        // The viewer is upright by default; only the operator can flip it.
        spanish.swipeUp()
        XCTAssertNotEqual(spanish.screenshot().pngRepresentation, spanishBeforeScroll,
                          "The upright Spanish viewer must scroll long content.")
        waitForScrollToSettle()
        let manualSourceY = source.frame.minY
        let manualTranslationY = translation.frame.minY
        let translationAfterManualScroll = try captionInteriorPixels(translation, inside: spanish)
        attachPNG(translationAfterManualScroll, name: "Landscape caption interior - settled baseline")
        attachScreenshot("Landscape largest text - settled manual scroll baseline")
        waitBeyondSlowReveal()
        XCTAssertEqual(source.label, longEnglish)
        XCTAssertEqual(translation.label, longSpanish)
        XCTAssertEqual(source.frame.minY, manualSourceY, accuracy: 2)
        XCTAssertEqual(translation.frame.minY, manualTranslationY, accuracy: 2)
        let translationAfterDeadline = try captionInteriorPixels(translation, inside: spanish)
        attachPNG(translationAfterDeadline, name: "Landscape caption interior - after reveal deadline")
        attachScreenshot("Landscape largest text - after reveal deadline")
        XCTAssertEqual(translationAfterDeadline, translationAfterManualScroll,
                       "Manual scrolling must expose the complete caption and stop subsequent reveal updates.")
        assertOperatorOwnsConversationControls()
        XCTAssertTrue(app.buttons["speak.english"].isHittable)
        XCTAssertTrue(app.buttons["speak.spanish"].isHittable)
        attachScreenshot("Landscape largest text - upright text-only viewer")
        app.buttons["viewer.flip"].tap()
        XCTAssertEqual(translation.label, longSpanish)
        XCTAssertTrue(spanish.isHittable)
        let screenFrame = app.frame
        let flippedViewport = spanish.frame.intersection(screenFrame)
        XCTAssertTrue(screenFrame.insetBy(dx: -2, dy: -2).contains(spanish.frame),
                      "The flipped Spanish caption viewport must remain within the screen.")
        // An element swipe on a rotated ScrollView can start at the system top
        // edge. Use app coordinates strictly inside the visible caption viewport.
        let dragArea = flippedViewport.insetBy(dx: 24, dy: 24)
            .intersection(screenFrame.insetBy(dx: 24, dy: 24))
        XCTAssertGreaterThan(dragArea.width, 0)
        XCTAssertGreaterThan(dragArea.height, 40,
                             "The flipped viewport must allow a meaningful interior drag.")
        let beforeFlippedScroll = try captionInteriorPixels(translation, inside: spanish)
        attachPNG(beforeFlippedScroll, name: "Flipped Spanish caption interior - before scroll")
        attachScreenshot("Landscape largest text - flipped viewer before interior scroll")
        let screenOrigin = app.coordinate(withNormalizedOffset: .zero)
        let dragStart = screenOrigin.withOffset(CGVector(
            dx: dragArea.midX - screenFrame.minX,
            dy: dragArea.minY + dragArea.height * 0.25 - screenFrame.minY))
        let dragEnd = screenOrigin.withOffset(CGVector(
            dx: dragArea.midX - screenFrame.minX,
            dy: dragArea.minY + dragArea.height * 0.75 - screenFrame.minY))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        waitForScrollToSettle()
        let afterFlippedScroll = try captionInteriorPixels(translation, inside: spanish)
        attachPNG(afterFlippedScroll, name: "Flipped Spanish caption interior - after scroll")
        attachScreenshot("Landscape largest text - flipped viewer after interior scroll")
        XCTAssertNotEqual(afterFlippedScroll, beforeFlippedScroll,
                          "The flipped Spanish viewer must scroll long captions within its viewport.")
        XCTAssertEqual(translation.label, longSpanish)
        assertOperatorOwnsConversationControls()
        attachScreenshot("Landscape largest text - operator flipped Spanish viewer")
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

    @MainActor
    private func assertOperatorOwnsConversationControls() {
        // Rotation and scrolling can briefly rebuild SwiftUI accessibility
        // containers. Resolve fresh queries while waiting for both panels.
        let panelsReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                app.descendants(matching: .any).matching(identifier: "panel.spanish").firstMatch.exists
                    && app.descendants(matching: .any).matching(identifier: "panel.english").firstMatch.exists
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [panelsReady], timeout: 5), .completed,
                       "Both language panels must remain accessible after layout changes.")
        let viewer = app.descendants(matching: .any).matching(identifier: "panel.spanish").firstMatch
        let operatorPanel = app.descendants(matching: .any).matching(identifier: "panel.english").firstMatch
        XCTAssertTrue(viewer.exists)
        XCTAssertTrue(operatorPanel.exists)
        XCTAssertEqual(viewer.buttons.count, 0, "The Spanish viewer must remain text-only.")
        let instructions = viewer.staticTexts["viewer.instructions"]
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertFalse(instructions.label.isEmpty)
        for identifier in ["speak.english", "speak.spanish", "conversation.stop",
                           "conversation.retry", "conversation.correct", "viewer.flip",
                           "conversation.clear", "conversation.setup"] {
            XCTAssertTrue(operatorPanel.buttons[identifier].exists,
                          "Only the English operator side may contain \(identifier).")
        }
    }

    @MainActor
    func testOperatorCanRetryTheSpanishDirectionWithoutChangingOlderEnglishText() {
        openSample()
        completeSampleTurn("spanish")
        XCTAssertTrue(app.buttons["conversation.retry"].isEnabled)
        app.buttons["conversation.retry"].tap()
        XCTAssertTrue(app.buttons["conversation.stop"].isEnabled)
        app.buttons["conversation.stop"].tap()
        waitForOperatorToBeReady()
        waitBeyondSlowReveal()
        let spanishSources = app.staticTexts.matching(identifier: "caption.source.spanish")
        let englishTranslations = app.staticTexts.matching(identifier: "caption.translation.english")
        XCTAssertGreaterThan(spanishSources.count, 0)
        XCTAssertGreaterThan(englishTranslations.count, 0)
        XCTAssertTrue(spanishSources.allElementsBoundByIndex.allSatisfy { $0.label == "¿Cómo está?" })
        XCTAssertTrue(englishTranslations.allElementsBoundByIndex.allSatisfy { $0.label == "How are you?" })
        // Revisit retained history instead of depending on LazyVStack materializing
        // an offscreen first turn immediately after the new sample arrives.
        app.scrollViews["captions.english"].swipeDown()
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, "Hello")
        assertOperatorOwnsConversationControls()
    }

    @MainActor
    func testCancellingTranscriptCorrectionDuringRevealKeepsOriginalCaptions() {
        openSample(arguments: slowLongArguments)
        app.buttons["conversation.correct"].tap()
        let editor = app.textViews["correction.transcript"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, longEnglish)
        editor.tap()
        editor.typeText(" Cancelled edit.")
        app.buttons["correction.cancel"].tap()
        XCTAssertFalse(editor.exists)
        waitBeyondSlowReveal()
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, longEnglish)
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, longSpanish)
        XCTAssertEqual(app.staticTexts.matching(identifier: "caption.source.english").count, 1)
        assertOperatorOwnsConversationControls()
    }

    @MainActor
    func testOperatorCanCorrectEachSourceLanguageWithAnExplicitSamplePreview() {
        openSample()
        let directions = [
            ("english", "spanish", "Hello", " Please speak slowly.",
             "Ejemplo de traducción. Este texto no se ha traducido; el micrófono está apagado."),
            ("spanish", "english", "¿Cómo está?", " Más despacio.",
             "Translation preview only. This edited text has not been translated; microphone is off.")
        ]
        for (sourceLanguage, targetLanguage, original, correction, preview) in directions {
            if sourceLanguage == "spanish" {
                app.buttons["conversation.clear"].tap()
                completeSampleTurn("spanish")
            }
            XCTAssertEqual(app.staticTexts["caption.source.\(sourceLanguage)"].label, original)
            app.buttons["conversation.correct"].tap()
            let editor = app.textViews["correction.transcript"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertEqual(editor.value as? String, original)
            editor.tap()
            editor.typeText(correction)
            // TextEditor cursor placement is native UI behavior. Verify the exact
            // entered value is applied, without assuming the initial caret position.
            let editedText = editor.value as? String
            XCTAssertNotNil(editedText)
            XCTAssertTrue(editedText?.contains(correction.trimmingCharacters(in: .whitespaces)) == true)
            app.buttons["correction.translate"].tap()
            XCTAssertFalse(editor.exists)
            XCTAssertEqual(app.staticTexts["caption.source.\(sourceLanguage)"].label,
                           editedText?.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertEqual(app.staticTexts["caption.translation.\(targetLanguage)"].label, preview,
                           "Sample editing must never claim that the microphone-off preview is a real translation.")
            XCTAssertEqual(app.staticTexts.matching(identifier: "caption.source.\(sourceLanguage)").count, 1)
            assertOperatorOwnsConversationControls()
        }
        attachScreenshot("WhippleChat corrected sample with explicit preview disclaimer")
    }

    @MainActor
    private func waitForOperatorToBeReady() {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: app.buttons["speak.english"])
        // Simulator accessibility snapshots can arrive after the final ten-
        // second poll even though the sample has already returned to idle.
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertTrue(app.buttons["speak.spanish"].isEnabled)
        XCTAssertFalse(app.buttons["conversation.stop"].isEnabled)
    }

    @MainActor
    private func completeSampleTurn(_ language: String) {
        app.buttons["speak.\(language)"].tap()
        XCTAssertTrue(app.buttons["conversation.stop"].isEnabled,
                      "The operator must stop a sample turn before its result arrives.")
        app.buttons["conversation.stop"].tap()
        waitForOperatorToBeReady()
    }

    @MainActor
    private func waitForViewerStage(_ text: String) {
        let stage = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", text),
            object: app.staticTexts["viewer.instructions"])
        XCTAssertEqual(XCTWaiter.wait(for: [stage], timeout: 6), .completed)
    }

    @MainActor
    func testOperatorStartStopShowsHonestSampleRecordingAndProcessingInstructions() {
        openSample(arguments: ["--ui-testing-slow-stages"])
        app.buttons["speak.english"].tap()
        XCTAssertTrue(app.buttons["conversation.stop"].isEnabled)
        let instructions = app.staticTexts["viewer.instructions"]
        XCTAssertTrue(instructions.label.contains("EJEMPLO. Micrófono apagado."))
        XCTAssertTrue(instructions.label.contains("El operador está hablando."))
        XCTAssertFalse(app.buttons["speak.spanish"].isEnabled)
        app.buttons["conversation.stop"].tap()
        waitForViewerStage("transcribiendo")
        XCTAssertFalse(app.buttons["conversation.stop"].isEnabled)
        attachScreenshot("WhippleChat sample - transcribing with operator controls")
        waitForViewerStage("traduciendo")
        XCTAssertTrue(instructions.label.contains("EJEMPLO. Micrófono apagado."))
        attachScreenshot("WhippleChat sample - translating with text-only viewer")
        waitForOperatorToBeReady()

        app.buttons["speak.spanish"].tap()
        XCTAssertTrue(app.buttons["conversation.stop"].isEnabled)
        XCTAssertTrue(instructions.label.contains("Hable despacio y con claridad."))
        XCTAssertTrue(instructions.label.contains("EJEMPLO. Micrófono apagado."))
        XCTAssertFalse(app.staticTexts["caption.source.spanish"].exists)
        app.buttons["conversation.stop"].tap()
        waitForOperatorToBeReady()
        XCTAssertEqual(app.staticTexts["caption.source.spanish"].label, "¿Cómo está?")
        XCTAssertEqual(app.staticTexts["caption.translation.english"].label, "How are you?")
        assertOperatorOwnsConversationControls()
    }

    @MainActor
    func testClearAndBackgroundCancelPendingSampleRecognitionAndTranslation() {
        openSample(arguments: ["--ui-testing-slow-stages"])
        app.buttons["speak.spanish"].tap()
        app.buttons["conversation.stop"].tap()
        waitForViewerStage("transcribiendo")
        app.buttons["conversation.clear"].tap()
        assertCaptionsRemainAbsent()
        XCTAssertTrue(app.buttons["speak.english"].isEnabled)
        XCTAssertFalse(app.buttons["conversation.stop"].isEnabled)
        XCTAssertFalse(app.buttons["conversation.retry"].isEnabled)

        app.buttons["speak.spanish"].tap()
        app.buttons["conversation.stop"].tap()
        waitForViewerStage("traduciendo")
        XCUIDevice.shared.press(.home)
        assertAppIsBackgrounded()
        app.activate()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        assertCaptionsRemainAbsent()
    }

    @MainActor
    func testBackgroundingTranscriptCorrectionDiscardsTheDraftAndRequiresSetup() {
        openSample()
        app.buttons["conversation.correct"].tap()
        let editor = app.textViews["correction.transcript"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" Discard this draft.")
        let draft = editor.value as? String
        XCTAssertTrue(draft?.contains("Discard this draft.") == true)

        XCUIDevice.shared.press(.home)
        assertAppIsBackgrounded()
        app.activate()
        XCTAssertTrue(app.buttons["setup.startSample"].waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
        XCTAssertFalse(app.staticTexts["demo.label"].exists)
        XCTAssertFalse(app.staticTexts["caption.source.english"].exists)
        XCTAssertFalse(app.staticTexts["caption.translation.spanish"].exists)
        attachScreenshot("Whipple Chat setup after correction draft was discarded")

        revealSampleButton().tap()
        XCTAssertTrue(app.staticTexts["demo.label"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["caption.source.english"].label, "Hello")
        XCTAssertEqual(app.staticTexts["caption.translation.spanish"].label, "Hola")
        XCTAssertEqual(app.staticTexts.matching(identifier: "caption.source.english").count, 1)
        XCTAssertFalse(app.staticTexts[draft ?? "Discard this draft."].exists)
        assertOperatorOwnsConversationControls()
    }

    @MainActor
    private func assertAppIsBackgrounded() {
        func waitUntilForegroundEnds(timeout: TimeInterval) -> Bool {
            let leftForeground = XCTNSPredicateExpectation(
                predicate: NSPredicate { [self] _, _ in app.state != .runningForeground },
                object: nil)
            return XCTWaiter.wait(for: [leftForeground], timeout: timeout) == .completed
        }
        var leftForeground = waitUntilForegroundEnds(timeout: 10)
        if !leftForeground && app.state == .runningForeground {
            // The first Home event can be lost during a cold simulator launch.
            XCUIDevice.shared.press(.home)
            leftForeground = waitUntilForegroundEnds(timeout: 10)
        }
        XCTAssertTrue(leftForeground, "Home must move the app out of the foreground before reactivation.")
        XCTAssertNotEqual(app.state, .notRunning, "Backgrounding must preserve the running app process.")
        XCTAssertNotEqual(app.state, .unknown, "The background lifecycle state must be observable.")
        // Each caller reactivates the app and checks setup plus cleared private
        // conversation data, so leaving the foreground alone is insufficient.
    }

    @MainActor
    private func waitForScrollToSettle() {
        let deadline = Date().addingTimeInterval(2)
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed)
    }

    /// Application/element captures can retain portrait cropping after rotation.
    /// Normalize a full-screen capture into current screen coordinates, then
    /// compare only visible caption ink, excluding system UI and the scroll bar.
    @MainActor
    private func captionInteriorPixels(_ caption: XCUIElement, inside scroll: XCUIElement) throws -> Data {
        let screenImage = XCUIScreen.main.screenshot().image
        let rawImage = try XCTUnwrap(screenImage.cgImage)
        let screenFrame = app.frame
        var visible = caption.frame.intersection(scroll.frame).intersection(screenFrame)
            .insetBy(dx: 4, dy: 4)
        visible.size.width -= 16 // Right-side scroll indicator and its fading edge.
        XCTAssertGreaterThan(visible.width, 0, "A caption interior must be visible for pixel validation.")
        XCTAssertGreaterThan(visible.height, 0, "A caption interior must be visible for pixel validation.")

        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(max(rawImage.width, rawImage.height))
            / max(screenFrame.width, screenFrame.height)
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: screenFrame.size, format: format).image { _ in
            screenImage.draw(in: CGRect(origin: .zero, size: screenFrame.size))
        }
        let pixels = CGRect(x: (visible.minX - screenFrame.minX) * format.scale,
                            y: (visible.minY - screenFrame.minY) * format.scale,
                            width: visible.width * format.scale,
                            height: visible.height * format.scale).integral
        let normalizedPixels = try XCTUnwrap(normalized.cgImage)
        let captionPixels = try XCTUnwrap(normalizedPixels.cropping(to: pixels))
        return try XCTUnwrap(UIImage(cgImage: captionPixels).pngData())
    }

    @MainActor
    private func attachPNG(_ pixels: Data, name: String) {
        let attachment = XCTAttachment(data: pixels, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
