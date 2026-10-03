import XCTest
@testable import TableTalkCore

final class AudioSamplesTests: XCTestCase {
    func testEmptyAndSilentInputNeverDecode() {
        var audio = AudioSamples()
        XCTAssertEqual(audio.rms, 0)
        XCTAssertFalse(audio.worthDecoding)
        audio.append(Array(repeating: 0, count: 16_000))
        XCTAssertEqual(audio.seconds, 1)
        XCTAssertFalse(audio.worthDecoding)
    }

    func testHalfSecondBoundary() {
        var audio = AudioSamples()
        audio.append(Array(repeating: 0.2, count: 7_999))
        XCTAssertFalse(audio.worthDecoding)
        audio.append([0.2])
        XCTAssertEqual(audio.seconds, 0.5)
        XCTAssertTrue(audio.worthDecoding)
    }

    func testRMSBoundary() {
        var quiet = AudioSamples()
        quiet.append(Array(repeating: 0.00199, count: 8_000))
        XCTAssertFalse(quiet.worthDecoding)
        var audible = AudioSamples()
        audible.append(Array(repeating: 0.002, count: 8_000))
        XCTAssertTrue(audible.worthDecoding)
        XCTAssertEqual(audible.rms, 0.002, accuracy: 0.000000001)
    }

    func testTwelveSecondCapAndDiscardedSamplesDoNotAffectRMS() {
        var audio = AudioSamples()
        audio.append(Array(repeating: 0.25, count: 16_000 * 15))
        XCTAssertEqual(audio.count, 192_000)
        XCTAssertEqual(audio.samples.count, 192_000)
        XCTAssertEqual(audio.seconds, 12)
        XCTAssertTrue(audio.isFull)
        audio.append(Array(repeating: 1, count: 1_000))
        XCTAssertEqual(audio.rms, 0.25, accuracy: 0.000001)
    }

    func testRMSAccumulatesAcrossChunks() {
        var audio = AudioSamples()
        audio.append(Array(repeating: 0.5, count: 4_000))
        audio.append(Array(repeating: -0.5, count: 4_000))
        XCTAssertEqual(audio.rms, 0.5, accuracy: 0.000001)
        XCTAssertTrue(audio.worthDecoding)
    }

    func testMalformedPCMIsFiniteAndClipped() {
        var audio = AudioSamples()
        audio.append([.nan, .infinity, -.infinity, 2, -2])
        XCTAssertEqual(audio.samples, [0, 0, 0, 1, -1])
        XCTAssertTrue(audio.rms.isFinite)
    }

    func testClearRemovesAudioAndAllowsReuse() {
        var audio = AudioSamples()
        audio.append(Array(repeating: 0.5, count: 192_000))
        audio.clear()
        XCTAssertTrue(audio.samples.isEmpty)
        XCTAssertEqual(audio.count, 0)
        XCTAssertEqual(audio.rms, 0)
        XCTAssertEqual(audio.seconds, 0)
        XCTAssertFalse(audio.isFull)
        XCTAssertFalse(audio.worthDecoding)
        audio.append(Array(repeating: -1, count: 8_000))
        XCTAssertEqual(audio.rms, 1)
        XCTAssertTrue(audio.worthDecoding)
    }
}
