import Foundation

@main
struct TranslationBackoffSmoke {
    static func main() {
        var policy = GameTranslationBackoff()
        precondition(policy.remainingMilliseconds(at: 100) == 0)
        for (index, ms) in [1000, 2000, 4000, 8000, 16000, 30000, 30000].enumerated() {
            let now = Double(index) * 100.0
            precondition(policy.failed(at: now) == ms)
            precondition(policy.remainingMilliseconds(at: now) == ms)
            precondition(policy.remainingMilliseconds(at: now + Double(ms) / 1000) == 0)
        }
        policy.reset()
        precondition(policy.remainingMilliseconds(at: 0) == 0)
        precondition(policy.failed(at: 2000) == 1000)
        print("PASS: translation retry backoff, cap, and reset")
    }
}
