import Foundation

// Runs on the Codemagic Mac host. No iPhone SDK, screenshots or network needed.
@main
struct OCRQualitySmoke {
    static func main() {
        let cases: [(String, Float, String, Bool)] = [
            ("ホイミ", 0.82, "ja", true),
            ("攻撃力 +25", 0.67, "ja", true),
            ("HP 120 / MP 30", 0.65, "ja", true),
            ("獲得したアイテムを確認する。", 0.80, "ja", true),
            ("Potion +20", 0.79, "en", true),
            ("", 0.9, "ja", false),
            ("???!!!", 0.9, "ja", false),
            ("異常\u{FFFD}文字", 0.9, "ja", false),
            ("ホイミ", 0.1, "ja", false)
        ]
        for (source, confidence, language, expected) in cases {
            let ok = GameOCRQuality.evaluate(
                source, confidence: confidence, language: language) != nil
            precondition(ok == expected, "OCR QA mismatch for: \(source)")
        }
        let selected = GameOCRQuality.best(
            from: [("???!!!", 0.9), ("ホイミ", 0.8)],
            language: "ja")
        precondition(selected?.text == "ホイミ",
                     "Candidate scoring did not reject corrupted text")
        precondition(GameOCRQuality.requiredStableFrames(confidence: 0.92, fastMode: true) == 1)
        precondition(GameOCRQuality.requiredStableFrames(confidence: 0.65, fastMode: true) == 2)
        precondition(GameOCRQuality.requiredStableFrames(confidence: 0.40, fastMode: true) == 3)
        precondition(GameOCRQuality.requiredStableFrames(confidence: 0.80, fastMode: false) == 1)
        print("PASS: OCR quality checks (\(cases.count) samples + candidate selection)")
    }
}
