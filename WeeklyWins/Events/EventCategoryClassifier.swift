import Foundation

struct EventCategoryClassifier {
    private struct Example {
        let category: EventCategory
        let features: Set<String>
        let weight: Int
    }

    private let examples: [Example]

    init(recordings: [Recording]) {
        var seen: [EventCategory: Set<Set<String>>] = [:]
        var examples: [Example] = []
        // The store is sorted newest first. Cap the on-device comparison cost for long journals.
        for recording in recordings where recording.deletedAt == nil {
            for event in recording.events ?? [] {
                // Before automatic categorization, every named category came from a user edit.
                let confirmed = recording.eventCategorySources?[event.id].map { $0 == .manual }
                    ?? (recording.eventsManuallyEdited == true && event.category != .unclassified)
                guard confirmed else { continue }
                let features = Self.features(in: event.text)
                guard !features.isEmpty, seen[event.category, default: []].insert(features).inserted else { continue }
                examples.append(Example(category: event.category, features: features, weight: Self.weight(of: features)))
            }
            if examples.count >= 500 { break }
        }
        self.examples = Array(examples.prefix(500))
    }

    func category(for text: String) -> EventCategory {
        let features = Self.features(in: text)
        guard !features.isEmpty else { return .unclassified }

        let queryWeight = Self.weight(of: features)
        var scores: [EventCategory: [Double]] = [:]
        var strongestByCategory: [EventCategory: Double] = [:]
        var distinctiveMatches: [EventCategory: Double] = [:]
        for example in examples {
            let shared = features.intersection(example.features)
            let commonWords = shared.count(where: { !$0.contains(" ") })
            let commonPhrases = shared.count - commonWords
            guard commonWords >= 2 else { continue }
            // Ordered pairs provide stronger evidence than isolated words.
            let overlap = Double(commonWords + 2 * commonPhrases)
            let coverage = overlap / Double(max(queryWeight, example.weight))
            if coverage >= 0.30 { scores[example.category, default: []].append(coverage) }

            // A short, distinctive phrase can be buried within a much longer voice note.
            // Normalize against both lengths so surrounding details do not hide that overlap.
            let similarity = overlap / sqrt(Double(queryWeight) * Double(example.weight))
            strongestByCategory[example.category] = max(strongestByCategory[example.category, default: 0], similarity)
            if commonWords >= 4, commonPhrases >= 1, similarity >= 0.36 {
                distinctiveMatches[example.category] = max(distinctiveMatches[example.category, default: 0], similarity)
            }
        }

        let ranked = scores.compactMap { category, matches -> (category: EventCategory, score: Double)? in
            guard matches.count >= 2 else { return nil }
            let best = matches.sorted(by: >).prefix(2)
            return (category, best.reduce(0, +) / 2)
        }.sorted { $0.score > $1.score }
        if let best = ranked.first, best.score >= 0.38 {
            let runnerUp = ranked.dropFirst().first?.score ?? 0
            return best.score - runnerUp >= 0.12 ? best.category : .unclassified
        }

        guard let best = distinctiveMatches.max(by: { $0.value < $1.value }) else { return .unclassified }
        let rival = strongestByCategory.filter { $0.key != best.key }.values.max() ?? 0
        return best.value - rival >= 0.10 ? best.key : .unclassified
    }

    private static func weight(of features: Set<String>) -> Int {
        features.reduce(0) { $0 + ($1.contains(" ") ? 2 : 1) }
    }

    private static func features(in text: String) -> Set<String> {
        let stopWords: Set<Substring> = ["когда", "сегодня", "вчера", "после", "потом", "нужно", "было",
                                         "который", "также", "очень", "просто", "только", "снова"]
        let words = text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { !$0.isLetter })
            .map { word -> String? in
                guard word.count >= 4, !stopWords.contains(word) else { return nil }
                // Keep the common prefix across frequent Russian inflections.
                return String(word.prefix(5))
            }
        let phrases = zip(words, words.dropFirst()).compactMap { lhs, rhs -> String? in
            guard let lhs, let rhs else { return nil }
            return lhs + " " + rhs
        }
        return Set(words.compactMap { $0 }).union(phrases)
    }
}
