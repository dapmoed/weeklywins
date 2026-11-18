import Foundation

@MainActor
final class LegacySpeechResultAccumulator {
    private var current: LegacySpeechTranscription.Transcript?
    var hasTimedSpeech: Bool { current != nil }

    func update(
        _ snapshot: LegacySpeechTranscription.Transcript,
        isFinal: Bool
    ) throws -> LegacySpeechTranscription.Transcript? {
        let hasTiming = snapshot.words.contains { $0.timestamp > 0 || $0.duration > 0 }
        guard hasTiming else {
            guard isFinal else { return nil }
            try snapshot.validate()
            if let current, snapshot.text.isEmpty || snapshot.text == current.text { return current }
            guard current == nil else { throw TranscriptionError.invalidRecognitionResult }
            return snapshot
        }
        try snapshot.validate()
        if let previous = current, let first = snapshot.words.first {
            let oldWords = previous.words
            let previousEnd = oldWords.last.map { $0.timestamp + $0.duration } ?? 0
            let prefixEnd: Int
            if first.timestamp >= previousEnd {
                prefixEnd = oldWords.count
            } else {
                let newWord = snapshot.normalizedWords()[0]
                let normalized = previous.normalizedWords()
                let matches = oldWords.indices.filter { index in
                    let old = oldWords[index]
                    return normalized[index] == newWord
                        && old.timestamp < first.timestamp + first.duration
                        && old.timestamp + old.duration > first.timestamp
                }
                if matches.count == 1, let match = matches.first {
                    prefixEnd = match
                } else {
                    prefixEnd = oldWords.firstIndex { $0.timestamp + $0.duration > first.timestamp } ?? oldWords.count
                }
            }
            let prefix: String
            if prefixEnd == 0 {
                prefix = ""
            } else if prefixEnd == oldWords.count {
                prefix = previous.text
            } else {
                prefix = (previous.text as NSString).substring(to: oldWords[prefixEnd].range.location)
            }
            let separator = prefix.isEmpty || prefix.last?.isWhitespace == true ? "" : " "
            let offset = (prefix as NSString).length + (separator as NSString).length
            let appended = snapshot.words.map { word in
                LegacySpeechTranscription.Word(
                    range: NSRange(location: word.range.location + offset, length: word.range.length),
                    timestamp: word.timestamp, duration: word.duration
                )
            }
            current = .init(text: prefix + separator + snapshot.text,
                            words: Array(oldWords.prefix(prefixEnd)) + appended)
        } else {
            current = snapshot
        }
        try current?.validate()
        return isFinal ? current : nil
    }
}
