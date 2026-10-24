import Foundation
import Vision
import NaturalLanguage

@main
struct AutoLanguageSmoke {
    static func main() {
        precondition(GameLanguageSupport.isAutomatic("auto"))
        precondition(GameLanguageSupport.resolvedSource(
            in: "勇者は城へ向かった。", configured: "auto") == "ja")
        precondition(GameLanguageSupport.resolvedSource(
            in: "용사가 마을로 돌아왔습니다.", configured: "auto") == "ko")
        precondition(GameLanguageSupport.resolvedSource(
            in: "1234 / 90%", configured: "auto") == nil)
        precondition(GameLanguageSupport.resolvedSource(
            in: "Potion", configured: "fr") == "fr")
        precondition(GameLanguageSupport.resolvedSource(
            in: "The hero walks into a forest and opens the ancient wooden door.",
            configured: "auto") == "en")

        // An auto OCR request should not receive the literal language "auto".
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try! GameLanguageSupport.setup(request, language: "auto")
        precondition(request.automaticallyDetectsLanguage)
        precondition(!request.recognitionLanguages.contains("auto"))
        print("PASS: auto language OCR and conservative source resolution")
    }
}
