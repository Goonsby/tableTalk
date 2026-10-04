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

    func testCorrectionKeepsIdentityAndLanguageAndResetsTranslationInBothDirections() throws {
        for language in SourceLanguage.allCases {
            for initiallyFailed in [false, true] {
                var ledger = ConversationLedger()
                let original = language == .english ? "I said Tuesday." : "Dije martes."
                let corrected = language == .english ? "I said Thursday." : "Dije jueves."
                let generation = ledger.generation
                let id = try XCTUnwrap(ledger.addSource(expected: generation, language: language, source: original))
                XCTAssertTrue(ledger.finish(expected: generation, id: id, translation: "Old translation", failed: initiallyFailed))
                let snapshot = ledger.turns

                let revisedGeneration = try XCTUnwrap(ledger.reviseLastSource(expected: generation,
                    source: " \n\(corrected)\t "))

                XCTAssertEqual(revisedGeneration, generation &+ 1)
                XCTAssertEqual(ledger.generation, revisedGeneration)
                XCTAssertEqual(ledger.turns.count, 1)
                XCTAssertEqual(ledger.turns[0].id, id)
                XCTAssertEqual(ledger.turns[0].sourceLanguage, language)
                XCTAssertEqual(ledger.turns[0].source, corrected)
                XCTAssertEqual(ledger.turns[0].text(for: language), corrected)
                XCTAssertNil(ledger.turns[0].translation)
                XCTAssertFalse(ledger.turns[0].translationFailed)
                XCTAssertEqual(snapshot[0].source, original)
                XCTAssertEqual(snapshot[0].translation, initiallyFailed ? nil : "Old translation")
                XCTAssertEqual(snapshot[0].translationFailed, initiallyFailed)

                XCTAssertTrue(ledger.finish(expected: revisedGeneration, id: id,
                    translation: "Corrected translation", failed: false))
                XCTAssertEqual(ledger.turns[0].text(for: language.other), "Corrected translation")
            }
        }
    }

    func testCorrectionRejectsOldRecognitionAndTranslationResults() throws {
        var ledger = ConversationLedger()
        let originalGeneration = ledger.generation
        let id = try XCTUnwrap(ledger.addSource(expected: originalGeneration, language: .english, source: "Original"))
        let correctedGeneration = try XCTUnwrap(ledger.reviseLastSource(expected: originalGeneration, source: "Corrected"))
        let correctedTurns = ledger.turns

        XCTAssertFalse(ledger.isCurrent(originalGeneration))
        XCTAssertNil(ledger.addSource(expected: originalGeneration, language: .spanish, source: "Late recognition"))
        XCTAssertFalse(ledger.finish(expected: originalGeneration, id: id, translation: "Old translation", failed: false))
        XCTAssertFalse(ledger.finish(expected: originalGeneration, id: id, translation: nil, failed: true))
        XCTAssertNil(ledger.reviseLastSource(expected: originalGeneration, source: "Stale correction"))
        XCTAssertEqual(ledger.generation, correctedGeneration)
        XCTAssertEqual(ledger.turns, correctedTurns)
        XCTAssertTrue(ledger.finish(expected: correctedGeneration, id: id, translation: "Current translation", failed: false))
    }

    func testEmptyAndStaleCorrectionsDoNotMutateLedger() throws {
        var ledger = ConversationLedger()
        let id = try XCTUnwrap(ledger.addSource(expected: ledger.generation, language: .spanish, source: "Original"))
        XCTAssertTrue(ledger.finish(expected: ledger.generation, id: id, translation: "Existing translation", failed: false))
        let staleGeneration = ledger.generation
        ledger.invalidate()
        let generation = ledger.generation
        let snapshot = ledger.turns

        for source in ["", " \n\t ", "\u{00A0}\u{2003}"] {
            XCTAssertNil(ledger.reviseLastSource(expected: generation, source: source))
            XCTAssertEqual(ledger.generation, generation)
            XCTAssertEqual(ledger.turns, snapshot)
        }
        XCTAssertNil(ledger.reviseLastSource(expected: staleGeneration, source: "A valid but stale correction"))
        XCTAssertEqual(ledger.generation, generation)
        XCTAssertEqual(ledger.turns, snapshot)
        XCTAssertEqual(ledger.addSource(expected: generation, language: .english, source: "Next turn"), id + 1)
    }

    func testCorrectionWithoutHistoryDoesNotCreateTurnOrInvalidateWork() throws {
        var ledger = ConversationLedger()
        XCTAssertNil(ledger.reviseLastSource(expected: 0, source: "No original exists"))
        XCTAssertEqual(ledger.generation, 0)
        XCTAssertTrue(ledger.turns.isEmpty)
        let id = try XCTUnwrap(ledger.addSource(expected: 0, language: .english, source: "First turn"))
        XCTAssertEqual(id, 1)
        ledger.clear()
        let clearedGeneration = ledger.generation
        XCTAssertNil(ledger.reviseLastSource(expected: clearedGeneration, source: "History was cleared"))
        XCTAssertEqual(ledger.generation, clearedGeneration)
        XCTAssertTrue(ledger.turns.isEmpty)
    }

    func testCorrectionPreservesBoundedHistoryAndItsValueSnapshot() throws {
        var ledger = ConversationLedger()
        for index in 0..<20 {
            let id = try XCTUnwrap(ledger.addSource(expected: ledger.generation,
                language: index.isMultiple(of: 2) ? .english : .spanish, source: "Turn \(index)"))
            XCTAssertTrue(ledger.finish(expected: ledger.generation, id: id,
                translation: "Translation \(index)", failed: false))
        }
        let snapshot = ledger.turns
        let lastID = try XCTUnwrap(snapshot.last?.id)
        let newGeneration = try XCTUnwrap(ledger.reviseLastSource(expected: ledger.generation,
            source: "  Corrected  latest\nturn  "))

        XCTAssertEqual(ledger.turns.count, ConversationLedger.maxTurns)
        XCTAssertEqual(ledger.turns.map(\.id), snapshot.map(\.id))
        XCTAssertEqual(Array(ledger.turns.dropLast()), Array(snapshot.dropLast()))
        XCTAssertEqual(ledger.turns.last?.source, "Corrected  latest\nturn")
        XCTAssertEqual(snapshot.last?.source, "Turn 19")
        XCTAssertEqual(snapshot.last?.translation, "Translation 19")
        XCTAssertEqual(ledger.addSource(expected: newGeneration, language: .english, source: "Next turn"), lastID + 1)
        XCTAssertEqual(ledger.turns.count, ConversationLedger.maxTurns)
        XCTAssertEqual(ledger.turns.first?.id, snapshot[1].id)
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
