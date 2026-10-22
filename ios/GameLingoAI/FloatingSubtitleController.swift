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
    private var currentText = "字幕预览  ↑  ABC 123"
    private var pages = ["字幕预览  ↑  ABC 123"]
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

    func setText(_ text: String) {
        let updated = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "等待游戏字幕…" : text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard updated != currentText else { return }
        currentText = updated
        pages = makePages(for: updated)
        pageIndex = 0
        pageChangedAt = CACurrentMediaTime()
        renderFrame()
    }

    func setFontScale(_ scale: CGFloat) {
        fontScale = min(1.45, max(0.75, scale))
        pages = makePages(for: currentText)
        pageIndex = 0
        pageChangedAt = CACurrentMediaTime()
        renderFrame()
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
        // Feed current subtitle frames so PiP remains visibly up to date.
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.pages.count > 1 && CACurrentMediaTime() - self.pageChangedAt >= 3.2 {
                self.pageIndex = (self.pageIndex + 1) % self.pages.count
                self.pageChangedAt = CACurrentMediaTime()
            }
            self.renderFrame()
        }
        frameTimer?.tolerance = 0.12
    }

    // Paginate long translated dialogue instead of drawing it below the
    // bottom edge of a tiny system PiP window.
    private func makePages(for text: String) -> [String] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 8
        let font = UIFont.systemFont(ofSize: 44 * fontScale, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        var result: [String] = []
        var page = ""
        for character in text.prefix(480) {
            let next = page + String(character)
            let bounds = (next as NSString).boundingRect(
                with: CGSize(width: frameSize.width - 42,
                             height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil)
            if bounds.height > frameSize.height - 43 && !page.isEmpty {
                result.append(page.trimmingCharacters(in: .whitespacesAndNewlines))
                page = String(character)
            } else {
                page = next
            }
        }
        if !page.isEmpty {
            result.append(page.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.filter { !$0.isEmpty }.isEmpty
            ? ["等待游戏字幕…"] : result.filter { !$0.isEmpty }
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

            let displayText = pages.indices.contains(pageIndex)
                ? pages[pageIndex] : currentText
            let area = CGRect(x: 21, y: 15, width: size.width - 42, height: size.height - 30)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 8

            var chosenFont = UIFont.systemFont(ofSize: 44 * fontScale, weight: .bold)
            var lineHeight: CGFloat = 0
            for pointSize in stride(from: 72.0 * Double(fontScale),
                                    through: 44.0 * Double(fontScale), by: -2) {
                let candidate = UIFont.systemFont(ofSize: CGFloat(pointSize), weight: .bold)
                let measure = (displayText as NSString).boundingRect(
                    with: CGSize(width: area.width, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: candidate, .paragraphStyle: paragraph],
                    context: nil)
                chosenFont = candidate
                lineHeight = ceil(measure.height)
                if lineHeight <= area.height - 9 { break }
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: chosenFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let boundedHeight = min(lineHeight, area.height)
            let centered = CGRect(x: area.minX,
                                  y: area.midY - boundedHeight / 2,
                                  width: area.width,
                                  height: boundedHeight + 2)
            (displayText as NSString).draw(with: centered,
                                           options: [.usesLineFragmentOrigin, .usesFontLeading],
                                           attributes: attributes,
                                           context: nil)

            // Nonverbal progress indicator for subtitles that require pages.
            if pages.count > 1 {
                let progressWidth = size.width / CGFloat(pages.count)
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
