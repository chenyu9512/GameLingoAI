import ReplayKit
import Vision
import Translation
import CoreImage
import ImageIO
import CoreMedia
import Foundation

final class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = OfflineOCRPipeline()

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        pipeline.start()
        SharedSubtitles.save(.init(original: "", translated: "游戏翻译已开始", status: "识别中", updatedAt: Date().timeIntervalSince1970))
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

private final class OfflineOCRPipeline {
    private let queue = DispatchQueue(label: "GameLingo.OfflineOCR", qos: .utility)
    private let lock = NSLock()
    private var lastFrameTime = 0.0
    private var processing = false
    private var active = false
    private var previousOCR = ""
    private var pendingOCR = ""
    private var stableFrames = 0
    private var cache: [String: String] = [:]

    func start() {
        lock.lock(); active = true; lock.unlock()
    }
    func pause() { lock.lock(); active = false; lock.unlock() }
    func stop() { pause() }

    func accept(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        lock.lock()
        let now = Date().timeIntervalSince1970
        guard active && !processing && now - lastFrameTime >= 0.85 else {
            lock.unlock(); return
        }
        processing = true
        lastFrameTime = now
        lock.unlock()

        queue.async { [weak self, buffer] in
            guard let self else { return }
            let lines = self.ocr(buffer, orientation: orientation)
            let original = lines.joined(separator: "\n")
            if original == self.pendingOCR { self.stableFrames += 1 }
            else { self.pendingOCR = original; self.stableFrames = 1 }
            guard !original.isEmpty, original != self.previousOCR, self.stableFrames >= 2 else {
                self.releaseProcessing(); return
            }
            self.previousOCR = original
            // Exact phrase matches for skill names, item names and short UI terms.
            // Avoid replacing substrings inside full dialogue where it could change the meaning.
            if let fixed = SharedSubtitles.glossary()[original] {
                SharedSubtitles.save(.init(original: original, translated: fixed,
                                           status: "用户术语表", updatedAt: Date().timeIntervalSince1970))
                self.releaseProcessing()
                return
            }
            if let cached = self.cache[original] {
                SharedSubtitles.save(.init(original: original, translated: cached,
                                        status: "本地缓存", updatedAt: Date().timeIntervalSince1970))
                self.releaseProcessing()
                return
            }
            // This initializer is only available from iOS 26. Language models must
            // first be installed from the host App's "下载语言包" button.
            let source = self.detectLanguage(original)
            Task {
                defer { self.releaseProcessing() }
                do {
                    let session = TranslationSession(installedSource: Locale.Language(identifier: source),
                                                     target: Locale.Language(identifier: "zh-Hans"))
                    let response = try await session.translate(original)
                    let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.queue.async {
                        self.cache[original] = translated
                        if self.cache.count > 120 { self.cache.removeAll(keepingCapacity: true) }
                    }
                    SharedSubtitles.save(.init(original: original, translated: translated,
                                            status: "设备离线翻译", updatedAt: Date().timeIntervalSince1970))
                } catch {
                    SharedSubtitles.save(.init(original: original,
                                            translated: "本地翻译失败，请回到 App 安装该语言包。",
                                            status: String(describing: error).prefix(16).description,
                                            updatedAt: Date().timeIntervalSince1970))
                }
            }
        }
    }

    private func ocr(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ja-JP", "en-US", "ko-KR"]
        request.minimumTextHeight = 0.015
        do { try VNImageRequestHandler(cvPixelBuffer: buffer,
                                       orientation: orientation, options: [:]).perform([request]) }
        catch { return [] }
        let tuples: [(String, CGFloat, CGFloat)] = (request.results ?? []).compactMap { result in
            guard let candidate = result.topCandidates(1).first, candidate.confidence > 0.38 else { return nil }
            let value = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count > 1 else { return nil }
            return (value, result.boundingBox.maxY, result.boundingBox.minX)
        }
        let ordered = tuples.sorted { first, second in
            abs(first.1 - second.1) < 0.02 ? first.2 < second.2 : first.1 > second.1
        }
        return Array(ordered.prefix(6)).map { $0.0 }
    }

    private func detectLanguage(_ text: String) -> String {
        if text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains(Int($0.value)) }) { return "ko" }
        if text.unicodeScalars.contains(where: {
            (0x3040...0x30FF).contains(Int($0.value))
        }) { return "ja" }
        // Games with Kanji-only Japanese text may be mistaken for Chinese.
        if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) { return "ja" }
        return "en"
    }

    private func releaseProcessing() {
        lock.lock(); processing = false; lock.unlock()
    }
}
