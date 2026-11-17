import Foundation

enum EventExtractor {
    static func extract(_ transcript: String, recordingID: UUID) -> [DiaryEvent] {
        let separated = transcript.replacingOccurrences(
            of: #"(?i),?\s+(?:потом|затем|после этого)\s+|\s+и\s+(?=(?:купил|помыл|позвонил|отправил|подготовил|сделал|сходил|убрал|починил|приготовил|проверил|обсудил)\b)"#,
            with: ";",
            options: .regularExpression
        )
        let fragments = separated.replacingOccurrences(
            of: #"(?<!\d)\.|\.(?!\d)|[!?;\n]+"#,
            with: ";",
            options: .regularExpression
        ).components(separatedBy: ";")
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

    private static let numberValues: [String: Double] = [
        "один": 1, "одна": 1, "одну": 1, "два": 2, "две": 2,
        "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7,
        "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11,
        "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14,
        "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17,
        "восемнадцать": 18, "девятнадцать": 19, "двадцать": 20,
        "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
        "семьдесят": 70, "восемьдесят": 80, "девяносто": 90,
        "сто": 100, "двести": 200, "триста": 300, "четыреста": 400,
        "пятьсот": 500, "шестьсот": 600, "семьсот": 700,
        "восемьсот": 800, "девятьсот": 900, "полтора": 1.5, "полторы": 1.5
    ]

    private static func explicitDuration(in text: String) -> TimeInterval? {
        let ones = "один|одна|одну|два|две|три|четыре|пять|шесть|семь|восемь|девять"
        let teens = "десять|одиннадцать|двенадцать|тринадцать|четырнадцать|пятнадцать|шестнадцать|семнадцать|восемнадцать|девятнадцать"
        let tens = "двадцать|тридцать|сорок|пятьдесят|шестьдесят|семьдесят|восемьдесят|девяносто"
        let hundreds = "сто|двести|триста|четыреста|пятьсот|шестьсот|семьсот|восемьсот|девятьсот"
        let belowHundred = "(?:(?:\(tens))(?:\\s+(?:\(ones)))?|\(teens)|\(ones))"
        let words = "(?:(?:\(hundreds))(?:\\s+\(belowHundred))?|\(belowHundred)|полтора|полторы)"
        let amount = "(?:\\d+(?:[.,]\\d+)?|\(words))"
        let minuteUnits = "(?:минуты|минуту|минута|минут)"
        let hours = "(?:(?<hours>\(amount))\\s*(?:часа|часов|час)|(?<hourWord>час|полчаса))"
        let minutes = "(?<minutes>\(amount))\\s*\(minuteUnits)"
        let compound = "\(hours)(?:[\\s,]*(?:и\\s+)?\(minutes))?"
        let minutesOnly = "(?<minutesOnly>\(amount))\\s*\(minuteUnits)"
        let pattern = "(?i)\\b(?:\(compound)|\(minutesOnly))\\b"
        let largerNumbers = "тысяч(?:а|и|у)?|миллион(?:а|ов)?|миллиард(?:а|ов)?"
        let quantity = "(?:\(amount)|\(largerNumbers)|часа|часов|час|полчаса|\(minuteUnits))"
        let partialQuantityPrefix = "(?i)\\b\(quantity)(?:\\s*[-–—]\\s*|\\s+(?:или\\s+)?)$"
        let rangeSuffix = "(?i)^\\s*(?:[-–—]|или\\b)\\s*\(quantity)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let prefix = source.substring(to: match.range.location)
            if prefix.range(of: #"(?i)\b(?:в|во|к|около|примерно|приблизительно|почти|через|до|после|с|со)\s+$"#, options: .regularExpression) != nil { continue }
            if prefix.range(of: partialQuantityPrefix, options: .regularExpression) != nil { continue }
            let suffix = source.substring(from: NSMaxRange(match.range))
            if suffix.range(of: #"(?i)^\s+(?:назад|спустя|позже|раньше)\b"#, options: .regularExpression) != nil { continue }
            if suffix.range(of: rangeSuffix, options: .regularExpression) != nil { continue }
            let wordRange = match.range(withName: "hourWord")
            var wordSeconds: TimeInterval = 0
            if wordRange.location != NSNotFound {
                wordSeconds = source.substring(with: wordRange).lowercased() == "полчаса" ? 1800 : 3600
            }
            let seconds = number(named: "hours", in: match, source: source) * 3600
                + number(named: "minutes", in: match, source: source) * 60
                + number(named: "minutesOnly", in: match, source: source) * 60
                + wordSeconds
            guard seconds.isFinite else { continue }
            return seconds
        }
        return nil
    }

    private static func number(named group: String, in match: NSTextCheckingResult, source: NSString) -> Double {
        let range = match.range(withName: group)
        guard range.location != NSNotFound else { return 0 }
        let text = source.substring(with: range).lowercased()
        if let value = Double(text.replacingOccurrences(of: ",", with: ".")) { return value }
        return text.split(whereSeparator: \.isWhitespace).compactMap { numberValues[String($0)] }.reduce(0, +)
    }
}
