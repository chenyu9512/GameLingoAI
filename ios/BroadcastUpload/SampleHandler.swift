import ReplayKit
import Vision
import Translation
import CoreImage
import ImageIO
import CoreMedia
import Foundation

final class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = GameLingoPipeline()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard SharedSubtitles.isGroupAvailable else {
            finishBroadcastWithError(NSError(domain: "GameLingoAI", code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "缺少 App Groups 授权；侧载签名无法共享字幕"]))
            return
        }
        pipeline.resume()
        SharedSubtitles.save(SubtitleMessage(original: "", translated: "正在接收游戏画面…",
                                              status: "广播已启动", updatedAt: Date().timeIntervalSince1970))
    }
    override func broadcastPaused() { pipeline.pause() }
    override func broadcastResumed() { pipeline.resume() }
    override func broadcastFinished() { pipeline.pause() }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                    attachmentModeOut: nil) as? NSNumber
        let orientation = value.flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        pipeline.process(pixelBuffer, orientation: orientation)
    }
}

private final class GameLingoPipeline {
    private let scanQueue = DispatchQueue(label: "com.gamelingoai.ocr", qos: .userInitiated)
    private let lock = NSLock()
    private var active = false
    private var busy = false
    private var lastScan = 0.0
    private var lastDelivered = ""
    private var candidate = ""
    private var stableFrames = 0
    private var cached: [String: String] = [:]
    private var diagnostics = BroadcastTelemetry()

    func resume() {
        lock.lock(); active = true; lock.unlock()
        report("识别已启动", "等待游戏画面中的文字")
    }
    func pause() {
        lock.lock(); active = false; lock.unlock()
        report("已停止", "屏幕广播已结束或暂停")
    }

    func process(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        lock.lock()
        diagnostics.frames += 1
        let now = Date().timeIntervalSince1970
        guard active && !busy && now - lastScan > 0.55 else {
            lock.unlock()
            return
        }
        busy = true
        lastScan = now
        lock.unlock()
        scanQueue.async { [weak self, pixelBuffer] in
            guard let self else { return }
            self.lock.lock(); self.diagnostics.scans += 1; self.lock.unlock()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [
                ["ja":"ja-JP","en":"en-US","ko":"ko-KR"][SharedSubtitles.sourceLanguage] ?? "ja-JP"
            ]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012
            if SharedSubtitles.scanArea == "bottom" {
                request.regionOfInterest = CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.62)
            }
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                          orientation: orientation, options: [:]).perform([request])
            } catch {
                self.failed("文字识别失败", error.localizedDescription)
                self.release()
                return
            }
            let blocks: [(String,CGFloat,CGFloat)] = (request.results ?? []).compactMap { item in
                guard let best = item.topCandidates(1).first, best.confidence >= 0.32 else { return nil }
                let str = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !str.isEmpty else { return nil }
                return (str,item.boundingBox.midY,item.boundingBox.minX)
            }
            let text = blocks.sorted { a,b in
                abs(a.1-b.1) <= 0.025 ? a.2 < b.2 : a.1 > b.1
            }.prefix(9).map { $0.0 }.joined(separator: "\n")
            guard !text.isEmpty else {
                self.report("扫描正常", "未发现文字；可以切换扫描范围")
                self.release()
                return
            }
            self.lock.lock(); self.diagnostics.hits += 1; self.lock.unlock()
            if text == self.candidate { self.stableFrames += 1 }
            else { self.candidate = text; self.stableFrames = 1 }
            guard self.stableFrames >= 2, text != self.lastDelivered else {
                self.report("扫描正常", "正在等待文字变化")
                self.release()
                return
            }
            if let ready = SharedSubtitles.glossary()[text] ?? self.cached[text] {
                self.success(text, ready, "术语 / 缓存")
                self.release()
                return
            }
            self.report("正在翻译", "检测到 \(text.count) 字符")
            Task {
                defer { self.release() }
                do {
                    let engine = TranslationSession(
                        installedSource: Locale.Language(identifier: SharedSubtitles.sourceLanguage),
                        target: Locale.Language(identifier: "zh-Hans"))
                    let response = try await engine.translate(text)
                    let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !translated.isEmpty else {
                        self.failed("翻译为空", "系统没有返回中文")
                        return
                    }
                    self.success(text, translated, "设备内翻译")
                } catch {
                    // A failed translation must be retried; never change lastDelivered here.
                    self.failed("翻译失败", error.localizedDescription)
                }
            }
        }
    }

    private func success(_ original: String, _ translation: String, _ status: String) {
        lastDelivered = original
        cached[original] = translation
        if cached.count > 150 { cached.removeAll(keepingCapacity: true) }
        lock.lock(); diagnostics.translated += 1; lock.unlock()
        SharedSubtitles.save(SubtitleMessage(original: original, translated: translation,
                                              status: status, updatedAt: Date().timeIntervalSince1970))
        report("正在运行", "字幕已更新")
    }
    private func failed(_ phase: String, _ message: String) {
        lock.lock(); diagnostics.failures += 1; lock.unlock()
        report(phase, message)
        SharedSubtitles.save(SubtitleMessage(original: candidate, translated: "翻译暂不可用：\(message)",
                                              status: phase, updatedAt: Date().timeIntervalSince1970))
    }
    private func release() {
        lock.lock(); busy = false; lock.unlock()
    }
    private func report(_ phase: String, _ detail: String) {
        lock.lock()
        diagnostics.phase = phase
        diagnostics.detail = detail
        diagnostics.updatedAt = Date().timeIntervalSince1970
        let snapshot = diagnostics
        lock.unlock()
        SharedSubtitles.saveTelemetry(snapshot)
    }
}
