import XCTest
@testable import TableTalkCore

final class CaptionRevealTests: XCTestCase {
    func testRevealPreservesAccentedAndEmojiGraphemesWithPunctuation() {
        let text = "Cafe\u{301}, 👩🏽‍💻 ¿qué? 🇲🇬!"
        var reveal = CaptionReveal(text: text)
        XCTAssertEqual(reveal.visibleCharacters, 0)
        XCTAssertEqual(reveal.visibleText, "")
        XCTAssertEqual(reveal.hiddenText, text)

        let expected = ["Cafe\u{301}, ", "Cafe\u{301}, 👩🏽‍💻 ",
                        "Cafe\u{301}, 👩🏽‍💻 ¿qué? ", text]
        for prefix in expected {
            reveal.advance()
            XCTAssertEqual(reveal.visibleText, prefix)
            XCTAssertEqual(reveal.visibleCharacters, prefix.count)
            XCTAssertEqual(reveal.visibleText + reveal.hiddenText, text)
        }
        XCTAssertTrue(reveal.isComplete)
    }

    func testWhitespaceAndNewlinesRemainInTheirOriginalPositions() {
        let text = "\tHello,  \nworld!\t "
        var reveal = CaptionReveal(text: text)
        reveal.advance()
        XCTAssertEqual(reveal.visibleText, "\tHello,  \n")
        XCTAssertEqual(reveal.hiddenText, "world!\t ")
        XCTAssertFalse(reveal.isComplete)
        reveal.advance()
        XCTAssertEqual(reveal.visibleText, text)
        XCTAssertEqual(reveal.hiddenText, "")
        XCTAssertEqual(reveal.text, text)
        XCTAssertTrue(reveal.isComplete)
    }

    func testEmptyAndWhitespaceOnlyCaptionsAreImmediatelyComplete() {
        for text in ["", " \n\t", "\u{00A0}\u{2003}\r\n"] {
            var reveal = CaptionReveal(text: text)
            let initial = reveal
            XCTAssertTrue(reveal.isComplete)
            XCTAssertEqual(reveal.visibleCharacters, text.count)
            XCTAssertEqual(reveal.visibleText, text)
            XCTAssertEqual(reveal.hiddenText, "")
            reveal.advance()
            reveal.finish()
            XCTAssertEqual(reveal, initial)
        }
    }

    func testLongCaptionAdvancesMonotonicallyAtWordBoundariesWithin32Ticks() {
        let words = (0..<500).map { "word\($0)!" }
        let text = words.joined(separator: " \n\t") + "\n "
        var reveal = CaptionReveal(text: text)
        var ticks = 0
        var previousCount = 0
        var previousWords = 0
        while !reveal.isComplete && ticks < 32 {
            reveal.advance()
            ticks += 1
            XCTAssertGreaterThan(reveal.visibleCharacters, previousCount)
            let visibleWords = reveal.visibleText.split(whereSeparator: { $0.isWhitespace })
            XCTAssertGreaterThan(visibleWords.count, previousWords)
            XCTAssertEqual(visibleWords.map(String.init), Array(words.prefix(visibleWords.count)))
            XCTAssertEqual(reveal.visibleText + reveal.hiddenText, text)
            XCTAssertEqual(reveal.text, text)
            previousCount = reveal.visibleCharacters
            previousWords = visibleWords.count
        }
        XCTAssertTrue(reveal.isComplete)
        XCTAssertLessThanOrEqual(ticks, 32)
        XCTAssertEqual(reveal.visibleCharacters, text.count)
        XCTAssertEqual(reveal.visibleText, text)
    }

    func testUnbrokenCaptionRevealsAsOneCompleteWord() {
        let text = String(repeating: "界", count: 1_000) + "!"
        var reveal = CaptionReveal(text: text)
        reveal.advance()
        XCTAssertTrue(reveal.isComplete)
        XCTAssertEqual(reveal.visibleText, text)
    }

    func testDisabledRevealShowsFullTextImmediatelyAndRemainsStable() {
        let text = "  Hola, 👋🏽\n¿cómo estás?  "
        var reveal = CaptionReveal(text: text, enabled: false)
        let initial = reveal
        XCTAssertTrue(reveal.isComplete)
        XCTAssertEqual(reveal.visibleCharacters, text.count)
        XCTAssertEqual(reveal.visibleText, text)
        XCTAssertEqual(reveal.hiddenText, "")
        reveal.advance()
        reveal.finish()
        XCTAssertEqual(reveal, initial)
    }

    func testFinishShowsOriginalCaptionAndSubsequentCallsAreStable() {
        let text = "One  two\nthree!  "
        var reveal = CaptionReveal(text: text)
        let before = reveal
        reveal.advance()
        XCTAssertEqual(before.visibleText, "")
        XCTAssertFalse(reveal.isComplete)
        reveal.finish()
        XCTAssertTrue(reveal.isComplete)
        XCTAssertEqual(reveal.text, text)
        XCTAssertEqual(reveal.visibleCharacters, text.count)
        XCTAssertEqual(reveal.visibleText, text)
        XCTAssertEqual(reveal.hiddenText, "")
        let completed = reveal
        reveal.finish()
        reveal.advance()
        XCTAssertEqual(reveal, completed)
    }
}
