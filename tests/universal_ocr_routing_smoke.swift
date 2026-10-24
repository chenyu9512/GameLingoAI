import Foundation

@main
struct OCRRoutingSmoke {
    static func main() {
        let modes = GameOCRRouting.Mode.allCases
        precondition(modes.count == 2)
        precondition(modes.contains(.vision) && modes.contains(.paddleHybrid))
        precondition(!GameOCRRouting.shouldEnhance(
            confidence: 0.1, candidateCount: 4, mode: .vision,
            performanceFast: false, millisecondsSinceLast: 5000))
        precondition(!GameOCRRouting.shouldEnhance(
            confidence: 0.1, candidateCount: 4, mode: .paddleHybrid,
            performanceFast: true, millisecondsSinceLast: 5000))
        precondition(!GameOCRRouting.shouldEnhance(
            confidence: 0.1, candidateCount: 4, mode: .paddleHybrid,
            performanceFast: false, millisecondsSinceLast: 300))
        precondition(!GameOCRRouting.shouldEnhance(
            confidence: 0.85, candidateCount: 4, mode: .paddleHybrid,
            performanceFast: false, millisecondsSinceLast: 5000))
        precondition(GameOCRRouting.shouldEnhance(
            confidence: 0.41, candidateCount: 4, mode: .paddleHybrid,
            performanceFast: false, millisecondsSinceLast: 5000))
        precondition(GameOCRRouting.commonOCRLanguages.contains { $0.1 == "ar" })
        precondition(GameOCRRouting.commonOCRLanguages.contains { $0.1 == "zh-Hant" })
        print("PASS: Universal OCR routing and multilingual selections")
    }
}
