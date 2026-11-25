import Foundation

enum RecorderBLECommand: UInt8 {
    case clock = 1, list, open, read, acknowledge
}

@MainActor
struct RecorderSyncClient {
    struct Entry {
        let id: UUID
        let recordedAt: Date
    }

    static let maximumAudioBytes = 90 * 16_000 * 2 + 44
    nonisolated static let windowSize = 8192
    private static let pageSize = 16
    private static let entrySize = 20

    let partialDirectory: URL
    let exchange: (RecorderBLECommand, Data) async throws -> Data

    func synchronizeClock() async throws {
        let seconds = UInt32(Date.now.timeIntervalSince1970)
        try await emptyReply(.clock, payload: Data(littleEndian: seconds))
    }

    func pendingRecordings() async throws -> [Entry] {
        var entries: [Entry] = []
        var seen: Set<UUID> = []
        var firstPage = true
        while true {
            let page = try await exchange(.list, Data([firstPage ? 1 : 0]))
            guard page.count <= Self.entrySize * Self.pageSize,
                  page.count.isMultiple(of: Self.entrySize) else { throw RecorderSyncError.invalidResponse }
            for offset in stride(from: 0, to: page.count, by: Self.entrySize) {
                let id = page.withUnsafeBytes { bytes in
                    NSUUID(uuidBytes: bytes.baseAddress!.assumingMemoryBound(to: UInt8.self) + offset) as UUID
                }
                let time = TimeInterval(page.littleEndianUInt32(at: offset + 16))
                guard (1_704_067_200..<4_102_444_800).contains(time),
                      seen.insert(id).inserted else { throw RecorderSyncError.invalidRecording }
                entries.append(Entry(id: id, recordedAt: Date(timeIntervalSince1970: time)))
            }
            if page.count < Self.entrySize * Self.pageSize { return entries.sorted { $0.recordedAt < $1.recordedAt } }
            firstPage = false
        }
    }

    func audio(for id: UUID) async throws -> Data {
        let sizeReply = try await exchange(.open, id.recorderBytes)
        guard sizeReply.count == 4 else { throw RecorderSyncError.invalidResponse }
        let total = Int(sizeReply.littleEndianUInt32(at: 0))
        guard (45...Self.maximumAudioBytes).contains(total) else { throw RecorderSyncError.invalidRecording }

        let manager = FileManager.default
        try manager.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
        let file = partialURL(for: id)
        if !manager.fileExists(atPath: file.path) {
            try Data().write(to: file, options: .atomic)
        }
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        var offset = try handle.seekToEnd()
        if offset > total {
            offset = 0
            try handle.truncate(atOffset: offset)
            try handle.seek(toOffset: offset)
        } else if offset < total && !offset.isMultiple(of: UInt64(Self.windowSize)) {
            offset -= offset % UInt64(Self.windowSize)
            try handle.truncate(atOffset: offset)
            try handle.seek(toOffset: offset)
        }

        while offset < total {
            let window = try await exchange(.read, Data(littleEndian: UInt32(offset)))
            try Task.checkCancellation()
            guard window.count == min(Self.windowSize, total - Int(offset)) else {
                throw RecorderSyncError.incompleteTransfer
            }
            try handle.write(contentsOf: window)
            offset += UInt64(window.count)
        }
        let data = try Data(contentsOf: file)
        guard data.count == total, data.prefix(4).elementsEqual("RIFF".utf8),
              data[8..<12].elementsEqual("WAVE".utf8) else {
            try? manager.removeItem(at: file)
            throw RecorderSyncError.invalidRecording
        }
        return data
    }

    func acknowledge(_ id: UUID) async throws {
        try await emptyReply(.acknowledge, payload: id.recorderBytes)
        let file = partialURL(for: id)
        if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
    }

    private func partialURL(for id: UUID) -> URL {
        partialDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("part")
    }

    private func emptyReply(_ command: RecorderBLECommand, payload: Data) async throws {
        guard try await exchange(command, payload).isEmpty else { throw RecorderSyncError.invalidResponse }
    }
}

struct RecorderBLEReply {
    let tag: UInt8
    private var bytes = Data()

    mutating func consume(_ frame: Data) throws -> Data? {
        guard frame.count >= 4, frame[0] == tag else { throw RecorderSyncError.invalidResponse }
        let status = frame[1] & 0x7f
        let offset = Int(frame[2]) | Int(frame[3]) << 8
        let last = frame[1] & 0x80 != 0
        switch status {
        case 0: break
        case 2: throw RecorderSyncError.recorderBusy
        case 3: throw RecorderSyncError.invalidRecording
        default: throw RecorderSyncError.invalidResponse
        }
        guard offset == bytes.count, bytes.count + frame.count - 4 <= RecorderSyncClient.windowSize,
              last || frame.count > 4 else { throw RecorderSyncError.incompleteTransfer }
        bytes.append(frame.dropFirst(4))
        return last ? bytes : nil
    }

    init(tag: UInt8) { self.tag = tag }
}

private extension UUID {
    var recorderBytes: Data { withUnsafeBytes(of: uuid) { Data($0) } }
}

private extension Data {
    init(littleEndian value: UInt32) {
        var littleEndian = value.littleEndian
        self = Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }

    func littleEndianUInt32(at index: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: index, as: UInt32.self)) }
    }
}

enum RecorderSyncError: LocalizedError {
    case busy, recorderBusy, invalidResponse, invalidRecording, incompleteTransfer, disconnected, timedOut

    var errorDescription: String? {
        switch self {
        case .busy: return "Синхронизация уже идёт."
        case .recorderBusy: return "Диктофон сейчас записывает."
        case .invalidResponse: return "Диктофон вернул неожиданный ответ."
        case .invalidRecording: return "Не удалось прочитать аудиозапись с диктофона."
        case .incompleteTransfer: return "Передача прервалась. Она продолжится при следующем подключении."
        case .disconnected: return "Связь с диктофоном прервана."
        case .timedOut: return "Диктофон не ответил вовремя."
        }
    }
}
