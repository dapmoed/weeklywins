import XCTest
@testable import WeeklyWins

final class LegacySpeechResultAccumulatorTests: XCTestCase {
    @MainActor
    func testTimedPartialSurvivesTheFinalUtteranceReset() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        XCTAssertNil(try accumulator.update(result("первое дело", times: [0, 1]), isFinal: false))
        XCTAssertNil(try accumulator.update(result("второе", times: [0], duration: 0), isFinal: false))
        let combined = try XCTUnwrap(accumulator.update(result("второе дело", times: [3, 4]), isFinal: true))
        XCTAssertEqual(combined.text, "первое дело второе дело")
        XCTAssertEqual(combined.words.count, 4)
        XCTAssertEqual(combined.words.map(\.timestamp), [0, 1, 3, 4])
        try combined.validate()
    }

    @MainActor
    func testRevisedCumulativeFinalReplacesEarlierPartial() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("первое бело", times: [0, 1]), isFinal: false)
        let combined = try XCTUnwrap(accumulator.update(result("первое дело", times: [0, 1]), isFinal: true))
        XCTAssertEqual(combined.text, "первое дело")
        XCTAssertEqual(combined.words.count, 2)
    }

    @MainActor
    func testShiftedFirstWordDoesNotDuplicateItsPreviousVersion() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("первое дело", times: [0, 1], duration: 0.4), isFinal: false)
        let combined = try XCTUnwrap(accumulator.update(
            result("первое дело", times: [0.2, 1.2], duration: 0.4), isFinal: true
        ))
        XCTAssertEqual(combined.text, "первое дело")
        XCTAssertEqual(combined.words.count, 2)
    }

    @MainActor
    func testCorrectedSnapshotAtAbuttingBoundaryKeepsTheEarlierWord() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("первое бело", times: [0, 1], duration: 1), isFinal: false)
        let corrected = try XCTUnwrap(accumulator.update(result("дело", times: [1], duration: 1), isFinal: true))
        XCTAssertEqual(corrected.text, "первое дело")
        XCTAssertEqual(corrected.words.count, 2)
    }

    @MainActor
    func testRollingSnapshotRetainsPrefixAndValidOriginalOffsets() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("  первое дело третье", times: [0, 1, 2]), isFinal: false)
        let combined = try XCTUnwrap(accumulator.update(result("дело исправлено", times: [1, 2]), isFinal: true))
        XCTAssertEqual(combined.text, "  первое дело исправлено")
        XCTAssertEqual(try combined.excerpt(from: 0, to: 3), "первое дело исправлено")
        XCTAssertEqual(combined.words.map(\.timestamp), [0, 1, 2])
    }

    @MainActor
    func testFinalWithoutTimingPreservesShortRecognition() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        let final = result("да", times: [0], duration: 0)
        XCTAssertNil(try accumulator.update(final, isFinal: false))
        XCTAssertEqual(try accumulator.update(final, isFinal: true)?.text, "да")
    }

    @MainActor
    func testUntimedConflictingFinalDoesNotEraseTimedSpeech() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("важное дело", times: [0, 1]), isFinal: false)
        XCTAssertThrowsError(try accumulator.update(result("да", times: [0], duration: 0), isFinal: true))
    }

    @MainActor
    func testEmptyFinalAfterTimedSpeechKeepsTheRecognizedUtterance() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("важное дело", times: [0, 1]), isFinal: false)
        let empty = LegacySpeechTranscription.Transcript(text: "", words: [])
        XCTAssertEqual(try accumulator.update(empty, isFinal: true)?.text, "важное дело")
    }

    @MainActor
    func testIdenticalUntimedFinalUsesPreviouslyEstablishedTiming() async throws {
        let accumulator = LegacySpeechResultAccumulator()
        _ = try accumulator.update(result("важное дело", times: [0, 1]), isFinal: false)
        let final = try XCTUnwrap(accumulator.update(result("важное дело", times: [0, 0], duration: 0), isFinal: true))
        XCTAssertEqual(final.words.map(\.timestamp), [0, 1])
    }

    private func result(_ text: String, times: [Double], duration: Double = 0.2) -> LegacySpeechTranscription.Transcript {
        let source = text as NSString
        var location = 0
        let words = text.split(separator: " ").enumerated().map { index, word in
            let range = source.range(of: String(word), range: NSRange(location: location, length: source.length - location))
            location = NSMaxRange(range)
            return LegacySpeechTranscription.Word(range: range, timestamp: times[index], duration: duration)
        }
        return .init(text: text, words: words)
    }
}
