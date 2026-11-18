import Foundation

enum EventExtractor {
    private static let durationSubjects = #"встреч|созвон|совещан|обсужден|работ|задач|проверк"#
    private static let durationVerbs = #"длил(?:ся|ась|ось)|занял(?:а|о)?"#
    private static let clockDuration = #"\d{1,3}:[0-5]\d"#
    private static let durationQualifier = #"(?:(?:сегодня|вчера|сам[ао]?)\s+)*"#

    static func extract(_ transcript: String, recordingID: UUID) -> [DiaryEvent] {
        let separated = transcript.replacingOccurrences(
            of: #"(?i),?\s+(?:потом|затем|после этого)\s+|\s+и\s+(?=(?:купил|помыл|позвонил|отправил|подготовил|сделал|сходил|убрал|починил|приготовил|проверил|обсудил)\b)"#,
            with: ";",
            options: .regularExpression
        )
        let durationClause = "\(durationQualifier)(?:\(durationSubjects))\\p{L}*\\s+(?:\(durationVerbs))\\s+\(clockDuration)\\b"
        let followUp = #"(?:(?:я|мы)\s+)?решил(?:а|и)?[,]?\s+(?:что\s+)?(?:нужно|надо)\b"#
        let subsequentTask = #"после\s+(?:встречи|созвона|совещания)\s+(?:починил|проверил|подготовил|отправил|сделал|обсудил)(?:а|и)?\b"#
        let decisions = separated.replacingOccurrences(
            of: "(?i)(?<=\\S)(?<!\\bне)(?<!\\bя)(?<!\\bмы)(?<!\\bчто)[ \\t]+(?:и\\s+)?(\(followUp))",
            with: ";$1", options: .regularExpression
        )
        let clauses = decisions.replacingOccurrences(
            of: "(?im)(^|[;.!?\\n])(\\s*\(followUp)[^;.!?\\n]*?)[ \\t]+(?=\(durationClause))",
            with: "$1$2;", options: .regularExpression
        ).replacingOccurrences(
            of: "(?i)(\\b\(durationClause))[ \\t]+(?=\(subsequentTask))",
            with: "$1;", options: .regularExpression
        )
        let priorAction = #"(?:поменял|сменил|проверил|сходил|купил|заш[её]л|помыл|приготовил|убрал)(?:а|и)?\b"#
        let transition = #"(?:на обед|дома)\s+(?:не\s+)?(?:сходил|купил|помыл|приготовил|убрал)(?:а|и)?\b"#
        let activities = clauses.replacingOccurrences(
            of: "(?i)(\\b\(priorAction)[^;.!?\\n]*?)[ \\t]+(?=\(transition))",
            with: "$1;", options: .regularExpression
        )
        let fragments = activities.replacingOccurrences(
            of: #"(?<!\d)\.|\.(?!\d)|[!?;\n]+"#,
            with: ";",
            options: .regularExpression
        ).components(separatedBy: ";")
        var events: [DiaryEvent] = []
        var conflictingDurations: Set<UUID> = []
        for fragment in fragments {
            let text = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let clarification = durationClarification(in: text) ?? clockDurationClarification(in: text)
            if let clarification,
               let index = events.lastIndex(where: { describesSubject(clarification.subject, in: $0.text) }) {
                if let existing = events[index].duration, existing != clarification.duration {
                    conflictingDurations.insert(events[index].id)
                }
                events[index].duration = conflictingDurations.contains(events[index].id) ? nil : clarification.duration
                events[index].sourceText += ". " + text
                continue
            }
            events.append(DiaryEvent(
                recordingID: recordingID,
                sourceText: text,
                text: text,
                completion: isPending(text) ? .notCompleted : .completed,
                duration: clarification?.duration ?? explicitDuration(in: text)
            ))
        }
        return events
    }

    private static func isPending(_ text: String) -> Bool {
        let leadingNegation = #"^(?:(?:я|мы|сегодня|вчера|дома|утром|вечером)\s+)*не\s+\p{L}+"#
        let negatedVerb = #"\bне\s+(?:\p{L}+(?:л|ла|ли|ло|ет|ит|ют|ат|ят)(?:ся|сь)?|мог|смог|могу|можем)\b"#
        let negatedResult = #"\bне\s+(?:выполнен|отправлен|сделан|закончен|подготовлен|заверш[её]н)[аоы]?\b"#
        let intent = #"\b(?:планирую|собираюсь|нужно|надо)\b"#
        return text.range(of: "(?i)\(leadingNegation)|\(negatedVerb)|\(negatedResult)|\(intent)",
                          options: .regularExpression) != nil
    }

    private static func describesSubject(_ subject: String, in text: String) -> Bool {
        let time = "(?:(?:сегодня|вчера|утром|днем|днём|вечером)\\s+)?"
        let action = "(?:прош(?:[её]л|ла|ло|ли)|пров[её]л|провела|провели|состоял(?:ся|ась|ось|ись)|был(?:а|о|и)?|проводил(?:а|и)?|выполнил(?:а|и)?|сделал(?:а|и)?|завершил(?:а|и)?|планирую|запланировал(?:а|и)?|будет|нужно\\s+(?:провести|назначить|сделать|выполнить))"
        let adjective = "(?:\\p{L}+(?:ая|ую|ое|ый|ой|ые|ого)\\s+)?"
        let introduction = #"(?:(?:запишу|запишем|расскажу|расскажем)\s+[^;.!?\n]{1,100}?\bдел(?:а)?\s+)?"#
        let pattern = "(?i)^\(time)(?:я\\s+)?\(introduction)(?:\(action)\\s+)?\(adjective)\(subject)\\p{L}*\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func durationClarification(in text: String) -> (duration: TimeInterval, subject: String)? {
        let durations: [String: TimeInterval] = [
            "часов": 3600, "получасов": 1800, "полуторачасов": 5400,
            "двухчасов": 7200, "трехчасов": 10800, "трёхчасов": 10800,
            "четырехчасов": 14400, "четырёхчасов": 14400, "пятичасов": 18000
        ]
        let adjectives = durations.keys.sorted().joined(separator: "|")
        let pattern = "(?i)^(\(adjectives))(?:ая|ой|ое|ую)\\s+(\(durationSubjects))\\p{L}*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
              let duration = durations[source.substring(with: match.range(at: 1)).lowercased()] else { return nil }
        return (duration, source.substring(with: match.range(at: 2)).lowercased())
    }

    private static func clockDurationClarification(in text: String) -> (duration: TimeInterval, subject: String)? {
        let pattern = "(?i)^\(durationQualifier)(\(durationSubjects))\\p{L}*\\s+(?:\(durationVerbs))\\s+(\(clockDuration))$"
        let source = text as NSString
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(
            in: text, range: NSRange(location: 0, length: source.length)
        ) else { return nil }
        let parts = source.substring(with: match.range(at: 2)).split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0] * 3600 + parts[1] * 60, source.substring(with: match.range(at: 1)).lowercased())
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
