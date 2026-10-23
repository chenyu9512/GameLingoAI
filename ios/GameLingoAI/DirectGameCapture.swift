import Foundation
import SwiftUI
import ScreenCaptureKit
import Vision
import Translation
import CoreMedia
import CoreVideo
import ImageIO

// iOS 27: screen -> Vision -> on-device Translation -> latest-only bilingual line.
// ScreenCaptureKit delivers frames on captureQueue; no ReplayKit or App Groups.
@available(iOS 27.0, *)
final class DirectGameCapture: NSObject, ObservableObject,
                               SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    static let shared = DirectGameCapture()

    @Published private(set) var phase = "未启动"
    @Published private(set) var details = "先准备语言包，再授权捕获整个屏幕。"
    @Published private(set) var isCapturing = false
    @Published private(set) var frames = 0
    @Published private(set) var scans = 0
    @Published private(set) var translatedCount = 0
    @Published private(set) var ignoredFrames = 0
    @Published private(set) var original = ""
    @Published private(set) var latest = ""
    @Published private(set) var latestLine: GameSubtitleLine?
    @Published private(set) var ocrConfidence: Double = 0
    @Published private(set) var ocrElapsedMs = 0
    @Published private(set) var translationElapsedMs = 0
    @Published private(set) var lastFrameAt: Date?
    @Published private(set) var failures = 0
    @Published private(set) var lastError = ""
    @Published private(set) var detectedLayout: GameFrameLayout = .portrait
    @Published private(set) var screenDimensions = "等待画面"
    @Published private(set) var activeRotation: GameScreenRotation = .automatic

    private struct Snapshot: Equatable {
        var profileID: UUID
        var name: String
        var language: String
        var portraitROI: CGRect
        var landscapeROI: CGRect
        var rotation: GameScreenRotation
        var excluded: CGRect?
        var glossary: [String: String]
        var performance: GamePerformance
        var provider: GameTranslationProvider
        var endpoint: GameTranslationEndpoint

        static let initial = Snapshot(profileID: UUID(), name: "默认游戏", language: "ja",
                                      portraitROI: GameOCRBox.dialogue.rect,
                                      landscapeROI: GameOCRBox.landscapeDialogue.rect,
                                      rotation: .automatic,
                                      excluded: nil, glossary: [:],
                                      performance: .balanced,
                                      provider: .offline, endpoint: GameTranslationEndpoint())
    }

    private struct Recognition {
        let text: String
        let confidence: Double
        let lineCount: Int
    }

    private let captureQueue = DispatchQueue(label: "GameLingo.ocr.queue", qos: .userInitiated)
    private let menuQueue = DispatchQueue(label: "GameLingo.fullscreen.ocr", qos: .utility)
    private let gate = NSLock()
    private var config = Snapshot.initial
    private var busy = false
    private var lastAcceptedAt: TimeInterval = 0
    private var lastFingerprint: UInt64 = 0
    private var lastOCRAt: TimeInterval = 0
    // Only touched on captureQueue: rotation/dimensions changes reset OCR
    // stabilisation without confusing previous frames with new geometry.
    private var lastFrameGeometry = ""
    // Protected by gate; full-screen OCR is independently scheduled and never
    // blocks the faster PiP OCR callback queue.
    private var menuInFlight = false
    private var forceMenuScan = false
    private var manualMenuReadyAt: TimeInterval = 0
    private var hostAppForeground = true
    private var lastMenuScannedAt: TimeInterval = 0
    private var lastMenuFingerprint: UInt64 = 0
    private var lastPageFingerprint: UInt64 = 0
    private var menuStaticSince: TimeInterval = 0
    private var menuGeometryRevision = 0
    // Mutable only on captureQueue.
    private var candidate = ""
    private var candidateCount = 0

    // Mutable only on the main actor.
    private var stream: SCStream?
    private var pickerObserved = false
    private var captureGeneration = 0
    private var translationRevision = 0
    private var pendingTranslation: Task<Void, Never>?
    private var latestSubmitted = ""
    private var latestSubmittedAt: TimeInterval = 0
    private var lastCompleted = ""
    private var translationCache: [String: String] = [:]
    private var retries = 0
    private var captureRetries = 0
    private var lastRequestedFilter: SCContentFilter?

    private override init() {
        super.init()
    }

    /// Called by SwiftUI scene lifecycle; prevents scanning GameLingo's own UI
    /// as if it were a game menu.
    @MainActor
    func setHostAppForeground(_ value: Bool) {
        gate.lock()
        hostAppForeground = value
        gate.unlock()
    }

    // Called from SwiftUI when a selected game profile or power mode changes.
    @MainActor
    func configure(profile: GameProfile, performance: GamePerformance) {
        // Bundle-only terminology: short names and original RPG prompts.
        // User game glossary overrides bundled entries.
        var mergedTerms = GameRPGDictionary.mapping
        if !profile.dragonQuestEnabled {
            for term in GameRPGDictionary.terms
                where term.category == "勇者斗恶龙专用" {
                mergedTerms.removeValue(forKey: term.japanese)
            }
        }
        mergedTerms.merge(GameLingoStore.glossaryMap(profile.glossary)) { _, custom in custom }
        let snapshot = Snapshot(profileID: profile.id, name: profile.name, language: profile.language,
                                portraitROI: profile.region.rect,
                                landscapeROI: profile.region(for: .landscape).rect,
                                rotation: profile.screenRotation,
                                excluded: profile.excluded?.rect,
                                glossary: mergedTerms, performance: performance,
                                provider: GameLingoStore.shared.provider,
                                endpoint: GameLingoStore.shared.endpoint)
        gate.lock()
        let changed = config != snapshot
        if changed {
            config = snapshot
            forceMenuScan = false
            manualMenuReadyAt = 0
            lastMenuScannedAt = 0
            lastMenuFingerprint = 0
            lastPageFingerprint = 0
            menuStaticSince = 0
            menuGeometryRevision += 1
            menuInFlight = false
        }
        gate.unlock()
        // A tab change or SwiftUI view reappearance must not restart OCR,
        // cancel a menu batch, or wipe the already translated dialogue.
        guard changed else { return }
        GameMenuCatalog.shared.cancelForProfileChange()
        captureQueue.async { [weak self] in
            self?.lastFingerprint = 0
            self?.lastFrameGeometry = ""
            self?.candidate = ""
            self?.candidateCount = 0
        }
        // Ensure no earlier profile's translation can overwrite the new one.
        translationRevision += 1
        pendingTranslation?.cancel()
        pendingTranslation = nil
        latestSubmitted = ""
        lastCompleted = ""
        translationCache.removeAll(keepingCapacity: true)
        phase = isCapturing ? "已切换游戏设置" : "未启动"
        details = "当前游戏：" + profile.name
    }

    func start() {
        let picker = SCContentSharingPicker.shared
        if !pickerObserved {
            picker.add(self)
            pickerObserved = true
        }
        picker.isActive = true
        phase = "等待系统授权"
        details = "请选择整个屏幕，完成后切换到游戏。"
        picker.present()
    }

    func stop() {
        captureGeneration += 1
        let old = stream
        stream = nil
        lastRequestedFilter = nil
        GameMenuCatalog.shared.cancelForProfileChange()
        pendingTranslation?.cancel()
        translationRevision += 1
        pendingTranslation = nil
        isCapturing = false
        phase = "已停止"
        details = "屏幕采集已结束"
        old?.stopCapture { _ in }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for selectedStream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            self?.captureRetries = 0
            self?.launch(filter)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            self.phase = "已取消"
            self.details = "没有授予屏幕捕获权限"
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.phase = "屏幕授权失败"
            self.details = error.localizedDescription
            self.lastError = error.localizedDescription
            self.failures += 1
        }
    }

    private func launch(_ filter: SCContentFilter) {
        captureGeneration += 1
        let generation = captureGeneration
        let old = stream
        old?.stopCapture { _ in }
        stream = nil
        isCapturing = false
        lastRequestedFilter = filter

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        let next = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try next.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            stream = next
            phase = "正在连接屏幕"
            details = "屏幕内容只在本机识别；不存储原始画面。"
            next.startCapture { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.captureGeneration == generation else { return }
                    if let error {
                        self.isCapturing = false
                        self.phase = "启动失败"
                        self.details = error.localizedDescription
                        self.lastError = error.localizedDescription
                        self.failures += 1
                        self.retryCaptureIfAppropriate()
                    } else {
                        self.isCapturing = true
                        self.phase = "等待游戏画面"
                        self.details = "采集已经启动，正在识别游戏对白"
                    }
                }
            }
        } catch {
            phase = "采集连接失败"
            details = error.localizedDescription
            lastError = error.localizedDescription
            failures += 1
        }
    }

    // Retry only transient stream errors while a valid user-selected filter exists.
    // Do not silently present the system consent picker.
    private func retryCaptureIfAppropriate() {
        guard captureRetries < 2, let filter = lastRequestedFilter else { return }
        captureRetries += 1
        let attempt = captureRetries
        details = "采集暂时中断，正在重试 \(attempt)/2"
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt * 2)) { [weak self] in
            guard let self, !self.isCapturing,
                  self.captureRetries == attempt,
                  self.lastRequestedFilter != nil else { return }
            self.launch(filter)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.stream === stream else { return }
            self.isCapturing = false
            self.phase = "采集意外停止"
            self.details = error.localizedDescription
            self.lastError = error.localizedDescription
            self.failures += 1
            self.retryCaptureIfAppropriate()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Callback is serialized on captureQueue; the lock protects UI settings.
        let now = Date().timeIntervalSince1970
        gate.lock()
        let snapshot = config
        let shouldAccept = !busy && now - lastAcceptedAt >= snapshot.performance.minimumInterval
        if shouldAccept {
            busy = true
            lastAcceptedAt = now
        }
        gate.unlock()
        guard shouldAccept else { return }

        defer {
            gate.lock()
            busy = false
            gate.unlock()
        }
        let geometry = GameCaptureGeometry(
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            rotation: snapshot.rotation)
        if geometry.identity != lastFrameGeometry {
            lastFrameGeometry = geometry.identity
            lastFingerprint = 0
            lastOCRAt = 0
            candidate = ""
            candidateCount = 0
            gate.lock()
            lastMenuFingerprint = 0
            lastPageFingerprint = 0
            menuStaticSince = 0
            lastMenuScannedAt = 0
            menuGeometryRevision += 1
            menuInFlight = false
            gate.unlock()
            DispatchQueue.main.async {
                self.detectedLayout = geometry.layout
                self.activeRotation = geometry.rotation
                self.screenDimensions = "\(geometry.width) × \(geometry.height)"
                // Invalidate translation and static pages from the prior
                // layout before they can replace a newly rotated screen.
                self.translationRevision += 1
                self.pendingTranslation?.cancel()
                self.pendingTranslation = nil
                self.lastCompleted = ""
                GameMenuCatalog.shared.cancelForProfileChange()
            }
        }
        let region = geometry.layout == .portrait
            ? snapshot.portraitROI : snapshot.landscapeROI
        scheduleMenuScan(buffer, snapshot: snapshot, geometry: geometry, now: now)
        let fingerprint = frameFingerprint(buffer, region: geometry.rawRegion(for: region))
        let staticScene = fingerprint != 0 && fingerprint == lastFingerprint
        // Still recheck static frames periodically: failed translations may retry,
        // and the same visual frame may need new state after UI changes.
        if staticScene && now - lastOCRAt < 3.0 {
            DispatchQueue.main.async {
                self.ignoredFrames += 1
                self.lastFrameAt = Date()
            }
            return
        }
        lastFingerprint = fingerprint
        lastOCRAt = now

        let startedAt = CFAbsoluteTimeGetCurrent()
        let recognition = recognize(buffer, using: snapshot,
                                    geometry: geometry, region: region)
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        DispatchQueue.main.async {
            self.frames += 1
            self.scans += 1
            self.lastFrameAt = Date()
            self.ocrElapsedMs = elapsedMs
            self.ocrConfidence = recognition.confidence
        }
        let text = recognition.text
        guard !text.isEmpty else {
            DispatchQueue.main.async {
                self.phase = "等待对白"
                self.details = "已收到画面，当前识别区域没有可用文字"
            }
            candidate = ""
            candidateCount = 0
            return
        }
        if candidate == text { candidateCount += 1 }
        else { candidate = text; candidateCount = 1 }
        // A stable, high-confidence line can be sent immediately instead of
        // waiting for a second OCR cycle. Dense menus use the full-page lane.
        guard recognition.lineCount <= 5 && text.count <= 190 else { return }
        let needed = snapshot.performance == .fast || recognition.confidence >= 0.76 ? 1 : 2
        guard candidateCount >= needed else { return }

        DispatchQueue.main.async { [weak self] in
            self?.submit(text, profile: snapshot, detectedAt: now)
        }
    }


    /// Trigger a complete scan of the next available captured frame. No new
    /// iOS screen permission prompt is needed when the stream is running.
    @MainActor
    func requestFullScreenScan() {
        guard isCapturing else {
            phase = "请先开始屏幕采集"
            details = "授权并捕获整个屏幕后，才能扫描游戏菜单"
            return
        }
        gate.lock()
        forceMenuScan = true
        manualMenuReadyAt = Date().timeIntervalSince1970 + 2.5
        gate.unlock()
        GameMenuCatalog.shared.statusForUserRequest()
    }

    // This lane intentionally checks the entire image, unlike fast PiP OCR.
    // Stable pages are scanned promptly; animated menus get a periodic
    // fallback scan (8 sec), and the user can request an immediate scan.
    private func scheduleMenuScan(_ buffer: CVPixelBuffer,
                                  snapshot: Snapshot, geometry: GameCaptureGeometry,
                                  now: TimeInterval) {
        gate.lock()
        let forced = forceMenuScan
        let ready = now >= manualMenuReadyAt
        let visible = hostAppForeground
        let enoughTime = now - lastMenuScannedAt >= 0.7
        let running = menuInFlight
        gate.unlock()
        // Pause menu OCR while our own settings screen is visible.
        // Manual scans wait until the user has returned to the game.
        guard !visible, (!forced || ready), (forced || enoughTime), !running else { return }

        let fingerprint = frameFingerprint(buffer, region: CGRect(x: 0, y: 0, width: 1, height: 1))
        gate.lock()
        if lastMenuScannedAt == 0 {
            // Start the auto-scan clock on the first actual game frame,
            // not at Unix epoch 0 (which would trigger the fallback instantly).
            lastMenuScannedAt = now
        }
        if fingerprint != lastMenuFingerprint {
            lastMenuFingerprint = fingerprint
            menuStaticSince = now
        }
        let stable = now - menuStaticSince >= 1.1
        let changed = fingerprint != lastPageFingerprint
        let fallbackInterval: TimeInterval = snapshot.performance == .battery ? 14 : 9
        let fallback = now - lastMenuScannedAt >= fallbackInterval
        let perform = !menuInFlight && (forced || (stable && changed) || fallback)
        let revision = menuGeometryRevision
        if perform {
            menuInFlight = true
            forceMenuScan = false
            lastMenuScannedAt = now
            lastPageFingerprint = fingerprint
        }
        gate.unlock()
        guard perform else { return }

        menuQueue.async { [weak self] in
            guard let self else { return }
            let started = CFAbsoluteTimeGetCurrent()
            let textBlocks = self.recognizeFullScreen(buffer, using: snapshot,
                                                     geometry: geometry)
            let took = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            self.gate.lock()
            let current = self.menuGeometryRevision == revision
            if current { self.menuInFlight = false }
            self.gate.unlock()
            guard current else { return }
            DispatchQueue.main.async {
                // A delayed OCR result must never repopulate the catalog after
                // the user stopped capture or switched to a different stream.
                guard self.isCapturing, self.stream != nil else { return }
                GameMenuCatalog.shared.receive(
                    textBlocks, profileID: snapshot.profileID,
                    gameName: snapshot.name, language: snapshot.language,
                    glossary: snapshot.glossary, fingerprint: fingerprint,
                    ocrMilliseconds: took, explicitlyRequested: forced,
                    layout: geometry.layout)
            }
        }
    }

    private func recognizeFullScreen(_ buffer: CVPixelBuffer,
                                     using snapshot: Snapshot,
                                     geometry: GameCaptureGeometry) -> [GameMenuBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.006
        request.usesLanguageCorrection = true
        request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        do {
            try GameLanguageSupport.setup(request, language: snapshot.language)
            if snapshot.language == "ja" {
                request.customWords = GameRPGDictionary.terms
                    .filter { $0.category == "勇者斗恶龙专用" }
                    .map(\.japanese)
            }
            try VNImageRequestHandler(cvPixelBuffer: buffer,
                                     orientation: geometry.imageOrientation,
                                     options: [:]).perform([request])
            let found = (request.results ?? []).compactMap {
                observation -> (String, CGRect, Double)? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.28 else { return nil }
                let rect = observation.boundingBox
                if let excluded = snapshot.excluded,
                   excluded.contains(CGPoint(x: rect.midX, y: rect.midY)) {
                    return nil
                }
                let raw = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                return (raw, rect, Double(candidate.confidence))
            }
            // Position is preserved for the complete menu list and for future
            // screenshot overlays. Do not clip this list to the first N lines.
            let sorted = found.sorted { a, b in
                abs(a.1.midY - b.1.midY) < 0.025
                    ? a.1.minX < b.1.minX : a.1.midY > b.1.midY
            }
            return sorted.enumerated().map { offset, item in
                GameMenuBlock(id: "\(offset)-\(Int(item.1.minX * 1000))-\(Int(item.1.midY * 1000))",
                              original: item.0, chinese: nil,
                              x: Double(item.1.minX), y: Double(item.1.minY),
                              width: Double(item.1.width), height: Double(item.1.height),
                              confidence: item.2)
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = "全屏 OCR：" + error.localizedDescription
                self.failures += 1
            }
            return []
        }
    }

    // Cheap frame-change detector; supports packed and planar CVPixelBuffers.
    // It intentionally samples only a few bytes and does not retain the frame.
    private func frameFingerprint(_ buffer: CVPixelBuffer, region: CGRect) -> UInt64 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferGetPlaneCount(buffer) > 0
        let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
                          : CVPixelBufferGetBaseAddress(buffer)
        guard let base else { return 0 }
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                              : CVPixelBufferGetBytesPerRow(buffer)
        let rows = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0)
                          : CVPixelBufferGetHeight(buffer)
        guard rowBytes > 0, rows > 0 else { return 0 }

        // Increase coverage across the selected dialogue region: a sparse
        // full-screen grid can miss a small glyph change and delay subtitles.
        let top = max(0, min(rows - 1,
                            Int((1 - region.maxY) * CGFloat(rows))))
        let bottom = max(top + 1, min(rows,
                                    Int((1 - region.minY) * CGFloat(rows))))
        let left = max(0, min(rowBytes - 1, Int(region.minX * CGFloat(rowBytes))))
        let right = max(left + 1, min(rowBytes,
                                     Int(region.maxX * CGFloat(rowBytes))))
        let yStep = max(1, (bottom - top) / 70)
        let xStep = max(1, (right - left) / 110)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 14695981039346656037
        for y in Swift.stride(from: top, to: bottom, by: yStep) {
            for x in Swift.stride(from: left, to: right, by: xStep) {
                hash = (hash ^ UInt64(bytes[y * rowBytes + x])) &* 1099511628211
            }
        }
        return hash
    }

    private func recognize(_ buffer: CVPixelBuffer, using snapshot: Snapshot,
                           geometry: GameCaptureGeometry, region: CGRect) -> Recognition {
        func pass(_ level: VNRequestTextRecognitionLevel) -> Recognition {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012
            request.regionOfInterest = region
            do {
                try GameLanguageSupport.setup(request, language: snapshot.language)
                try VNImageRequestHandler(cvPixelBuffer: buffer,
                                          orientation: geometry.imageOrientation,
                                          options: [:])
                    .perform([request])
                let candidates = (request.results ?? []).compactMap {
                    item -> (String, CGFloat, CGFloat, Float)? in
                    guard let candidate = item.topCandidates(1).first,
                          candidate.confidence >= 0.34,
                          !(snapshot.excluded.map { excluded in
                              excluded.contains(CGPoint(x: item.boundingBox.midX,
                                                        y: item.boundingBox.midY))
                          } ?? false) else {
                        return nil
                    }
                    let content = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return content.isEmpty ? nil :
                        (content, item.boundingBox.midY, item.boundingBox.minX, candidate.confidence)
                }
                let sorted = candidates.sorted { a, b in
                    abs(a.1 - b.1) < 0.025 ? a.2 < b.2 : a.1 > b.1
                }
                let lines = sorted.prefix(4) // Low-latency PiP only; menu OCR keeps ALL blocks.
                let merged = lines.map(\.0).joined(separator: "\n")
                let confidence = lines.isEmpty ? 0 : lines.map { Double($0.3) }
                    .reduce(0, +) / Double(lines.count)
                return Recognition(text: merged, confidence: confidence, lineCount: sorted.count)
            } catch {
                DispatchQueue.main.async {
                    self.phase = "文字识别失败"
                    self.details = error.localizedDescription
                    self.lastError = error.localizedDescription
                    self.failures += 1
                }
                return Recognition(text: "", confidence: 0, lineCount: 0)
            }
        }
        let first = pass(.fast)
        // Two-stage OCR: scan cheaply first; refine *only* when characters exist.
        if snapshot.performance == .balanced,
           !first.text.isEmpty && first.confidence < 0.60 {
            let second = pass(.accurate)
            return second.text.isEmpty ? first : second
        }
        return first
    }

    @MainActor
    private func submit(_ text: String, profile: Snapshot, detectedAt: TimeInterval) {
        let now = Date().timeIntervalSince1970
        if text == lastCompleted { return }
        if text == latestSubmitted && now - latestSubmittedAt < Double(2 + retries * 2) {
            return
        }
        latestSubmitted = text
        latestSubmittedAt = now
        translationRevision += 1
        let revision = translationRevision
        pendingTranslation?.cancel()
        phase = "翻译中"
        details = "已识别 \(text.count) 个字符 · 置信度 \(Int(ocrConfidence * 100))%"
        pendingTranslation = Task { @MainActor [weak self] in
            await self?.translate(text, profile: profile, revision: revision,
                                  detectedAt: detectedAt)
        }
    }

    @MainActor
    private func translate(_ text: String, profile: Snapshot,
                           revision: Int, detectedAt: TimeInterval) async {
        let started = CFAbsoluteTimeGetCurrent()
        let key = profile.provider.rawValue + "|" + profile.name + "|" + profile.language + "|" + text
        do {
            let result: String
            if let exact = profile.glossary[text] {
                result = exact
            } else if let cached = translationCache[key] {
                result = cached
            } else {
                // Sending text to online providers is opt-in; the persisted
                // provider defaults to offline and has no automatic failover.
                result = try await GameOnlineTranslator.shared.translate(
                    text, source: profile.language,
                    provider: profile.provider, endpoint: profile.endpoint)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard revision == translationRevision && !Task.isCancelled else { return }
            guard !result.isEmpty else {
                phase = "空译文"
                details = "系统没有返回翻译内容"
                failures += 1
                retries = min(retries + 1, 3)
                return
            }
            translationCache[key] = result
            if translationCache.count > 160 { translationCache.removeAll(keepingCapacity: true) }
            retries = 0
            lastCompleted = text
            original = text
            latest = result
            translatedCount += 1
            translationElapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            phase = "双语字幕已更新"
            details = "识别 \(ocrElapsedMs)ms · 翻译 \(translationElapsedMs)ms"
            let entry = GameSubtitleLine(original: text, translated: result,
                                         game: profile.name, timestamp: Date(),
                                         elapsedMs: Int((Date().timeIntervalSince1970 - detectedAt) * 1000))
            latestLine = entry
            GameLingoStore.shared.add(entry)
        } catch {
            guard revision == translationRevision && !Task.isCancelled else { return }
            retries = min(retries + 1, 3)
            phase = profile.provider == .offline ? "本机翻译失败" : "在线翻译失败"
            details = error.localizedDescription
            lastError = error.localizedDescription
            failures += 1
            // Do not change lastCompleted, so the next stable OCR may retry.
        }
    }

    func heartbeat() {
        guard isCapturing, let stamp = lastFrameAt else { return }
        if Date().timeIntervalSince(stamp) > 9 {
            phase = "没有新的屏幕帧"
            details = "采集可能被系统暂停；返回 App 检查授权与 PiP 状态"
        }
    }

    @MainActor
    var diagnostics: String {
        let stamp = lastFrameAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
        return """
        GameLingo Direct Diagnostics (no screenshot contents)
        Game: \(GameLingoStore.shared.activeProfile.name)
        Mode: \(GameLingoStore.shared.performance.title)
        Phase: \(phase)
        Details: \(details)
        Capturing: \(isCapturing)
        Last frame: \(stamp)
        OCR scans: \(scans) / reused frames: \(ignoredFrames)
        Translations: \(translatedCount)
        OCR: \(ocrElapsedMs)ms, confidence: \(Int(ocrConfidence * 100))%
        Translation: \(translationElapsedMs)ms
        Screen: \(screenDimensions) / \(detectedLayout.title)
        Rotation setting: \(activeRotation.title)
        Errors: \(failures) / last: \(lastError)
        """
    }
}

@available(iOS 27.0, *)
struct DirectCapturePanel: View {
    @ObservedObject private var capture = DirectGameCapture.shared
    let profile: GameProfile
    let performance: GamePerformance

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("iOS 27 · 本机屏幕捕获", systemImage: "display")
                .font(.headline).foregroundStyle(.mint)
            HStack {
                Text(capture.phase).font(.subheadline.bold())
                Spacer()
                Circle().fill(capture.isCapturing ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
            }
            Text(capture.details).font(.caption).foregroundStyle(.secondary)
            Label("画面：\(capture.detectedLayout.title) · \(capture.screenDimensions)",
                  systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.caption).foregroundStyle(.mint)
            Text("方向校正：\(capture.activeRotation.title)")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                item("\(capture.scans)", "OCR")
                item("\(capture.translatedCount)", "翻译")
                item("\(capture.ocrElapsedMs)ms", "识别耗时")
            }
            Button(capture.isCapturing ? "结束采集" : "授权捕获整个屏幕") {
                if capture.isCapturing { capture.stop() } else { capture.start() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
        }
        .onAppear { capture.configure(profile: profile, performance: performance) }
        .onChange(of: profile) { _, updated in
            capture.configure(profile: updated, performance: performance)
        }
        .onChange(of: performance) { _, updated in
            capture.configure(profile: profile, performance: updated)
        }
    }

    private func item(_ value: String, _ label: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value).font(.caption.bold().monospacedDigit())
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
