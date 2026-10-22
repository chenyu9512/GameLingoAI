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

    let previewLayer = AVSampleBufferDisplayLayer()
    private var pictureInPicture: AVPictureInPictureController?
    private var frameTimer: Timer?
    private var currentText = "字幕预览  ↑  ABC 123"
    private var lastFrameTime: Double = 0
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

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
        currentText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "等待游戏字幕…" : text
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

        renderFrame()
        if previewLayer.status == .failed { previewLayer.flushAndRemoveImage() }
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
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    private func renderFrame() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.renderFrame() }
            return
        }
        let size = CGSize(width: 640, height: 360)
        let text = currentText
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rectangle = CGRect(origin: .zero, size: size)
            UIColor(red: 0.055, green: 0.075, blue: 0.13, alpha: 1).setFill()
            context.cgContext.fill(rectangle)
            UIColor(red: 0.30, green: 0.93, blue: 0.81, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: size.width, height: 7))
            let header = "GameLingo AI  ·  实时翻译"
            header.draw(in: CGRect(x: 25, y: 19, width: 590, height: 30),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                            .foregroundColor: UIColor(red: 0.30, green: 0.93, blue: 0.81, alpha: 1)
                        ])
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 7
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textBounds = CGRect(x: 25, y: 65, width: 590, height: 267)
            attributed.draw(with: textBounds, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        guard let cgImage = image.cgImage else { return }

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
                         bounds: sourceImage.extent,
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
        if previewLayer.status == .failed { previewLayer.flush() }
        if previewLayer.isReadyForMoreMediaData {
            previewLayer.enqueue(sampleBuffer)
        }
    }

    // MARK: PiP controller callbacks
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        status = "正在开启同屏字幕…"
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        status = "同屏字幕运行中：现在可以切换回游戏"
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
