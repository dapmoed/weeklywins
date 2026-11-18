import Foundation

extension LegacySpeechTranscription {
    struct Transcript: Sendable {
        let text: String
        let words: [Word]

        func validate() throws {
            let length = (text as NSString).length
            var previousEnd = 0
            for word in words {
                guard word.range.location >= previousEnd, word.range.location <= length,
                      word.range.length >= 0, word.range.length <= length - word.range.location,
                      word.timestamp.isFinite, word.duration.isFinite, word.duration >= 0 else {
                    throw TranscriptionError.invalidRecognitionResult
                }
                previousEnd = NSMaxRange(word.range)
            }
        }

        func excerpt(from first: Int, to end: Int) throws -> String {
            try validate()
            guard first >= 0, end >= first, end <= words.count else {
                throw TranscriptionError.invalidRecognitionResult
            }
            guard first < end else { return "" }
            let start = first == 0 ? 0 : words[first].range.location
            let finish = end < words.count ? words[end].range.location : (text as NSString).length
            return (text as NSString).substring(with: NSRange(location: start, length: finish - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func normalizedWords() -> [String] {
            words.map { word in
                (text as NSString).substring(with: word.range).lowercased()
                    .replacingOccurrences(of: "ё", with: "е")
                    .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            }
        }
    }
}

struct LegacyTranscriptMerger {
    private struct Pending {
        let transcript: LegacySpeechTranscription.Transcript
        let window: LegacySpeechTranscription.Window
        let start: Int

        func midpoint(at index: Int) -> Double {
            let word = transcript.words[index]
            return Double(window.inputFrames.lowerBound) + (word.timestamp + word.duration / 2) * window.sampleRate
        }
    }

    private struct Anchor {
        let oldEnd: Int
        let newStart: Int
        let score: Double
    }

    private var pending: Pending?
    private var pieces: [String] = []

    mutating func append(_ transcript: LegacySpeechTranscription.Transcript, window: LegacySpeechTranscription.Window) throws {
        try transcript.validate()
        guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !transcript.words.isEmpty else { throw TranscriptionError.invalidRecognitionResult }
        let next = Pending(transcript: transcript, window: window, start: 0)
        guard let previous = pending else { pending = next; return }
        if previous.window.inputFrames.upperBound <= window.inputFrames.lowerBound {
            try commit(previous, end: previous.transcript.words.count)
            pending = next
            return
        }
        guard let firstNewWord = transcript.words.indices.first(where: {
            next.midpoint(at: $0) >= Double(window.coreFrames.lowerBound)
        }) else { return }
        let anchor = findAnchor(previous: previous, next: next, width: 2)
            ?? findAnchor(previous: previous, next: next, width: 1)
        let oldEnd: Int
        let newStart: Int
        if let anchor {
            oldEnd = anchor.oldEnd
            newStart = anchor.newStart
        } else {
            newStart = firstNewWord
            let word = transcript.words[newStart]
            let cut = Double(window.inputFrames.lowerBound) + word.timestamp * window.sampleRate
            oldEnd = (previous.start..<previous.transcript.words.count).first { previous.midpoint(at: $0) >= cut }
                ?? previous.transcript.words.count
        }
        try commit(previous, end: oldEnd)
        pending = Pending(transcript: transcript, window: window, start: newStart)
    }

    mutating func finish() throws -> String {
        if let pending { try commit(pending, end: pending.transcript.words.count) }
        pending = nil
        return pieces.joined(separator: " ")
    }

    private mutating func commit(_ pending: Pending, end: Int) throws {
        let text = try pending.transcript.excerpt(from: pending.start, to: end)
        if !text.isEmpty { pieces.append(text) }
    }

    private func findAnchor(previous: Pending, next: Pending, width: Int) -> Anchor? {
        let oldWords = previous.transcript.normalizedWords()
        let newWords = next.transcript.normalizedWords()
        guard oldWords.count - previous.start >= width, newWords.count >= width else { return nil }
        let overlapStart = Double(max(previous.window.inputFrames.lowerBound, next.window.inputFrames.lowerBound))
        let overlapEnd = Double(min(previous.window.inputFrames.upperBound, next.window.inputFrames.upperBound))
        let tolerance = next.window.sampleRate
        var candidates: [Anchor] = []
        for old in previous.start...(oldWords.count - width) {
            for new in 0...(newWords.count - width) {
                let matches = (0..<width).allSatisfy { offset in
                    let oldTime = previous.midpoint(at: old + offset)
                    let newTime = next.midpoint(at: new + offset)
                    return !oldWords[old + offset].isEmpty && oldWords[old + offset] == newWords[new + offset]
                        && oldTime >= overlapStart && oldTime < overlapEnd
                        && newTime >= overlapStart && newTime < overlapEnd && abs(oldTime - newTime) <= tolerance
                }
                if matches {
                    let oldTime = previous.midpoint(at: old + width - 1)
                    let newTime = next.midpoint(at: new + width - 1)
                    let score = abs((oldTime + newTime) / 2 - Double(next.window.coreFrames.lowerBound))
                        + abs(oldTime - newTime)
                    candidates.append(Anchor(oldEnd: old + width, newStart: new + width, score: score))
                }
            }
        }
        return candidates.filter { candidate in
            candidates.filter { $0.oldEnd == candidate.oldEnd }.count == 1
                && candidates.filter { $0.newStart == candidate.newStart }.count == 1
        }.min { $0.score < $1.score }
    }
}
