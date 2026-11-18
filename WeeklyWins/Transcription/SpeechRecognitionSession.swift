import Foundation

typealias SpeechRecognitionSession = SpeechRecognitionResultSession<String>

@MainActor
final class SpeechRecognitionResultSession<Output: Sendable> {
    typealias Completion = @Sendable (Result<Output, Error>) -> Void
    typealias Cancellation = @MainActor () -> Void

    private var continuation: CheckedContinuation<Output, Error>?
    private var cancelRecognition: Cancellation?
    private var hasStarted = false

    func run(start: (@escaping Completion) -> Cancellation) async throws -> Output {
        guard !hasStarted else { throw TranscriptionError.alreadyProcessing }
        hasStarted = true
        defer { cancelRecognition = nil }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                cancelRecognition = start { [weak self] result in
                    Task { @MainActor in self?.finish(result) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Output, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let cancel = cancelRecognition
        cancelRecognition = nil
        cancel?()
        continuation.resume(with: result)
    }
}
