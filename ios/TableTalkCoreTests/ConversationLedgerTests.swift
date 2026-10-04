import XCTest
@testable import TableTalkCore

final class ConversationLedgerTests: XCTestCase {
    func testEachPanelPrioritizesItsLanguage() throws {
        for sourceLanguage in SourceLanguage.allCases {
            var ledger = ConversationLedger()
            let original = sourceLanguage == .english ? "How are you?" : "¿Cómo estás?"
            let translated = sourceLanguage == .english ? "¿Cómo estás?" : "How are you?"
            let id = try XCTUnwrap(ledger.addSource(expected: ledger.generation, language: sourceLanguage, source: original))
            XCTAssertEqual(ledger.turns[0].text(for: sourceLanguage), original)
            XCTAssertNil(ledger.turns[0].text(for: sourceLanguage.other))
            XCTAssertTrue(ledger.finish(expected: ledger.generation, id: id, translation: translated, failed: false))
            XCTAssertEqual(ledger.turns[0].text(for: sourceLanguage), original)
            XCTAssertEqual(ledger.turns[0].text(for: sourceLanguage.other), translated)
        }
    }

    func testClearRejectsRecognitionAndTranslationFromPreviousConversation() throws {
        var ledger = ConversationLedger()
        let oldGeneration = ledger.generation
        let oldID = try XCTUnwrap(ledger.addSource(expected: oldGeneration, language: .english, source: "Old turn"))
        ledger.clear()
        let newID = try XCTUnwrap(ledger.addSource(expected: ledger.generation, language: .spanish, source: "Nueva conversación"))
        XCTAssertNotEqual(newID, oldID)
        XCTAssertFalse(ledger.isCurrent(oldGeneration))
        XCTAssertNil(ledger.addSource(expected: oldGeneration, language: .english, source: "Late recognition"))
        XCTAssertFalse(ledger.finish(expected: oldGeneration, id: oldID, translation: "Late translation", failed: false))
        XCTAssertFalse(ledger.finish(expected: ledger.generation, id: oldID, translation: "Wrong turn", failed: false))
        XCTAssertEqual(ledger.turns.map(\.source), ["Nueva conversación"])
        XCTAssertNil(ledger.turns[0].translation)
    }

    func testInvalidateRejectsWorkWithoutDiscardingExistingOriginal() throws {
        var ledger = ConversationLedger()
        let generation = ledger.generation
        let id = try XCTUnwrap(ledger.addSource(expected: generation, language: .english, source: "Keep original"))
        ledger.invalidate()
        XCTAssertFalse(ledger.finish(expected: generation, id: id, translation: "Late result", failed: false))
        XCTAssertNil(ledger.addSource(expected: generation, language: .spanish, source: "Late recognition"))
        XCTAssertEqual(ledger.turns.first?.source, "Keep original")
    }

    func testFailureKeepsOriginalAndDoesNotShowPartialTranslation() throws {
        var ledger = ConversationLedger()
        let id = try XCTUnwrap(ledger.addSource(expected: 0, language: .spanish, source: "Me preocupa mi familia."))
        XCTAssertTrue(ledger.finish(expected: 0, id: id, translation: "Untrusted partial", failed: true))
        XCTAssertEqual(ledger.turns[0].source, "Me preocupa mi familia.")
        XCTAssertTrue(ledger.turns[0].translationFailed)
        XCTAssertNil(ledger.turns[0].text(for: .english))
    }

    func testEmptySuccessfulTranslationIsAnExplicitFailure() throws {
        let translations: [String?] = [nil, "", " \n\t"]
        for translation in translations {
            var ledger = ConversationLedger()
            let id = try XCTUnwrap(ledger.addSource(expected: 0, language: .english, source: "Original"))
            XCTAssertTrue(ledger.finish(expected: 0, id: id, translation: translation, failed: false))
            XCTAssertTrue(ledger.turns[0].translationFailed)
            XCTAssertNil(ledger.turns[0].translation)
            XCTAssertEqual(ledger.turns[0].source, "Original")
        }
    }

    func testHistoryEvictsOldestAndRejectsItsLateTranslation() throws {
        var ledger = ConversationLedger()
        let firstID = try XCTUnwrap(ledger.addSource(expected: 0, language: .english, source: "First"))
        for index in 0..<50 {
            XCTAssertNotNil(ledger.addSource(expected: 0, language: .english, source: "Turn \(index)"))
        }
        XCTAssertEqual(ledger.turns.count, 12)
        XCTAssertEqual(ledger.turns.first?.source, "Turn 38")
        XCTAssertEqual(ledger.turns.last?.source, "Turn 49")
        XCTAssertFalse(ledger.finish(expected: 0, id: firstID, translation: "Too late", failed: false))
    }

    func testWhitespaceAndValueSnapshots() throws {
        var ledger = ConversationLedger()
        XCTAssertNil(ledger.addSource(expected: 0, language: .spanish, source: " \n\t "))
        let id = try XCTUnwrap(ledger.addSource(expected: 0, language: .english, source: " \nHello\t "))
        let before = ledger.turns
        XCTAssertTrue(ledger.finish(expected: 0, id: id, translation: " Hola \n", failed: false))
        XCTAssertEqual(ledger.turns[0].translation, "Hola")
        XCTAssertEqual(before[0].source, "Hello")
        XCTAssertNil(before[0].translation)
        ledger.clear()
        XCTAssertTrue(ledger.turns.isEmpty)
    }

    func testLanguagesHaveStableCodesAndNativeLabels() {
        XCTAssertEqual(SourceLanguage.english.code, "en")
        XCTAssertEqual(SourceLanguage.spanish.code, "es")
        XCTAssertEqual(SourceLanguage.english.displayName, "English")
        XCTAssertEqual(SourceLanguage.spanish.displayName, "Español")
        XCTAssertEqual(SourceLanguage.english.other, .spanish)
        XCTAssertEqual(SourceLanguage.spanish.other, .english)
    }
}
