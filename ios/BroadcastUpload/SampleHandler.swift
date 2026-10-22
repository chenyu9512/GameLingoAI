import ReplayKit
import Vision
import Translation
import CoreImage
import ImageIO
import CoreMedia
import Foundation

final class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = OfflineOCRPipeline()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard SharedSubtitles.isGroupAvailable else {
            let issue = NSError(domain: "GameLingo", code: 1001,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "缺少 App Groups 授权。此侧载签名无法连接字幕，请重新签名主 App 和扩展。"])
            finishBroadcastWithError(issue)
            return
        }
        pipeline.start()
        SharedSubtitles.save(.init(original: "", translated: "正在捕获游戏画面…",
                                   status: "广播已连接", updatedAt: Date().timeIntervalSince1970))
    }
    override func broadcastPaused() { pipeline.pause() }
    override func broadcastResumed() { pipeline.start() }
    override func broadcastFinished() { pipeline.stop() }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientationValue = CMGetAttachment(sampleBuffer,
                                               key: RPVideoSampleOrientationKey as CFString,
                                               attachmentModeOut: nil) as? NSNumber
        let orientation = orientationValue.flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        pipeline.accept(buffer, orientation: orientation)
    }
}

/// OCR only processes selected frames. Translations remain wholly on the phone.
/// Work is serialized: no stale translation can overwrite a newer dialogue line.
private struct OCRFailure: Error { let message: String }

private final class OfflineOCRPipeline {
    private let queue = DispatchQueue(label: "GameLingo.OfflineOCR", qos: .userInitiated)
    private let lock = NSLock()
    private var lastFrameTime = 0.0
    private var processing = false
    private var active = false
    private var candidate = ""
    private var stable = 0
    private var lastDelivered = ""
    private var lastFailureAt = 0.0
    private var cache: [String: String] = [:]
    private var metrics = BroadcastTelemetry()

    func start() {
        lock.lock(); active = true; lock.unlock()
        report("正在接收画面", "正在等待游戏中的文字")
    }
    func pause() {
        lock.lock(); active = false; lock.unlock()
        report("已暂停", "系统暂停了屏幕共享")
    }
    func stop() { pause(); report("已停止", "屏幕共享已结束") }

    func accept(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        lock.lock()
        metrics.frames += 1
        let now = Date().timeIntervalSince1970
        guard active && !processing && now - lastFrameTime > 0.55 else {
            lock.unlock(); return
        }
        processing = true
        lastFrameTime = now
        lock.unlock()

        queue.async { [weak self, buffer] in
            guard let self else { return }
            self.lock.lock()
            self.metrics.scans += 1
            self.lock.unlock()
            let result = self.ocr(buffer, orientation: orientation)
            switch result {
            case .failure(let issue):
                self.failure("OCR 识别失败", issue.message)
                self.finish()
            case .success(let original):
                guard !original.isEmpty else {
                    self.report("识别中", "已接收到画面，但尚未发现文字。可在设置中切换扫描范围。")
                    self.finish()
                    return
                }
                self.lock.lock(); self.metrics.hits += 1; self.lock.unlock()
                if original == self.candidate { self.stable += 1 }
                else { self.candidate = original; self.stable = 1 }
                guard self.stable >= 2 else {
                    self.report("稳定画面", "检测到游戏文字，正在确认画面")
                    self.finish()
                    return
                }
                guard original != self.lastDelivered else {
                    self.report("正常运行", "文字没有变化，不重复翻译")
                    self.finish()
                    return
                }
                if let translated = SharedSubtitles.glossary()[original] ?? self.cache[original] {
                    self.complete(original: original, translated: translated, status: "术语 / 缓存")
                    self.finish()
                    return
                }
                self.report("翻译中", "已提取 \(original.count) 个字符")
                let language = SharedSubtitles.sourceLanguage
                Task {
                    defer { self.finish() }
                    do {
                        let session = TranslationSession(
                            installedSource: Locale.Language(identifier: language),
                            target: Locale.Language(identifier: "zh-Hans")
                        )
                        let response = try await session.translate(original)
                        let translation = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !translation.isEmpty else {
                            self.failure("翻译结果为空", "系统翻译引擎没有返回文字")
                            return
                        }
                        self.complete(original: original, translated: translation, status: "本机翻译")
                    } catch {
                        self.failure("翻译失败", error.localizedDescription)
                    }
                }
            }
        }
    }

    private func complete(original: String, translated: String, status: String) {
        lastDelivered = original
        cache[original] = translated
        if cache.count > 160 { cache.removeAll(keepingCapacity: true) }
        lock.lock(); metrics.translated += 1; lock.unlock()
        SharedSubtitles.save(.init(original: original, translated: translated,
                                   status: status, updatedAt: Date().timeIntervalSince1970))
        report("正常运行", "字幕已更新")
    }
    private func failure(_ status: String, _ detail: String) {
        let now = Date().timeIntervalSince1970
        lock.lock(); metrics.failures += 1; lock.unlock()
        report(status, detail)
        // Do not mark the OCR line as delivered after failure; retry it later.
        if now - lastFailureAt > 5 {
            SharedSubtitles.save(.init(original: candidate,
                                       translated: "翻译暂不可用：\(detail)",
                                       status: status, updatedAt: now))
            lastFailureAt = now
        }
    }
    private func report(_ phase: String, _ detail: String) {
        lock.lock()
        metrics.phase = phase
        metrics.detail = detail
        metrics.updatedAt = Date().timeIntervalSince1970
        let copy = metrics
        lock.unlock()
        SharedSubtitles.saveTelemetry(copy)
    }
    private func finish() { lock.lock(); processing = false; lock.unlock() }

    private func ocr(_ buffer: CVPixelBuffer,
                     orientation: CGImagePropertyOrientation) -> Result<String, OCRFailure> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [
            ["ja": "ja-JP", "en": "en-US", "ko": "ko-KR"][SharedSubtitles.sourceLanguage] ?? "ja-JP"
        ]
        request.minimumTextHeight = 0.012
        if SharedSubtitles.scanArea == "bottom" {
            // Vision uses lower-left normalized coordinates; reserve top UI/header area.
            request.regionOfInterest = CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.62)
        }
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer,
                                      orientation: orientation, options: [:]).perform([request])
        } catch { return .failure(OCRFailure(message: error.localizedDescription)) }
        let candidates: [(String, CGFloat, CGFloat)] = (request.results ?? []).compactMap { item in
            guard let best = item.topCandidates(1).first, best.confidence >= 0.32 else { return nil }
            let value = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return (value, item.boundingBox.midY, item.boundingBox.minX)
        }
        let ordered = candidates.sorted { first, second in
            abs(first.1 - second.1) <= 0.025 ? first.2 < second.2 : first.1 > second.1
        }
        // Upper bound keeps translation latency and widget size manageable.
        let text = ordered.prefix(9).map(\.0).joined(separator: "\n")
        return .success(text)
    }
}
