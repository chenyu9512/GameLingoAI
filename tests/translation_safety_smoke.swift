import Foundation

@main
struct TranslationSafetySmoke {
    static func main() {
        var tracker = GameSourceLanguageTracker()
        precondition(tracker.resolve(configured: "auto", detected: "ja", text: "勇者が行く") == "ja")
        precondition(tracker.resolve(configured: "auto", detected: "en", text: "HP 100") == "ja")
        precondition(tracker.resolve(configured: "auto", detected: "en", text: "HP 100") == "ja")
        precondition(tracker.resolve(configured: "auto", detected: "en", text: "Open the ancient door") == "en")
        precondition(tracker.resolve(configured: "auto", detected: "ja", text: "ようこそ！") == "ja")
        precondition(tracker.resolve(configured: "auto", detected: nil, text: "01234") == "ja")
        precondition(tracker.resolve(configured: "ko", detected: "en", text: "hello") == "ko")
        tracker.reset()
        precondition(tracker.resolve(configured: "auto", detected: nil, text: "01234") == nil)
        var policy = GameTranslationRetryPolicy()
        precondition(policy.canAttempt("ja", at: 100))
        precondition(policy.recordFailure(.languagePackMissing, language: "ja", at: 100) == 20)
        precondition(!policy.canAttempt("ja", at: 119.9))
        precondition(policy.canAttempt("ja", at: 120))
        precondition(policy.canAttempt("en", at: 110))
        precondition(policy.recordFailure(.executionFailed, language: "ja", at: 120) == 6)
        policy.recordSuccess("ja")
        precondition(policy.canAttempt("ja", at: 121))
        print("PASS language stability and bounded failure backoff")
    }
}
