import Foundation

/// Maintains the most reliable source language for one game without storing
/// recognized text. A Latin/Han switch needs distinct observations, while
/// kana/Hangul give strong direct evidence.
struct GameSourceLanguageTracker {
    private(set) var current: String?
    private var proposed: String?
    private var proposedDistinctTexts = 0
    private var lastProposalText = ""

    mutating func reset() {
        current = nil
        proposed = nil
        proposedDistinctTexts = 0
        lastProposalText = ""
    }

    mutating func resolve(configured: String, detected: String?, text: String) -> String? {
        guard configured.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto" else {
            reset()
            current = configured
            return configured
        }
        guard let detected, !detected.isEmpty, detected != "und" else { return current }
        if current == nil || current == detected {
            current = detected
            proposed = nil
            proposedDistinctTexts = 0
            lastProposalText = ""
            return current
        }
        let strongJapanese = detected == "ja" && text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value)
        }
        let strongKorean = detected == "ko" && text.unicodeScalars.contains {
            (0xAC00...0xD7AF).contains($0.value)
        }
        if strongJapanese || strongKorean {
            current = detected
            proposed = nil
            proposedDistinctTexts = 0
            lastProposalText = ""
            return current
        }
        let observation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if proposed != detected {
            proposed = detected
            proposedDistinctTexts = 0
            lastProposalText = ""
        }
        if observation != lastProposalText && !observation.isEmpty {
            proposedDistinctTexts += 1
            lastProposalText = observation
        }
        if proposedDistinctTexts >= 2 {
            current = detected
            proposed = nil
            proposedDistinctTexts = 0
            lastProposalText = ""
        }
        return current
    }
}

enum GameTranslationIssue: Int {
    case languagePackMissing = 1
    case unsupportedPair = 2
    case emptyResult = 3
    case executionFailed = 4
}

/// Per-source cooldown suppresses repeated failed attempts, without affecting
/// other source languages or the last visible subtitle.
struct GameTranslationRetryPolicy {
    private struct Entry {
        var failures: Int
        var retryAt: TimeInterval
    }
    private var entries: [String: Entry] = [:]

    func canAttempt(_ language: String, at now: TimeInterval) -> Bool {
        now >= (entries[language]?.retryAt ?? 0)
    }

    @discardableResult
    mutating func recordFailure(_ issue: GameTranslationIssue,
                                language: String, at now: TimeInterval) -> Int {
        let failures = min((entries[language]?.failures ?? 0) + 1, 8)
        let delay: Int
        switch issue {
        case .languagePackMissing: delay = 20
        case .unsupportedPair: delay = 90
        case .emptyResult: delay = min(30, 2 << min(failures - 1, 4))
        case .executionFailed: delay = min(60, 3 << min(failures - 1, 4))
        }
        entries[language] = Entry(failures: failures, retryAt: now + Double(delay))
        return delay
    }

    mutating func recordSuccess(_ language: String) {
        entries.removeValue(forKey: language)
    }

    mutating func reset() {
        entries.removeAll()
    }
}
