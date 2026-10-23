import Foundation

/// Conservative OCR cleanup: reject damaged/low-signal candidates without
/// inventing Japanese words or replacing valid RPG symbols, numbers, HP/MP.
enum GameOCRQuality {
    struct Candidate {
        let text: String
        let confidence: Float
        let score: Double
    }

    static func evaluate(_ source: String, confidence: Float, language: String) -> Candidate? {
        let text = source.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, confidence >= 0.30,
              text.count <= 2000, !text.contains("\u{FFFD}") else { return nil }

        var meaningful = 0
        var controls = 0
        var unusual = 0
        var Japanese = 0
        var punctuation = 0
        for scalar in text.unicodeScalars {
            let n = scalar.value
            if CharacterSet.controlCharacters.contains(scalar) {
                controls += 1
                continue
            }
            if CharacterSet.letters.contains(scalar) ||
                CharacterSet.decimalDigits.contains(scalar) {
                meaningful += 1
            }
            if (0x3040...0x30ff).contains(n) || (0x3400...0x9fff).contains(n) {
                Japanese += 1
            }
            if CharacterSet.punctuationCharacters.contains(scalar) ||
                CharacterSet.symbols.contains(scalar) {
                punctuation += 1
            }
            if !CharacterSet.letters.contains(scalar) &&
                !CharacterSet.decimalDigits.contains(scalar) &&
                !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
                !CharacterSet.punctuationCharacters.contains(scalar) &&
                !CharacterSet.symbols.contains(scalar) {
                unusual += 1
            }
        }
        guard controls == 0, unusual <= 1, meaningful > 0,
              !(text.count >= 4 && punctuation > meaningful * 3) else { return nil }
        let base = Double(confidence)
        let scriptBonus = language.hasPrefix("ja") && Japanese > 0 ? 0.10 : 0
        return Candidate(text: text, confidence: confidence,
                         score: base + scriptBonus - (Double(unusual) * 0.20))
    }

    static func best(from raw: [(String, Float)], language: String) -> Candidate? {
        raw.compactMap { evaluate($0.0, confidence: $0.1, language: language) }
            .max { $0.score < $1.score }
    }

    /// Fast mode is a latency preference, not permission to display a
    /// low-confidence single-frame hallucination. High-confidence dialogue
    /// still appears immediately, while noisy frames must stabilize.
    static func requiredStableFrames(confidence: Double, fastMode: Bool) -> Int {
        if confidence < 0.48 { return 3 }
        if fastMode { return confidence >= 0.86 ? 1 : 2 }
        return confidence >= 0.78 ? 1 : 2
    }

    static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if abs(a.count - b.count) > max(a.count, b.count) / 6 { return false }
        let count = min(a.count, b.count)
        let differences = (0..<count).reduce(0) { $0 + (a[$1] == b[$1] ? 0 : 1) }
        return differences <= max(1, count / 12)
    }
}
