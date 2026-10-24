import Foundation

@main
struct TranslationLanguagesSmoke {
    static func main() {
        precondition(GameTranslationLanguages.preferredTarget(["ja-JP"]) == "ja")
        precondition(GameTranslationLanguages.preferredTarget(["zh-TW"]) == "zh-Hant")
        precondition(GameTranslationLanguages.preferredTarget(["de-DE"]) == "de")
        precondition(GameTranslationLanguages.preferredTarget(["xx-YY", "fr-FR"]) == "fr")
        precondition(GameTranslationLanguages.preferredTarget(["xx-YY"]) == "en")
        precondition(GameTranslationLanguages.normalized("zh-CN") == "zh-Hans")
        precondition(GameTranslationLanguages.apiCode("zh-Hant") == "zh-TW")
        precondition(GameTranslationLanguages.deepLCode("zh-Hans") == "ZH")
        precondition(GameTranslationLanguages.label(for: "ko") == "한국어")
        precondition(GameTranslationLanguages.choices.count >= 12)
        print("PASS: source-neutral user locale and target language provider normalization")
    }
}
