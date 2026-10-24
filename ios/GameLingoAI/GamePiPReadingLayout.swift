import Foundation

/// Text-only pagination shared by PiP layouts. A page always carries both
/// source and translated text; never paginate the two streams independently.
enum GamePiPReadingLayout {
    struct Pair: Equatable {
        let original: String
        let translated: String
    }

    static func paginate(original: String, translated: String,
                         originalLimit: Int = 100, translatedLimit: Int = 86) -> [Pair] {
        let originals = original.components(separatedBy: "\n")
        let translations = translated.components(separatedBy: "\n")
        // A batch TranslationSession maps input lines 1:1. Keep that mapping.
        if originals.count > 1 && originals.count == translations.count {
            return zip(originals, translations).flatMap {
                splitPair(original: $0.0, translated: $0.1,
                          originalLimit: originalLimit, translatedLimit: translatedLimit)
            }
        }
        return splitPair(original: original, translated: translated,
                         originalLimit: originalLimit, translatedLimit: translatedLimit)
    }

    private static func splitPair(original: String, translated: String,
                                  originalLimit: Int, translatedLimit: Int) -> [Pair] {
        let lhs = Array(original)
        let rhs = Array(translated)
        let lhsLimit = max(20, originalLimit)
        let rhsLimit = max(20, translatedLimit)
        let count = max(1, max((lhs.count + lhsLimit - 1) / lhsLimit,
                               (rhs.count + rhsLimit - 1) / rhsLimit))
        if count == 1 { return [Pair(original: original, translated: translated)] }
        // Approximate proportional fragments of the same translation pair.
        // Both strings keep every Unicode Character, including punctuation.
        func fragment(_ chars: [Character], at index: Int) -> String {
            let lower = index * chars.count / count
            let upper = (index + 1) * chars.count / count
            return String(chars[lower..<upper])
        }
        return (0..<count).map {
            Pair(original: fragment(lhs, at: $0), translated: fragment(rhs, at: $0))
        }
    }

    static func group(_ pairs: [Pair], maxPairs: Int, maxCharacters: Int) -> [[Pair]] {
        guard !pairs.isEmpty else { return [] }
        let pairLimit = max(1, maxPairs)
        let charLimit = max(40, maxCharacters)
        var groups: [[Pair]] = []
        var current: [Pair] = []
        var length = 0
        for pair in pairs {
            let added = max(pair.original.count, pair.translated.count)
            if !current.isEmpty && (current.count >= pairLimit || length + added > charLimit) {
                groups.append(current)
                current = []
                length = 0
            }
            current.append(pair)
            length += added
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
