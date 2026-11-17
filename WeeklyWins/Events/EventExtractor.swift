import Foundation

enum EventExtractor {
    static func extract(_ transcript: String, recordingID: UUID) -> [DiaryEvent] {
        let separated = transcript.replacingOccurrences(
            of: #"(?i),?\s+(?:потом|затем|после этого)\s+|\s+и\s+(?=(?:купил|помыл|позвонил|отправил|подготовил|сделал|сходил|убрал|починил|приготовил|проверил|обсудил)\b)"#,
            with: ";",
            options: .regularExpression
        )
        let fragments = separated.components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
        return fragments.compactMap { fragment in
            let text = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let negative = text.range(
                of: #"(?i)\b(не\s+\p{L}+|планирую|собираюсь|нужно|надо)\b"#,
                options: .regularExpression
            ) != nil
            return DiaryEvent(
                recordingID: recordingID,
                sourceText: text,
                text: text,
                completion: negative ? .notCompleted : .completed,
                duration: explicitDuration(in: text)
            )
        }
    }

    private static func explicitDuration(in text: String) -> TimeInterval? {
        let pattern = #"(?i)\b(\d+|один|одну|два|две|три|четыре|пять|полчаса|час)\s*(часа|часов|час|минуты|минута|минут)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = text as NSString
        let numbers: [String: Double] = ["один": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let prefix = source.substring(to: match.range.location)
            if prefix.range(of: #"(?i)\b(?:в|во|к|около|через|до|после|с)\s+$"#, options: .regularExpression) != nil { continue }
            let number = source.substring(with: match.range(at: 1)).lowercased()
            if number == "полчаса" { return 1800 }
            if number == "час" { return 3600 }
            guard match.range(at: 2).location != NSNotFound,
                  let value = Double(number) ?? numbers[number] else { continue }
            let unit = source.substring(with: match.range(at: 2)).lowercased()
            return value * (unit.hasPrefix("час") ? 3600 : 60)
        }
        return nil
    }
}
