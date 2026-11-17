import XCTest
@testable import WeeklyWins

final class SpeechRecognitionSessionTests: XCTestCase {
    @MainActor
    func testCancellationBeforeStartDoesNotStartRecognition() async {
        let session = SpeechRecognitionSession()
        var didStart = false
        let task = Task {
            try await session.run { _ in
                didStart = true
                return {}
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled recognition should throw.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(didStart)
    }

    @MainActor
    func testCancellationFinishesWaiterAndStopsRecognitionOnce() async throws {
        let session = SpeechRecognitionSession()
        let started = expectation(description: "Recognition started")
        var callback: SpeechRecognitionSession.Completion?
        var cancellations = 0
        let task = Task {
            try await session.run { completion in
                callback = completion
                started.fulfill()
                return { cancellations += 1 }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled recognition should throw.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cancellations, 1)
        callback?(.success("Late result"))
        await Task.yield()
        XCTAssertEqual(cancellations, 1)
    }

    @MainActor
    func testDuplicateCallbacksCompleteOnlyOnce() async throws {
        let session = SpeechRecognitionSession()
        let started = expectation(description: "Recognition started")
        var callback: SpeechRecognitionSession.Completion?
        var cancellations = 0
        let task = Task {
            try await session.run { completion in
                callback = completion
                started.fulfill()
                return { cancellations += 1 }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        callback?(.success("First"))
        callback?(.success("Duplicate"))
        let result = try await task.value
        XCTAssertEqual(result, "First")
        XCTAssertEqual(cancellations, 1)
    }
}
