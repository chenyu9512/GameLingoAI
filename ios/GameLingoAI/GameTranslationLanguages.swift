import Foundation

/// User-facing target-language choices, independent of OCR and specific
/// translation provider capabilities. The OS/provider still validates each pair.
enum GameTranslationLanguages {
    static let choices: [(label: String, code: String)] = [
        ("简体中文", "zh-Hans"), ("繁體中文", "zh-Hant"),
        ("English", "en"), ("日本語", "ja"), ("한국어", "ko"),
        ("Français", "fr"), ("Deutsch", "de"), ("Español", "es"),
        ("Português", "pt"), ("Italiano", "it"), ("Русский", "ru"),
        ("العربية", "ar"), ("ไทย", "th"), ("Tiếng Việt", "vi"),
        ("Bahasa Indonesia", "id"), ("Nederlands", "nl")
    ]

    static func normalized(_ code: String) -> String {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = value.lowercased()
        if low == "zh-cn" || low == "zh-sg" || low == "zh-hans" { return "zh-Hans" }
        if low == "zh-tw" || low == "zh-hk" || low == "zh-hant" { return "zh-Hant" }
        let base = low.split(separator: "-").first.map(String.init) ?? low
        if base == "zh" { return "zh-Hans" }
        return base
    }

    static func preferredTarget(_ preferred: [String] = Locale.preferredLanguages) -> String {
        for language in preferred {
            let normalized = normalized(language)
            if choices.contains(where: { $0.code == normalized }) { return normalized }
        }
        return "en"
    }

    static func label(for code: String) -> String {
        choices.first(where: { $0.code == normalized(code) })?.label ?? code
    }

    // Basic provider adaptation. Individual providers still own validation.
    static func apiCode(_ code: String) -> String {
        switch normalized(code) {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return normalized(code)
        }
    }

    static func deepLCode(_ code: String) -> String {
        switch normalized(code) {
        case "zh-Hans", "zh-Hant": return "ZH"
        case "en": return "EN"
        case "pt": return "PT"
        default: return normalized(code).uppercased()
        }
    }
}
