import Foundation

struct RecorderSyncClient {
    struct Entry: Decodable {
        let id: UUID
        let recordedAt: Date
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://192.168.4.1")!, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 30
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func synchronizeClock() async throws {
        let unixTime = String(Int(Date.now.timeIntervalSince1970))
        _ = try await request("clock", method: "POST", query: URLQueryItem(name: "unix", value: unixTime), status: 204)
    }

    func pendingRecordings() async throws -> [Entry] {
        let data = try await request("recordings", status: 200)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entries = try decoder.decode([Entry].self, from: data)
        guard entries.allSatisfy({ (1_704_067_200..<4_102_444_800).contains($0.recordedAt.timeIntervalSince1970) }) else {
            throw RecorderSyncError.invalidRecording
        }
        return entries.sorted { $0.recordedAt < $1.recordedAt }
    }

    func audio(for id: UUID) async throws -> Data {
        let data = try await request("recording", query: URLQueryItem(name: "id", value: id.uuidString), status: 200)
        let maximumBytes = 90 * 16_000 * 2 + 44
        guard data.count <= maximumBytes, data.count > 44,
              data.prefix(4).elementsEqual("RIFF".utf8), data[8..<12].elementsEqual("WAVE".utf8) else {
            throw RecorderSyncError.invalidRecording
        }
        return data
    }

    func acknowledge(_ id: UUID) async throws {
        _ = try await request("recording", method: "DELETE", query: URLQueryItem(name: "id", value: id.uuidString), status: 204)
    }

    private func request(_ path: String, method: String = "GET", query: URLQueryItem? = nil, status: Int) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let query { components?.queryItems = [query] }
        guard let endpoint = components?.url else { throw RecorderSyncError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("1", forHTTPHeaderField: "X-WeeklyWins-Recorder")
        let (data, response) = try await session.data(for: request, delegate: LocalRecorderSessionDelegate())
        guard (response as? HTTPURLResponse)?.statusCode == status else { throw RecorderSyncError.invalidResponse }
        return data
    }
}

private final class LocalRecorderSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum RecorderSyncError: LocalizedError {
    case busy, invalidResponse, invalidRecording

    var errorDescription: String? {
        switch self {
        case .busy: return "Синхронизация уже идёт."
        case .invalidResponse: return "Диктофон вернул неожиданный ответ. Проверьте подключение к его Wi-Fi."
        case .invalidRecording: return "Не удалось прочитать аудиозапись с диктофона."
        }
    }
}
