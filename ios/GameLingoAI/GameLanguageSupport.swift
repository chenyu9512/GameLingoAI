import Foundation
import Vision

/// OCR language hints. Downloading Apple Translation languages does not
/// download Vision models, and the set supported by the OS can be different.
enum GameLanguageSupport {
    static func ocrHint(for language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.components(separatedBy: "-").first?.lowercased() ?? trimmed
        let presets: [String: String] = [
            "ja": "ja-JP", "en": "en-US", "ko": "ko-KR",
            "fr": "fr-FR", "de": "de-DE", "es": "es-ES",
            "it": "it-IT", "pt": "pt-PT", "ru": "ru-RU",
            "zh": "zh-Hans", "th": "th-TH", "vi": "vi-VN",
            "id": "id-ID", "ar": "ar-SA", "nl": "nl-NL"
        ]
        return trimmed.contains("-") ? trimmed : (presets[prefix] ?? trimmed)
    }

    /// Query Vision on the current OS. If the requested hint is unsupported,
    /// try the supported regional code of the same language, never Japanese
    /// as an unrelated fallback.
    static func setup(_ request: VNRecognizeTextRequest, language: String) throws {
        let wanted = ocrHint(for: language)
        let available = try request.supportedRecognitionLanguages()
        let wantedBase = wanted.components(separatedBy: "-").first ?? wanted
        if available.contains(wanted) {
            request.recognitionLanguages = [wanted]
        } else if let alternate = available.first(where: {
            $0 == wantedBase || $0.hasPrefix(wantedBase + "-")
        }) {
            request.recognitionLanguages = [alternate]
        } else {
            // Let Vision emit a clear error rather than silently translating
            // the wrong language. The user's offline language pack is separate.
            request.recognitionLanguages = [wanted]
        }
    }
}
