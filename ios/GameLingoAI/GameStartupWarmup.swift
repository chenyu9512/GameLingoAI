import Foundation
import SwiftUI
import Vision
import Translation
import CoreGraphics

/// Best-effort cold-start preparation. No screen capture, no network provider,
/// no language download or user text is involved in prewarming.
@available(iOS 27.0, *)
@MainActor
final class GameStartupWarmup: ObservableObject {
    static let shared = GameStartupWarmup()
    @Published private(set) var status = "引擎尚未预热"
    @Published private(set) var visionMilliseconds = 0
    @Published private(set) var translationMilliseconds = 0
    @Published private(set) var languageReady = false
    @Published private(set) var isPreparing = false

    private var activeKey = ""
    private var completedKey = ""
    private var running: Task<Void, Never>?

    func prepare(language: String, targetLanguage: String, offline: Bool) {
        // In automatic mode no source language is known yet. Do not choose
        // Japanese or attempt to download/preload an unrelated language pair.
        let isAutomatic = GameLanguageSupport.isAutomatic(language)
        let key = "\(language)|\(targetLanguage)|\(offline)"
        guard key != completedKey, key != activeKey else { return }
        running?.cancel()
        activeKey = key
        isPreparing = true
        status = "正在准备 Vision OCR"
        running = Task { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let visionMs = await Task.detached(priority: .utility) {
                GameStartupWarmup.prepareVision(language: language)
            }.value
            guard let self, !Task.isCancelled, self.activeKey == key else { return }
            self.visionMilliseconds = visionMs
            self.status = "Vision 已预热 · 检查离线翻译"
            GameDiagnosticLog.shared.event("startup_vision", metrics: [
                "cold_vision_ms": visionMs
            ])
            if !offline {
                self.finish(key: key, started: started, result: "Vision 已就绪 · 在线翻译按需连接")
                return
            }
            if isAutomatic {
                self.languageReady = false
                self.finish(key: key, started: started,
                            result: "Vision 已就绪 · 检测到源语言后检查对应离线资源")
                return
            }
            let source = Locale.Language(identifier: language)
            let target = Locale.Language(identifier: targetLanguage)
            let state = await LanguageAvailability().status(from: source, to: target)
            guard !Task.isCancelled, self.activeKey == key else { return }
            if state != .installed {
                self.languageReady = false
                self.finish(key: key, started: started,
                            result: state == .unsupported
                                ? "Vision 已准备 · 该语言对不支持离线翻译"
                                : "Vision 已准备 · 请先安装离线语言包")
                GameDiagnosticLog.shared.event("startup_translation", metrics: [
                    "language_state": state == .unsupported ? 3 : 2
                ])
                return
            }
            self.languageReady = true
            self.status = "正在预热离线翻译模型"
            let translationStarted = CFAbsoluteTimeGetCurrent()
            do {
                let session = TranslationSession(installedSource: source, target: target)
                // A small fixed string only; never submit captured game content.
                let sample: [String: String] = [
                    "ja": "こんにちは", "en": "Hello", "ko": "안녕하세요",
                    "fr": "Bonjour", "de": "Hallo", "es": "Hola",
                    "pt": "Olá", "it": "Ciao", "ru": "Привет"
                ]
                _ = try await session.translate(sample[language] ?? "Hello")
                guard !Task.isCancelled, self.activeKey == key else { return }
                self.translationMilliseconds = max(0, Int(
                    (CFAbsoluteTimeGetCurrent() - translationStarted) * 1000))
                GameDiagnosticLog.shared.event("startup_translation", metrics: [
                    "language_state": 1,
                    "cold_translation_ms": self.translationMilliseconds
                ])
                self.finish(key: key, started: started, result: "Vision 与离线翻译已预热")
            } catch {
                guard !Task.isCancelled, self.activeKey == key else { return }
                self.translationMilliseconds = max(0, Int(
                    (CFAbsoluteTimeGetCurrent() - translationStarted) * 1000))
                self.finish(key: key, started: started,
                            result: "Vision 已准备 · 翻译预热未完成（仍可启动）")
                GameDiagnosticLog.shared.event("startup_translation", metrics: [
                    "language_state": 4,
                    "cold_translation_ms": self.translationMilliseconds
                ])
            }
        }
    }

    private func finish(key: String, started: CFAbsoluteTime, result: String) {
        // Missing system packs are not a permanent "completed" state.
        // Recheck on foreground after the user downloads a language pack.
        completedKey = (!key.hasSuffix("|true") || languageReady
                        || key.hasPrefix("auto|")) ? key : ""
        activeKey = ""
        isPreparing = false
        status = result
        GameDiagnosticLog.shared.event("startup_ready", metrics: [
            "cold_total_ms": max(0, Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
        ])
    }

    nonisolated private static func prepareVision(language: String) -> Int {
        let began = CFAbsoluteTimeGetCurrent()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        do {
            try GameLanguageSupport.setup(request, language: language)
            guard let bitmap = CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage() else { return 0 }
            try VNImageRequestHandler(cgImage: bitmap, options: [:]).perform([request])
        } catch {
            // Unsupported device models must not block normal capture.
            return 0
        }
        return max(0, Int((CFAbsoluteTimeGetCurrent() - began) * 1000))
    }
}
