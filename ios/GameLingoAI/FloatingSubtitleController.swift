import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import CoreImage
import QuartzCore
import SwiftUI
import UIKit

/// Experimental single-iPhone subtitles, rendered as video frames in a system PiP window.
/// PiP is NOT a general cross-app overlay and App Review approval is not guaranteed.
final class FloatingSubtitleController: NSObject, ObservableObject,
                                       AVPictureInPictureControllerDelegate,
                                       AVPictureInPictureSampleBufferPlaybackDelegate {
    @Published private(set) var isActive = false
    @Published private(set) var isPreparing = false
    @Published private(set) var launchFailed = false
    @Published private(set) var status = "悬浮字幕未启动"
    @Published private(set) var outputFrameCount = 0
    @Published private(set) var playbackPage = "1 / 1"
    @Published private(set) var isPlaybackPaused = false
    @Published private(set) var renderElapsedMs = 0
    @Published private(set) var captureToPiPMs = 0
    @Published private(set) var backpressureCount = 0
    @Published private(set) var p50CaptureToPiPMs = 0
    @Published private(set) var p95CaptureToPiPMs = 0

    let previewLayer = AVSampleBufferDisplayLayer()
    private var pictureInPicture: AVPictureInPictureController?
    private var frameTimer: Timer?
    private var menuRefreshTimer: Timer?
    private var playbackInterval: TimeInterval = 5.0
    private var autoplay = true
    private var readAloud = false
    private var speechLanguage = "en"
    private let speaker = AVSpeechSynthesizer()
    private struct SubtitlePage {
        let original: String
        let translated: String
        var x: Double? = nil
        var y: Double? = nil
    }
    private var currentOriginal = "おかえりなさい。"
    private var currentText = "欢迎回来。"
    private var pages = [SubtitlePage(original: "おかえりなさい。", translated: "欢迎回来。")]
    private var recentPairs = [SubtitlePage(original: "おかえりなさい。", translated: "欢迎回来。")]
    private var menuPairs: [SubtitlePage] = []
    private var renderSize = CMVideoDimensions(width: 640, height: 360)
    private var pageGroups: [[SubtitlePage]] = []
    private var lastDrawAt: CFTimeInterval = 0
    private let frameRenderer = GamePiPFrameRenderer()
    private var renderGeneration = 0
    private var pendingSample: CMSampleBuffer?
    private var readinessSubscribed = false
    private var startAfterFirstFrame = false
    private var pendingStartChecks = 0
    private var piPStartupRetryCycles = 0
    private var pipStartRequestedAt: CFTimeInterval = 0
    private var lastCaptureTime: TimeInterval = 0
    private var lastMeasuredCaptureTime: TimeInterval = 0
    private var latencySamples: [(Date, Int)] = []
    // The requested default is bilingual: game original above, Chinese below.
    private var subtitleMode = "bilingual"
    private var layoutMode = "standard"
    private var pageIndex = 0
    private var pageChangedAt = CACurrentMediaTime()
    private var fontScale: CGFloat = 1

    override init() {
        super.init()
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = UIColor.black.cgColor
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            status = "此设备不支持系统画中画"
            return
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: previewLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPicture = controller
    }

    func attachPreview(to view: UIView) {
        let newParent = previewLayer.superlayer !== view.layer
        if newParent {
            previewLayer.removeFromSuperlayer()
            view.layer.addSublayer(previewLayer)
        }
        previewLayer.frame = view.bounds
        // SwiftUI can call updateUIView repeatedly while OCR status changes.
        // Do not redraw the PiP video for every unrelated view update.
        if newParent { renderFrame() }
    }

    func resizePreview(to bounds: CGRect) {
        previewLayer.frame = bounds
    }

    // Backward-compatible entry point for the older ReplayKit workflow.
    func setText(_ text: String) {
        setBilingual(original: "", translated: text)
    }

    func setBilingual(original: String, translated: String,
                      capturedAt: TimeInterval? = nil) {
        let nextOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nextOriginal != currentOriginal || nextTranslated != currentText else { return }
        currentOriginal = nextOriginal
        currentText = nextTranslated.isEmpty ? "等待中文字幕…" : nextTranslated
        if let capturedAt { lastCaptureTime = capturedAt }
        let sourceLines = currentOriginal.split(separator: "\n").map(String.init)
        let targetLines = currentText.split(separator: "\n").map(String.init)
        if sourceLines.count > 1 && sourceLines.count == targetLines.count {
            for (source, target) in zip(sourceLines, targetLines) {
                recentPairs.append(SubtitlePage(original: source, translated: target))
            }
        } else {
            recentPairs.append(SubtitlePage(original: currentOriginal, translated: currentText))
        }
        if recentPairs.count > 24 { recentPairs.removeFirst(recentPairs.count - 24) }
        // Live subtitles must be visible as soon as they're translated.
        // Older pages remain in recentPairs, but no longer hide new dialogue.
        rebuildPages(preservePage: layoutMode == "menuPages")
    }

    func setMode(_ mode: String, layout: String) {
        let newMode = ["bilingual", "chinese", "original"].contains(mode) ? mode : "bilingual"
        let layouts = ["compact", "standard", "learning", "multiBilingual",
                       "denseChinese", "menuPages", "fullBilingual",
                       "fullChinese", "spatialMenu"]
        let newLayout = layouts.contains(layout) ? layout : "standard"
        guard subtitleMode != newMode || layoutMode != newLayout else { return }
        subtitleMode = newMode
        layoutMode = newLayout
        rebuildPages()
    }

    #if DIRECT_CAPTURE
    func setStructuredMenuEntries(_ blocks: [GameMenuBlock]) {
        let next = blocks.map {
            SubtitlePage(original: $0.original, translated: $0.chinese ?? "翻译中…",
                         x: $0.x, y: $0.y)
        }
        guard menuPairs.count != next.count ||
              zip(menuPairs, next).contains(where: {
                  $0.0.original != $0.1.original ||
                  $0.0.translated != $0.1.translated ||
                  $0.0.x != $0.1.x || $0.0.y != $0.1.y
              }) else { return }
        menuPairs = next
        if layoutMode == "menuPages" || layoutMode == "spatialMenu" {
            menuRefreshTimer?.invalidate()
            menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3,
                                                    repeats: false) { [weak self] _ in
                self?.rebuildPages(preservePage: true)
            }
        }
    }

    #endif

    func setMenuEntries(_ entries: [(String, String)]) {
        let next = entries.map {
            SubtitlePage(original: $0.0, translated: $0.1)
        }
        guard menuPairs.count != next.count ||
              zip(menuPairs, next).contains(where: { pair in
                  pair.0.original != pair.1.original ||
                  pair.0.translated != pair.1.translated
              }) else { return }
        menuPairs = next
        if layoutMode == "menuPages" {
            // Menu batch translations can deliver many results in a burst.
            // Coalesce updates instead of rebuilding a 640x360 frame per item.
            menuRefreshTimer?.invalidate()
            menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3,
                                                    repeats: false) { [weak self] _ in
                self?.rebuildPages(preservePage: true)
            }
        }
    }

    func setSpeechLanguage(_ language: String) {
        speechLanguage = GameTranslationLanguages.apiCode(language)
    }

    func primePreview() {
        // Called once the SwiftUI inline preview has been attached. A
        // primed sample-buffer makes the first PiP request less fragile.
        renderFrame()
    }

    func configurePlayback(autoplay: Bool, seconds: Double, readAloud: Bool) {
        let next = min(10.0, max(2.0, seconds))
        guard self.autoplay != autoplay || playbackInterval != next ||
              self.readAloud != readAloud else { return }
        self.autoplay = autoplay
        playbackInterval = next
        self.readAloud = readAloud
        if !readAloud { speaker.stopSpeaking(at: .immediate) }
        isPlaybackPaused = !autoplay
        pageChangedAt = CACurrentMediaTime()
    }

    func togglePlayback() {
        // The transport control can resume playback even if the saved
        // autoplay preference was off.
        if !autoplay { autoplay = true }
        isPlaybackPaused.toggle()
        pageChangedAt = CACurrentMediaTime()
    }

    func nextPage() { changePage(by: 1) }
    func previousPage() { changePage(by: -1) }

    private func changePage(by distance: Int) {
        guard pageCount > 0 else { return }
        pageIndex = (pageIndex + distance + pageCount) % pageCount
        pageChangedAt = CACurrentMediaTime()
        playbackPage = "\(pageIndex + 1) / \(pageCount)"
        renderFrame()
        speakCurrentPage()
    }

    private func speakCurrentPage() {
        guard readAloud, isActive, !pages.isEmpty else { return }
        let entries = isGroupedLayout && pageGroups.indices.contains(pageIndex)
            ? pageGroups[pageIndex] : [pages[pages.indices.contains(pageIndex) ? pageIndex : 0]]
        let message = entries.map { $0.translated }.joined(separator: "。")
        guard !message.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLanguage)
        utterance.rate = 0.48
        speaker.speak(utterance)
    }

    func setFontScale(_ scale: CGFloat) {
        let next = min(1.4, max(0.8, scale))
        guard abs(next - fontScale) > 0.001 else { return }
        fontScale = next
        rebuildPages()
    }

    private var pageCount: Int {
        isGroupedLayout ? max(1, pageGroups.count) : max(1, pages.count)
    }
    private var isGroupedLayout: Bool {
        ["multiBilingual", "denseChinese", "menuPages",
         "fullBilingual", "fullChinese", "spatialMenu"].contains(layoutMode)
    }
    private func rebuildPages(preservePage: Bool = false) {
        let previousPage = pageIndex
        pages = makeBilingualPages()
        if layoutMode == "menuPages" || layoutMode == "spatialMenu" {
            let menu = menuPairs.isEmpty ? Array(recentPairs.suffix(1)) : menuPairs
            pageGroups = chunk(menu, count: layoutMode == "spatialMenu" ? 5 : 4)
        } else if layoutMode == "fullBilingual" || layoutMode == "fullChinese" {
            // Fit groups to the actual PiP playback size, not a fixed
            // 640x360/characters-per-page assumption.
            let narrow = renderSize.width < 460 || renderSize.height < 265
            let chineseOnly = layoutMode == "fullChinese"
            let characters = narrow ? (chineseOnly ? 60 : 44) :
                (chineseOnly ? 110 : 65)
            let pairs = Array(recentPairs.suffix(12)).flatMap {
                GamePiPReadingLayout.paginate(
                    original: $0.original, translated: $0.translated,
                    originalLimit: characters,
                    translatedLimit: characters)
            }
            let groups = GamePiPReadingLayout.group(
                pairs, maxPairs: narrow ? 1 : (chineseOnly ? 3 : 2),
                maxCharacters: narrow ? characters : (chineseOnly ? 195 : 115))
            pageGroups = groups.map { group in
                group.map { SubtitlePage(original: $0.original, translated: $0.translated) }
            }
        } else if layoutMode == "denseChinese" {
            pageGroups = chunk(Array(recentPairs.suffix(20)), count: 5)
        } else if layoutMode == "multiBilingual" {
            pageGroups = chunk(Array(recentPairs.suffix(9)), count: 3)
        } else {
            pageGroups = []
        }
        // Newest dialogue groups first; the saved menu starts on page 1.
        let startingPage = (layoutMode == "menuPages" || layoutMode == "spatialMenu") ? 0 :
            (isGroupedLayout ? max(0, pageGroups.count - 1) : 0)
        pageIndex = preservePage ? min(previousPage, pageCount - 1) : startingPage
        playbackPage = "\(pageIndex + 1) / \(pageCount)"
        // Keep the page's remaining reading time when new OCR arrives.
        if !preservePage { pageChangedAt = CACurrentMediaTime() }
        renderFrame()
        if !preservePage { speakCurrentPage() }
    }

    private func chunk(_ source: [SubtitlePage], count: Int) -> [[SubtitlePage]] {
        guard !source.isEmpty else {
            return [[SubtitlePage(original: currentOriginal, translated: currentText)]]
        }
        return stride(from: 0, to: source.count, by: count).map {
            Array(source[$0..<min(source.count, $0 + count)])
        }
    }

    func start() {
        guard let pip = pictureInPicture else {
            isPreparing = false
            launchFailed = true
            status = "系统画中画不可用"
            return
        }
        do {
            // Keep the game's audio audible. This is for the PiP video session, not audio capture.
            try AVAudioSession.sharedInstance().setCategory(.playback,
                                                            mode: .default,
                                                            options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            isPreparing = false
            launchFailed = true
            status = "画中画音频会话初始化失败：\(error.localizedDescription)"
            return
        }

        if previewLayer.status == .failed { previewLayer.flushAndRemoveImage() }
        if pip.isPictureInPictureActive {
            isPreparing = false
            launchFailed = false
            status = "悬浮字幕正在显示"
            return
        }
        // Rendering now runs off-main. Wait for its first enqueued sample
        // before checking isPictureInPicturePossible; the old synchronous
        // primer is no longer valid.
        isPreparing = true
        launchFailed = false
        startAfterFirstFrame = true
        pendingStartChecks = 0
        piPStartupRetryCycles = 0
        pipStartRequestedAt = CACurrentMediaTime()
        status = "正在准备首帧字幕…"
        renderFrame()
    }

    func stop() {
        isPreparing = false
        launchFailed = false
        startAfterFirstFrame = false
        pendingStartChecks = 0
        previewLayer.sampleBufferRenderer.stopRequestingMediaData()
        readinessSubscribed = false
        pendingSample = nil
        renderGeneration += 1
        pictureInPicture?.stopPictureInPicture()
        frameTimer?.invalidate()
        frameTimer = nil
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    private func beginFrameTimer() {
        frameTimer?.invalidate()
        // Render on content/page changes, with only a rare heartbeat to keep
        // the system's sample-buffer PiP layer alive. No 0.8-second full render.
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if self.autoplay && !self.isPlaybackPaused &&
               self.pageCount > 1 && now - self.pageChangedAt >= self.playbackInterval {
                self.changePage(by: 1)
            } else if now - self.lastDrawAt >= 3.0 {
                self.renderFrame()
            }
        }
        frameTimer?.tolerance = 0.2
    }

    // Keep the two languages in a single frame. For longer lines, display
    // consecutive paired portions rather than silently clipping the bottom.
    private func makeBilingualPages() -> [SubtitlePage] {
        GamePiPReadingLayout.paginate(
            original: currentOriginal, translated: currentText
        ).map { SubtitlePage(original: $0.original, translated: $0.translated) }
    }

    // Only collect cheap, immutable text state on the UI thread.
    // CoreText layout and CVPixelBuffer creation occur on a serial worker.
    private func renderFrame() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.renderFrame() }
            return
        }
        renderGeneration += 1
        let count = max(1, pageCount)
        let selected: [GamePiPFrameRenderer.Pair]
        if isGroupedLayout && pageGroups.indices.contains(pageIndex) {
            selected = pageGroups[pageIndex].map {
                GamePiPFrameRenderer.Pair(original: $0.original,
                                          translated: $0.translated, x: $0.x, y: $0.y)
            }
        } else {
            let item = pages.indices.contains(pageIndex)
                ? pages[pageIndex]
                : SubtitlePage(original: currentOriginal, translated: currentText)
            selected = [GamePiPFrameRenderer.Pair(original: item.original,
                                                  translated: item.translated)]
        }
        let next = GamePiPFrameRenderer.Frame(
            generation: renderGeneration, entries: selected,
            layout: layoutMode, mode: subtitleMode, fontScale: fontScale,
            pageIndex: pageIndex, pageCount: count,
            renderWidth: Int(renderSize.width), renderHeight: Int(renderSize.height))
        frameRenderer.render(next) { [weak self] generation, buffer, elapsed in
            guard let self, generation == self.renderGeneration else { return }
            self.renderElapsedMs = Int(elapsed.rounded())
            guard let buffer else {
                self.isPreparing = false
                self.launchFailed = true
                self.startAfterFirstFrame = false
                self.status = "PiP 字幕视频帧生成失败，请重新尝试"
                return
            }
            self.pendingSample = buffer // latest frame replaces any stalled frame
            self.flushPendingFrame()
        }
    }

    private func flushPendingFrame() {
        guard let buffer = pendingSample else { return }
        let renderer = previewLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        if renderer.isReadyForMoreMediaData {
            pendingSample = nil
            renderer.enqueue(buffer)
            lastDrawAt = CACurrentMediaTime()
            outputFrameCount += 1
            if startAfterFirstFrame { tryStartPiPAfterFrame() }
            if lastCaptureTime > lastMeasuredCaptureTime {
                lastMeasuredCaptureTime = lastCaptureTime
                captureToPiPMs = max(0, Int(
                    (Date().timeIntervalSince1970 - lastCaptureTime) * 1000))
                let stamp = Date()
                latencySamples.append((stamp, captureToPiPMs))
                latencySamples.removeAll {
                    stamp.timeIntervalSince($0.0) > 60
                }
                let sorted = latencySamples.map(\.1).sorted()
                if !sorted.isEmpty {
                    p50CaptureToPiPMs = sorted[(sorted.count - 1) / 2]
                    p95CaptureToPiPMs = sorted[Int(
                        Double(sorted.count - 1) * 0.95)]
                }
            }
            if readinessSubscribed {
                renderer.stopRequestingMediaData()
                readinessSubscribed = false
            }
        } else if !readinessSubscribed {
            backpressureCount += 1
            readinessSubscribed = true
            // No busy polling; the renderer invokes this when it can accept
            // the latest sample. Never enqueue an unbounded video queue.
            renderer.requestMediaDataWhenReady(on: DispatchQueue.main) { [weak self] in
                guard let self else { return }
                self.flushPendingFrame()
            }
        }
    }

    private func tryStartPiPAfterFrame() {
        guard startAfterFirstFrame, let pip = pictureInPicture else { return }
        if pip.isPictureInPictureActive {
            startAfterFirstFrame = false
            return
        }
        if pip.isPictureInPicturePossible {
            startAfterFirstFrame = false
            pip.startPictureInPicture()
            return
        }
        pendingStartChecks += 1
        guard pendingStartChecks <= 12 else {
            if piPStartupRetryCycles < 1 {
                piPStartupRetryCycles += 1
                pendingStartChecks = 0
                status = "PiP 首次未就绪 · 自动重试一次"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.startAfterFirstFrame else { return }
                    self.renderFrame()
                }
                return
            }
            startAfterFirstFrame = false
            isPreparing = false
            launchFailed = true
            status = "PiP 首帧就绪，但系统不允许开启；请重试或跳过悬浮窗"
            #if DIRECT_CAPTURE
            GameDiagnosticLog.shared.event("pip_startup", metrics: [
                "pip_result": 2,
                "pip_start_ms": max(0, Int((CACurrentMediaTime() - pipStartRequestedAt) * 1000))
            ])
            #endif
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.tryStartPiPAfterFrame()
        }
    }

    // MARK: PiP controller callbacks
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        status = "正在开启同屏字幕…"
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        isPreparing = false
        launchFailed = false
        status = "同屏字幕运行中：现在可以切换回游戏"
        #if DIRECT_CAPTURE
        GameDiagnosticLog.shared.event("pip_startup", metrics: [
            "pip_result": 1,
            "pip_start_ms": max(0, Int((CACurrentMediaTime() - pipStartRequestedAt) * 1000))
        ])
        #endif
        renderFrame()
        beginFrameTimer()
        speakCurrentPage()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        startAfterFirstFrame = false
        isActive = false
        isPreparing = false
        launchFailed = true
        status = "画中画启动失败：\(error.localizedDescription)"
        #if DIRECT_CAPTURE
        GameDiagnosticLog.shared.event("pip_startup", metrics: [
            "pip_result": 3,
            "pip_start_ms": max(0, Int((CACurrentMediaTime() - pipStartRequestedAt) * 1000))
        ])
        #endif
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        startAfterFirstFrame = false
        isActive = false
        isPreparing = false
        status = "悬浮窗已关闭，翻译请返回 App 查看"
        frameTimer?.invalidate()
        frameTimer = nil
        previewLayer.sampleBufferRenderer.stopRequestingMediaData()
        readinessSubscribed = false
        pendingSample = nil
        renderGeneration += 1
    }

    // MARK: Live sample-buffer PiP playback
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
        if playing { renderFrame() }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        guard newRenderSize.width > 0, newRenderSize.height > 0 else { return }
        renderSize = newRenderSize
        rebuildPages(preservePage: true)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion: @escaping () -> Void) {
        completion()
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        true
    }
}

struct FloatingSubtitlePreview: UIViewRepresentable {
    let controller: FloatingSubtitleController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attachPreview(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        controller.attachPreview(to: view)
        DispatchQueue.main.async { controller.resizePreview(to: view.bounds) }
    }
}
