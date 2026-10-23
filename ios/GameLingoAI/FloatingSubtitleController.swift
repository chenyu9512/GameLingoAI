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
    @Published private(set) var status = "悬浮字幕未启动"
    @Published private(set) var outputFrameCount = 0

    let previewLayer = AVSampleBufferDisplayLayer()
    private var pictureInPicture: AVPictureInPictureController?
    private var frameTimer: Timer?
    private struct SubtitlePage {
        let original: String
        let translated: String
    }
    private var currentOriginal = "おかえりなさい。"
    private var currentText = "欢迎回来。"
    private var pages = [SubtitlePage(original: "おかえりなさい。", translated: "欢迎回来。")]
    private var recentPairs = [SubtitlePage(original: "おかえりなさい。", translated: "欢迎回来。")]
    private var menuPairs: [SubtitlePage] = []
    private var pageGroups: [[SubtitlePage]] = []
    private var lastDrawAt: CFTimeInterval = 0
    // The requested default is bilingual: game original above, Chinese below.
    private var subtitleMode = "bilingual"
    private var layoutMode = "standard"
    private var pageIndex = 0
    private var pageChangedAt = CACurrentMediaTime()
    private var fontScale: CGFloat = 1
    private var lastFrameTime: Double = 0
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    // This is the actual encoded video size. UIKit MUST render at scale 1.
    private let frameSize = CGSize(width: 640, height: 360)

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
        if previewLayer.superlayer !== view.layer {
            previewLayer.removeFromSuperlayer()
            view.layer.addSublayer(previewLayer)
        }
        previewLayer.frame = view.bounds
        renderFrame()
    }

    func resizePreview(to bounds: CGRect) {
        previewLayer.frame = bounds
    }

    // Backward-compatible entry point for the older ReplayKit workflow.
    func setText(_ text: String) {
        setBilingual(original: "", translated: text)
    }

    func setBilingual(original: String, translated: String) {
        let nextOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nextOriginal != currentOriginal || nextTranslated != currentText else { return }
        currentOriginal = nextOriginal
        currentText = nextTranslated.isEmpty ? "等待中文字幕…" : nextTranslated
        recentPairs.append(SubtitlePage(original: currentOriginal, translated: currentText))
        if recentPairs.count > 24 { recentPairs.removeFirst(recentPairs.count - 24) }
        rebuildPages()
    }

    func setMode(_ mode: String, layout: String) {
        let newMode = ["bilingual", "chinese", "original"].contains(mode) ? mode : "bilingual"
        let layouts = ["compact", "standard", "learning", "multiBilingual",
                       "denseChinese", "menuPages"]
        let newLayout = layouts.contains(layout) ? layout : "standard"
        guard subtitleMode != newMode || layoutMode != newLayout else { return }
        subtitleMode = newMode
        layoutMode = newLayout
        rebuildPages()
    }

    func setMenuEntries(_ entries: [(String, String)]) {
        let next = entries.map {
            SubtitlePage(original: $0.0, translated: $0.1)
        }
        guard menuPairs.count != next.count ||
              zip(menuPairs, next).contains(where: {
                  $0.original != $1.original || $0.translated != $1.translated
              }) else { return }
        menuPairs = next
        if layoutMode == "menuPages" { rebuildPages() }
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
        ["multiBilingual", "denseChinese", "menuPages"].contains(layoutMode)
    }
    private func rebuildPages() {
        pages = makeBilingualPages()
        if layoutMode == "menuPages" {
            pageGroups = chunk(menuPairs.isEmpty ? recentPairs.suffix(1).map { $0 } : menuPairs,
                               count: 4)
        } else if layoutMode == "denseChinese" {
            pageGroups = chunk(Array(recentPairs.suffix(20)), count: 5)
        } else if layoutMode == "multiBilingual" {
            pageGroups = chunk(Array(recentPairs.suffix(9)), count: 3)
        } else {
            pageGroups = []
        }
        // Newest group first; old history is still kept in the app.
        pageIndex = isGroupedLayout ? max(0, pageGroups.count - 1) : 0
        pageChangedAt = CACurrentMediaTime()
        renderFrame()
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
            status = "画中画音频会话初始化失败：\(error.localizedDescription)"
            return
        }

        if previewLayer.status == .failed { previewLayer.flushAndRemoveImage() }
        // Prime a real video frame *after* clearing a failed renderer;
        // otherwise PiP may start with an empty / black buffer.
        renderFrame()
        if pip.isPictureInPictureActive {
            status = "悬浮字幕正在显示"
            return
        }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            status = "小窗尚未就绪，请稍后再点一次。请保持预览区域可见。"
        }
    }

    func stop() {
        pictureInPicture?.stopPictureInPicture()
        frameTimer?.invalidate()
        frameTimer = nil
    }

    private func beginFrameTimer() {
        frameTimer?.invalidate()
        // Render on content/page changes, with only a rare heartbeat to keep
        // the system's sample-buffer PiP layer alive. No 0.8-second full render.
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let interval: CFTimeInterval = self.isGroupedLayout ? 5.0 : 3.8
            if self.pageCount > 1 && now - self.pageChangedAt >= interval {
                self.pageIndex = (self.pageIndex + 1) % self.pageCount
                self.pageChangedAt = now
                self.renderFrame()
            } else if now - self.lastDrawAt >= 9.0 {
                self.renderFrame()
            }
        }
        frameTimer?.tolerance = 0.2
    }

    // Keep the two languages in a single frame. For longer lines, display
    // consecutive paired portions rather than silently clipping the bottom.
    private func makeBilingualPages() -> [SubtitlePage] {
        let origCount = layoutMode == "learning" ? 68 : 78
        let chineseCount = layoutMode == "compact" ? 40 : 53
        func split(_ source: String, at limit: Int) -> [String] {
            let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return [""] }
            var result: [String] = []
            var working = ""
            for character in text.prefix(640) {
                working.append(character)
                if working.count >= limit
                    || (working.count > limit / 2
                        && "。！？!?；;。\n".contains(character)) {
                    result.append(working.trimmingCharacters(in: .whitespacesAndNewlines))
                    working = ""
                }
            }
            if !working.isEmpty {
                result.append(working.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return result.isEmpty ? [""] : result
        }

        let sourcePages = split(currentOriginal, at: origCount)
        let targetPages = split(currentText, at: chineseCount)
        let count = max(sourcePages.count, targetPages.count)
        return (0..<max(1, count)).map { index in
            SubtitlePage(original: index < sourcePages.count ? sourcePages[index] : "",
                         translated: index < targetPages.count ? targetPages[index] : "")
        }
    }


    private func renderFrame() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.renderFrame() }
            return
        }
        // UIGraphicsImageRenderer uses the screen's Retina scale by default.
        // That creates 1280x720 / 1920x1080 pixels for a 640x360 canvas,
        // which was clipped when copied into a 640x360 PiP pixel buffer.
        let size = frameSize
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1.0
        rendererFormat.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: rendererFormat).image { context in
            let cg = context.cgContext
            UIColor(red: 0.035, green: 0.055, blue: 0.09, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // The floating window is tiny. Do not waste 20% of its height
            // on the logo/header; give the full central region to captions.
            UIColor(red: 0.24, green: 0.92, blue: 0.78, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: 5))

            let page = pages.indices.contains(pageIndex)
                ? pages[pageIndex]
                : SubtitlePage(original: currentOriginal, translated: currentText)

            let showOriginal = subtitleMode != "chinese" && !page.original.isEmpty
            let showChinese = subtitleMode != "original" && !page.translated.isEmpty
            let inset: CGFloat = 22
            let areaWidth = size.width - inset * 2
            let origArea: CGRect
            let zhArea: CGRect
            if showOriginal && showChinese {
                let divider = layoutMode == "learning" ? CGFloat(171) :
                              (layoutMode == "compact" ? CGFloat(126) : CGFloat(149))
                origArea = CGRect(x: inset, y: 15, width: areaWidth, height: divider - 20)
                zhArea = CGRect(x: inset, y: divider + 5, width: areaWidth,
                                height: size.height - divider - 22)
                UIColor.white.withAlphaComponent(0.12).setFill()
                cg.fill(CGRect(x: 40, y: divider, width: size.width - 80, height: 1))
            } else {
                origArea = CGRect(x: inset, y: 22, width: areaWidth, height: size.height - 44)
                zhArea = origArea
            }

            func drawCentered(_ value: String, in area: CGRect,
                              color: UIColor, maximum: CGFloat, minimum: CGFloat,
                              weight: UIFont.Weight) {
                guard !value.isEmpty else { return }
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                paragraph.lineSpacing = 5

                var selectedFont = UIFont.systemFont(ofSize: minimum, weight: weight)
                var selectedHeight: CGFloat = 0
                for point in Swift.stride(from: maximum, through: minimum, by: -2) {
                    let font = UIFont.systemFont(ofSize: point, weight: weight)
                    let bounds = (value as NSString).boundingRect(
                        with: CGSize(width: area.width,
                                     height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: font, .paragraphStyle: paragraph],
                        context: nil)
                    selectedFont = font
                    selectedHeight = ceil(bounds.height)
                    if selectedHeight <= area.height - 4 { break }
                }
                let textHeight = min(selectedHeight, area.height)
                let textBounds = CGRect(x: area.minX,
                                        y: area.midY - textHeight / 2,
                                        width: area.width, height: textHeight + 2)
                (value as NSString).draw(with: textBounds,
                    options: [.usesLineFragmentOrigin, .usesFontLeading,
                              .truncatesLastVisibleLine],
                    attributes: [.font: selectedFont, .foregroundColor: color,
                                 .paragraphStyle: paragraph],
                    context: nil)
            }

            if isGroupedLayout {
                let group = pageGroups.indices.contains(pageIndex)
                    ? pageGroups[pageIndex]
                    : [SubtitlePage(original: currentOriginal, translated: currentText)]
                let areaTop: CGFloat = 12
                let availableHeight = size.height - 24
                let heightPerRow = availableHeight / CGFloat(max(group.count, 1))
                for (idx, entry) in group.enumerated() {
                    let top = areaTop + CGFloat(idx) * heightPerRow
                    let row = CGRect(x: 16, y: top,
                                     width: size.width - 32, height: heightPerRow)
                    if layoutMode == "denseChinese" {
                        drawCentered(subtitleMode == "original" ? entry.original : entry.translated,
                                     in: row.insetBy(dx: 3, dy: 5), color: .white,
                                     maximum: 36 * fontScale, minimum: 19 * fontScale,
                                     weight: .semibold)
                    } else if subtitleMode == "chinese" || subtitleMode == "original" {
                        let text = subtitleMode == "original" ? entry.original : entry.translated
                        drawCentered(text, in: row.insetBy(dx: 3, dy: 5), color: .white,
                                     maximum: 34 * fontScale, minimum: 17 * fontScale,
                                     weight: .semibold)
                    } else {
                        let originalRegion = CGRect(x: row.minX, y: row.minY + 2,
                            width: row.width, height: row.height * 0.42)
                        let chineseRegion = CGRect(x: row.minX,
                            y: row.minY + row.height * 0.43,
                            width: row.width, height: row.height * 0.55)
                        drawCentered(entry.original, in: originalRegion,
                                     color: UIColor(red: 0.42, green: 0.94,
                                                    blue: 0.85, alpha: 1),
                                     maximum: 29 * fontScale, minimum: 14 * fontScale,
                                     weight: .medium)
                        drawCentered(entry.translated, in: chineseRegion,
                                     color: .white, maximum: 32 * fontScale,
                                     minimum: 17 * fontScale, weight: .semibold)
                    }
                    if idx < group.count - 1 {
                        UIColor.white.withAlphaComponent(0.1).setFill()
                        cg.fill(CGRect(x: 32, y: row.maxY - 1,
                                       width: size.width - 64, height: 1))
                    }
                }
            } else {
            if showOriginal {
                let fontSize: CGFloat = layoutMode == "compact" ? 37 : 44
                drawCentered(page.original, in: origArea,
                             color: UIColor(red: 0.42, green: 0.94, blue: 0.85, alpha: 1),
                             maximum: fontSize * fontScale,
                             minimum: 28 * fontScale, weight: .medium)
            }
            if showChinese {
                let fontSize: CGFloat = layoutMode == "compact" ? 68 :
                                        (layoutMode == "learning" ? 56 : 64)
                drawCentered(page.translated, in: zhArea, color: .white,
                             maximum: fontSize * fontScale,
                             minimum: 38 * fontScale, weight: .bold)
            }
            }
            // Nonverbal progress indicator for subtitles that require pages.
            if pageCount > 1 {
                let progressWidth = size.width / CGFloat(pageCount)
                UIColor(red: 0.24, green: 0.92, blue: 0.78, alpha: 0.85).setFill()
                cg.fill(CGRect(x: CGFloat(pageIndex) * progressWidth,
                               y: size.height - 5,
                               width: progressWidth,
                               height: 5))
            }
        }
        guard let cgImage = image.cgImage,
              cgImage.width == Int(size.width),
              cgImage.height == Int(size.height) else {
            status = "字幕视频帧尺寸错误"
            return
        }

        var pixelBuffer: CVPixelBuffer?
        let properties: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: String]
        ]
        let createStatus = CVPixelBufferCreate(kCFAllocatorDefault, 640, 360,
                                               kCVPixelFormatType_32BGRA,
                                               properties as CFDictionary, &pixelBuffer)
        guard createStatus == kCVReturnSuccess, let buffer = pixelBuffer else { return }
        // Copy the rendered UIKit CGImage into the pixel buffer without an extra
        // CoreGraphics axis transform. The old CGContext flip inverted PiP text.
        let sourceImage = CIImage(cgImage: cgImage)
        ciContext.render(sourceImage, to: buffer,
                         bounds: CGRect(origin: .zero, size: size),
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                            imageBuffer: buffer,
                                                            formatDescriptionOut: &formatDescription) == noErr,
              let format = formatDescription else { return }
        // Use monotonic increasing timestamps when the content has not changed.
        let current = CACurrentMediaTime()
        lastDrawAt = current
        let stamp = max(current, lastFrameTime + 0.01)
        lastFrameTime = stamp
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 1),
                                        presentationTimeStamp: CMTime(seconds: stamp, preferredTimescale: 1000),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: buffer,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sampleBuffer = sample else { return }
        if let attachmentArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary],
           let attachment = attachmentArray.first {
            attachment[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        let sampleRenderer = previewLayer.sampleBufferRenderer
        if sampleRenderer.status == .failed { sampleRenderer.flush() }
        if sampleRenderer.isReadyForMoreMediaData {
            sampleRenderer.enqueue(sampleBuffer)
            outputFrameCount += 1
        }
    }

    // MARK: PiP controller callbacks
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        status = "正在开启同屏字幕…"
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        status = "同屏字幕运行中：现在可以切换回游戏"
        renderFrame()
        beginFrameTimer()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        status = "画中画启动失败：\(error.localizedDescription)"
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        status = "悬浮窗已关闭，翻译请返回 App 查看"
        frameTimer?.invalidate()
        frameTimer = nil
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
        renderFrame()
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
