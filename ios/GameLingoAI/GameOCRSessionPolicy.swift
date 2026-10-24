import Foundation

/// A deterministic admission policy for expensive Vision Accurate recovery.
/// It reduces recovery storms when animated backgrounds change pixel hashes,
/// but never shortens the multi-frame stability checks on OCR results.
enum GameOCRRecoveryPolicy {
    static func shouldRecover(text: String, confidence: Double,
                              priorText: String, priorSamples: Int,
                              fingerprint: UInt64,
                              lastFingerprint: UInt64,
                              now: TimeInterval, lastAt: TimeInterval,
                              fastMode: Bool) -> Bool {
        // Once the same nonempty Fast candidate has been observed, let the
        // stability filter finish instead of rerunning Accurate each frame.
        if !text.isEmpty && text == priorText && priorSamples > 0
            && confidence >= 0.48 { return false }
        guard lastAt > 0 else { return true }
        let elapsed = max(0, now - lastAt)
        // A global budget still protects animated scenes whose fingerprint
        // changes on each capture, not only exactly identical frames.
        let globalMinimum: TimeInterval = text.isEmpty ? 0.9 :
            (fastMode ? 1.0 : 1.4)
        if elapsed < globalMinimum { return false }
        // Static scenes get a longer cooldown. Recovery remains possible
        // later for previously unreadable tiny fonts and menus.
        if fingerprint != 0 && fingerprint == lastFingerprint &&
           elapsed < 2.5 { return false }
        return true
    }
}

/// Do not guess the script of an unseen game. A recent, confidently detected
/// Japanese/Chinese source can help interpret *Han-only* short OCR snippets.
/// Kana/Hangul/clear language changes are handled by the primary detector.
struct GameAutoSourceContext {
    private(set) var lastLanguage: String?
    private var lastSeenAt: TimeInterval = 0

    mutating func reset() {
        lastLanguage = nil
        lastSeenAt = 0
    }

    mutating func resolve(text: String, detected: String?,
                          at now: TimeInterval) -> (language: String?, inferred: Bool) {
        if let detected {
            lastLanguage = detected
            lastSeenAt = now
            return (detected, false)
        }
        guard let lastLanguage,
              ["ja", "zh-Hans", "zh-Hant"].contains(lastLanguage),
              lastSeenAt > 0, now >= lastSeenAt,
              now - lastSeenAt <= 120,
              Self.isHanOnly(text) else { return (nil, false) }
        return (lastLanguage, true)
    }

    private static func isHanOnly(_ text: String) -> Bool {
        var hanCount = 0
        for scalar in text.unicodeScalars {
            let n = scalar.value
            if (0x3400...0x9FFF).contains(n) || (0x20000...0x2FA1F).contains(n) {
                hanCount += 1
            } else if CharacterSet.letters.contains(scalar) {
                // Mixed Latin, kana, Hangul, etc. are not safe to infer.
                return false
            }
        }
        return hanCount >= 2
    }
}
