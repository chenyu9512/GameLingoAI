import Foundation
import SwiftUI
import ScreenCaptureKit
import Vision
import Translation
import CoreMedia
import CoreVideo
import ImageIO

// iOS 27 direct screen capture: no extension and no cross-process IPC.
// The user must grant capture permission using the system screen-sharing picker.
@available(iOS 27.0, *)
final class DirectGameCapture: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    static let shared = DirectGameCapture()

    @Published private(set) var phase = "未启动"
    @Published private(set) var details = "从系统选择整个屏幕，返回游戏后识别与翻译都在本机进行。"
    @Published private(set) var frames = 0
    @Published private(set) var scans = 0
    @Published private(set) var translatedCount = 0
    @Published private(set) var original = ""
    @Published private(set) var latest = ""
    @Published private(set) var isCapturing = false

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "GameLingo.direct.capture", qos: .utility)
    private let gate = NSLock()
    private var lastAccepted: TimeInterval = 0
    private var working = false
    private var pendingText = ""
    private var stable = 0
    private var lastFinished = ""
    private var cache: [String: String] = [:]
    private var language = "ja"
    private var region = "bottom"
    private var observing = false

    private override init() {
        super.init()
        let saved = UserDefaults.standard
        language = saved.string(forKey: "direct.sourceLanguage") ?? "ja"
        region = saved.string(forKey: "direct.scanArea") ?? "bottom"
    }

    func configure(language: String, scanArea: String) {
        gate.lock()
        self.language = language
        self.region = scanArea
        gate.unlock()
        UserDefaults.standard.set(language, forKey: "direct.sourceLanguage")
        UserDefaults.standard.set(scanArea, forKey: "direct.scanArea")
    }

    func start() {
        DispatchQueue.main.async {
            let picker = SCContentSharingPicker.shared
            if !self.observing {
                picker.add(self)
                self.observing = true
            }
            picker.isActive = true
            self.phase = "等待用户授权"
            self.details = "请选择整个屏幕（不是仅当前 App），随后切回游戏。"
            picker.present()
        }
    }

    func stop() {
        guard let old = stream else { return }
        stream = nil
        old.stopCapture { [weak self] error in
            DispatchQueue.main.async {
                self?.isCapturing = false
                self?.phase = "已停止"
                self?.details = error?.localizedDescription ?? "屏幕采集已停止"
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for selectedStream: SCStream?) {
        DispatchQueue.main.async { self.launch(filter) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            self.phase = "已取消"
            self.details = "未授予屏幕捕获权限"
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.phase = "系统授权失败"
            self.details = error.localizedDescription
        }
    }

    private func launch(_ filter: SCContentFilter) {
        stop()
        let config = SCStreamConfiguration()
        // iOS ScreenCaptureKit manages frame pacing and buffering internally.
        // minimumFrameInterval and queueDepth are macOS-only API properties.
        config.capturesAudio = false
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            self.stream = newStream
            phase = "正在连接屏幕"
            details = "屏幕数据将在设备内处理"
            newStream.startCapture { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        self?.phase = "启动失败"
                        self?.details = error.localizedDescription
                        self?.isCapturing = false
                    } else {
                        self?.phase = "正在采集"
                        self?.details = "屏幕捕获已启动，请切换到游戏"
                        self?.isCapturing = true
                    }
                }
            }
        } catch {
            phase = "视频流连接失败"
            details = error.localizedDescription
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.phase = "采集已停止"
            self.details = error.localizedDescription
            self.isCapturing = false
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        gate.lock()
        let now = Date().timeIntervalSince1970
        let take = !working && now - lastAccepted >= 0.65
        if take {
            working = true
            lastAccepted = now
        }
        gate.unlock()
        guard take else { return }

        // This delegate is already called on the captureQueue, not the UI thread.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.013
        gate.lock()
        let source = language
        let scanArea = region
        gate.unlock()
        request.recognitionLanguages = [["ja":"ja-JP", "en":"en-US", "ko":"ko-KR"][source] ?? "ja-JP"]
        if scanArea == "bottom" {
            request.regionOfInterest = CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.63)
        }
        let recognized: String
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
                .perform([request])
            let results = (request.results ?? []).compactMap { item -> (String, CGFloat)? in
                guard let result = item.topCandidates(1).first, result.confidence >= 0.35 else { return nil }
                let text = result.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : (text, item.boundingBox.midY)
            }
            recognized = results.sorted { $0.1 > $1.1 }.prefix(8).map { $0.0 }.joined(separator: "\n")
        } catch {
            DispatchQueue.main.async {
                self.phase = "OCR 出错"
                self.details = error.localizedDescription
            }
            releaseGate()
            return
        }

        let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            self.frames += 1
            self.scans += 1
        }
        guard !text.isEmpty else {
            releaseGate()
            return
        }
        if text == pendingText { stable += 1 }
        else { pendingText = text; stable = 1 }
        guard stable >= 2, text != lastFinished else {
            releaseGate()
            return
        }
        Task { @MainActor in
            await self.translate(text, source: source)
            self.releaseGate()
        }
    }

    @MainActor private func translate(_ text: String, source: String) async {
        original = text
        if let cached = cache[text] {
            latest = cached
            lastFinished = text
            phase = "本地缓存"
            return
        }
        phase = "设备内翻译中"
        details = "识别到 \(text.count) 个字符"
        do {
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: source),
                target: Locale.Language(identifier: "zh-Hans")
            )
            let translated = try await session.translate(text).targetText
            let result = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else {
                phase = "空译文"
                details = "翻译引擎返回空结果"
                return
            }
            cache[text] = result
            if cache.count > 120 { cache.removeAll(keepingCapacity: true) }
            lastFinished = text
            latest = result
            translatedCount += 1
            phase = "翻译已更新"
            details = "无需扩展，设备内完成"
        } catch {
            phase = "本地翻译失败"
            details = error.localizedDescription
            // Do not mark as complete; the next stable frame can retry.
        }
    }

    private func releaseGate() {
        gate.lock()
        working = false
        gate.unlock()
    }
}

@available(iOS 27.0, *)
struct DirectCapturePanel: View {
    @ObservedObject private var capture = DirectGameCapture.shared
    let language: String
    let scanArea: String
    let onSubtitle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: capture.isCapturing ? "record.circle.fill" : "display")
                Text("iOS 27 单进程屏幕采集")
                    .font(.system(size: 12, weight: .semibold))
            }.foregroundStyle(.mint)
            Text(capture.phase).font(.headline)
            Text(capture.details).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("OCR \(capture.scans)")
                Spacer()
                Text("翻译 \(capture.translatedCount)")
            }.font(.caption.monospacedDigit())
            if !capture.latest.isEmpty {
                Text(capture.latest).font(.headline)
            }
            Button(capture.isCapturing ? "停止采集" : "授权并捕获整个屏幕") {
                if capture.isCapturing { capture.stop() }
                else { capture.start() }
            }.buttonStyle(.borderedProminent)
        }
        .onAppear { capture.configure(language: language, scanArea: scanArea) }
        .onChange(of: language) { _, value in capture.configure(language: value, scanArea: scanArea) }
        .onChange(of: scanArea) { _, value in capture.configure(language: language, scanArea: value) }
        .onReceive(capture.$latest) { text in
            guard !text.isEmpty else { return }
            onSubtitle(text)
        }
    }
}
