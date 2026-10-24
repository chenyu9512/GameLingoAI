import Foundation

@main
struct OCRSessionPolicySmoke {
    static func main() {
        let policy = GameOCRRecoveryPolicy.self
        precondition(policy.shouldRecover(text: "勇者", confidence: 0.40,
                                         priorText: "", priorSamples: 0,
                                         fingerprint: 1, lastFingerprint: 0,
                                         now: 100, lastAt: 0, fastMode: false))
        // Animated frames have different hashes but should not launch Accurate
        // every time they arrive on the 0.48-second balanced capture path.
        precondition(!policy.shouldRecover(text: "勇者", confidence: 0.42,
                                          priorText: "攻撃", priorSamples: 1,
                                          fingerprint: 2, lastFingerprint: 1,
                                          now: 100.5, lastAt: 100, fastMode: false))
        precondition(!policy.shouldRecover(text: "勇者", confidence: 0.5,
                                          priorText: "勇者", priorSamples: 1,
                                          fingerprint: 2, lastFingerprint: 1,
                                          now: 102, lastAt: 100, fastMode: false))
        precondition(!policy.shouldRecover(text: "勇者", confidence: 0.41,
                                          priorText: "", priorSamples: 0,
                                          fingerprint: 1, lastFingerprint: 1,
                                          now: 102, lastAt: 100, fastMode: false))
        precondition(policy.shouldRecover(text: "勇者", confidence: 0.41,
                                         priorText: "", priorSamples: 0,
                                         fingerprint: 2, lastFingerprint: 1,
                                         now: 101.5, lastAt: 100, fastMode: false))
        precondition(policy.shouldRecover(text: "", confidence: 0,
                                         priorText: "", priorSamples: 0,
                                         fingerprint: 1, lastFingerprint: 1,
                                         now: 103, lastAt: 100, fastMode: false))

        var context = GameAutoSourceContext()
        precondition(context.resolve(text: "魔王", detected: nil, at: 100).language == nil)
        precondition(context.resolve(text: "こんにちは", detected: "ja", at: 101).language == "ja")
        let inferred = context.resolve(text: "魔王復活", detected: nil, at: 102)
        precondition(inferred.language == "ja" && inferred.inferred)
        precondition(context.resolve(text: "HP 100", detected: nil, at: 103).language == nil)
        precondition(context.resolve(text: "勇者", detected: nil, at: 250).language == nil)
        precondition(context.resolve(text: "안녕하세요", detected: "ko", at: 251).language == "ko")
        precondition(context.resolve(text: "勇者", detected: nil, at: 252).language == nil)
        context.reset()
        precondition(context.resolve(text: "勇者", detected: nil, at: 253).language == nil)
        print("PASS: bounded Accurate recovery and safe Han-only language context")
    }
}
