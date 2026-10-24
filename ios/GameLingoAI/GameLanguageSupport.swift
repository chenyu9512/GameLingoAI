import Foundation
import Vision
import NaturalLanguage

/// OCR language handling is independent from installed Translation packs.
/// "auto" is a profile setting, never a BCP-47 language passed to Apple APIs.
enum GameLanguageSupport {
    static let automatic = "auto"
    static func isAutomatic(_ language: String) -> Bool {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == automatic
    }

    private static let supportedLock = NSLock()
    private static var supportedByLevel: [String: [String]] = [:]

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

    /// Short game UI snippets need conservative language detection. Never guess
    /// Japanese for Latin status strings or translate a numeric-only HUD.
    static func detectedSource(in text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.unicodeScalars.filter({
            CharacterSet.letters.contains($0)
        }).count >= 3 else { return nil }

        if cleaned.unicodeScalars.contains(where: { (0x3041...0x30FF).contains($0.value) }) {
            return "ja"
        }
        if cleaned.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) {
            return "ko"
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(cleaned)
        guard let strongest = recognizer.languageHypotheses(withMaximum: 3)
            .max(by: { $0.value < $1.value }), strongest.value >= 0.48 else {
            return nil
        }
        let detected = strongest.key.rawValue
        let base = detected.components(separatedBy: "-").first ?? detected
        let supported: Set<String> = [
            "ja", "en", "ko", "zh", "fr", "de", "es", "it",
            "pt", "ru", "th", "vi", "id", "ar", "nl"
        ]
        guard supported.contains(base) else { return nil }
        if base == "zh" { return detected == "zh-Hant" ? "zh-Hant" : "zh-Hans" }
        return base
    }

    static func resolvedSource(in text: String, configured: String) -> String? {
        isAutomatic(configured) ? detectedSource(in: text) : configured
    }

    /// Auto mode uses Vision's own language-model selection, with a capped
    /// supported-language shortlist to avoid loading every model on each pass.
    /// An explicit selection keeps Vision constrained to that language.
    static func setup(_ request: VNRecognizeTextRequest, language: String) throws {
        let key = request.recognitionLevel == .fast ? "fast" : "accurate"
        supportedLock.lock()
        let cached = supportedByLevel[key]
        supportedLock.unlock()
        let available: [String]
        if let cached {
            available = cached
        } else {
            let detected = try request.supportedRecognitionLanguages()
            supportedLock.lock()
            supportedByLevel[key] = detected
            supportedLock.unlock()
            available = detected
        }

        if isAutomatic(language) {
            request.automaticallyDetectsLanguage = true
            let preferred = [
                "ja-JP", "en-US", "ko-KR", "zh-Hans", "zh-Hant",
                "fr-FR", "de-DE", "es-ES", "ru-RU", "pt-PT",
                "it-IT", "th-TH", "vi-VN", "ar-SA", "id-ID", "nl-NL"
            ]
            // Keep live OCR lightweight; the accurate recovery pass can
            // consider a wider range of writing systems.
            let maximumLanguages = request.recognitionLevel == .fast ? 5 : 12
            var selected: [String] = []
            for hint in preferred {
                let base = hint.components(separatedBy: "-").first ?? hint
                if let match = available.first(where: {
                    $0 == hint || $0 == base || $0.hasPrefix(base + "-")
                }), !selected.contains(match) {
                    selected.append(match)
                }
                if selected.count == maximumLanguages { break }
            }
            // Do not force a hard-coded default when a Vision revision has
            // different model support; its automatic detection remains on.
            if !selected.isEmpty { request.recognitionLanguages = selected }
            return
        }

        let wanted = ocrHint(for: language)
        let wantedBase = wanted.components(separatedBy: "-").first ?? wanted
        if available.contains(wanted) {
            request.recognitionLanguages = [wanted]
        } else if let alternate = available.first(where: {
            $0 == wantedBase || $0.hasPrefix(wantedBase + "-")
        }) {
            request.recognitionLanguages = [alternate]
        } else {
            request.recognitionLanguages = [wanted]
        }
    }
}
