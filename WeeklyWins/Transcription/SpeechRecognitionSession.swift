import Foundation

@MainActor
final class SpeechRecognitionSession {
    typealias Completion = @Sendable (Result<String, Error>) -> Void
    typealias Cancellation = @MainActor () -> Void

    private var continuation: CheckedContinuation<String, Error>?
    private var cancelRecognition: Cancellation?
    private var hasStarted = false

    func run(start: (@escaping Completion) -> Cancellation) async throws -> String {
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

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let cancel = cancelRecognition
        cancelRecognition = nil
        cancel?()
        continuation.resume(with: result)
    }
}
