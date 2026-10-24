import Foundation
import Vision

/// Saved game profiles keep the historic mlkitJapanese raw value readable,
/// but obsolete Google selection always migrates safely to native Vision.
enum GameOCRRouting {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case vision
        case paddleHybrid
        var id: String { rawValue }
        var title: String {
            switch self {
            case .vision: return "Apple Vision · 多语言快速"
            case .paddleHybrid: return "智能混合 · Vision + PaddleOCR"
            }
        }
    }

    static func shouldEnhance(confidence: Double, candidateCount: Int,
                              mode: Mode, performanceFast: Bool,
                              millisecondsSinceLast: Double) -> Bool {
        guard mode == .paddleHybrid && candidateCount > 0 else { return false }
        // Fast performance mode still honors the user's hybrid choice, but
        // limits expensive enhancement to very poor OCR once per 3 seconds.
        // Balanced mode can enhance more often with a broader threshold.
        return performanceFast
            ? millisecondsSinceLast >= 3000 && confidence < 0.45
            : millisecondsSinceLast >= 1200 && confidence < 0.72
    }

    static let commonOCRLanguages = [
        ("自动识别", "auto"), ("日语", "ja"), ("英语", "en"),
        ("简体中文", "zh-Hans"), ("繁体中文", "zh-Hant"),
        ("韩语", "ko"), ("法语", "fr"), ("德语", "de"),
        ("西班牙语", "es"), ("意大利语", "it"), ("葡萄牙语", "pt"),
        ("俄语", "ru"), ("泰语", "th"), ("越南语", "vi"),
        ("阿拉伯语", "ar"), ("印度尼西亚语", "id"), ("荷兰语", "nl")
    ]
}
