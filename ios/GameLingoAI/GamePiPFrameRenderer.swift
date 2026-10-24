import Foundation
import CoreGraphics
import CoreText
import CoreVideo
import CoreMedia
import QuartzCore
import CoreImage
import ImageIO

/// Only renders pixels on a serial utility queue. It never touches UIKit,
/// SwiftUI, AVPictureInPictureController, or AVSampleBufferDisplayLayer.
final class GamePiPFrameRenderer: @unchecked Sendable {
    struct Pair {
        let original: String
        let translated: String
        var x: Double? = nil
        var y: Double? = nil
    }

    struct Frame {
        let generation: Int
        let entries: [Pair]
        let layout: String
        let mode: String
        let fontScale: CGFloat
        let pageIndex: Int
        let pageCount: Int
        var renderWidth: Int = 640
        var renderHeight: Int = 360
        var sceneBuffer: CVPixelBuffer? = nil
        var sceneOrientation: CGImagePropertyOrientation = .up
        var sceneEntries: [GamePiPSceneText] = []
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "GameLingo.PiP.CoreText", qos: .userInitiated)
    private lazy var imageContext = CIContext(options: [.useSoftwareRenderer: false])
    private var pending: Frame?
    private var isWorking = false
    private var pool: CVPixelBufferPool?
    private struct TextLayout {
        let lines: [(CTLine, CGFloat)]
        let fontSize: CGFloat
    }
    // Worker-only cache; avoid repeating CoreText line layout on heartbeat
    // frames, repeated RPG prompts and user-controlled page flips.
    private var layoutCache: [String: TextLayout] = [:]
    private var lastStamp = 0.0
    private var width = 640
    private var height = 360
    private let background = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                     components: [0.035, 0.055, 0.09, 1])!
    private let accent = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                 components: [0.42, 0.94, 0.85, 1])!
    private let white = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                components: [1, 1, 1, 1])!

    /// Last-write-wins: new text replaces pending render work. A render already
    /// running may finish, but the consumer rejects stale generations.
    func render(_ frame: Frame, completion: @escaping (Int, CMSampleBuffer?, Double) -> Void) {
        lock.lock()
        pending = frame
        let launch = !isWorking
        if launch { isWorking = true }
        lock.unlock()
        guard launch else { return }
        queue.async { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                guard let next = self.pending else {
                    self.isWorking = false
                    self.lock.unlock()
                    return
                }
                self.pending = nil
                self.lock.unlock()
                let began = CFAbsoluteTimeGetCurrent()
                let sample = self.makeSample(next)
                let ms = (CFAbsoluteTimeGetCurrent() - began) * 1000
                DispatchQueue.main.async {
                    completion(next.generation, sample, ms)
                }
            }
        }
    }

    private func makePool(width newWidth: Int, height newHeight: Int) -> CVPixelBufferPool? {
        if width != newWidth || height != newHeight {
            width = newWidth
            height = newHeight
            pool = nil
            layoutCache.removeAll(keepingCapacity: true)
        }
        if let pool { return pool }
        let settings: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: String]
        ]
        let poolSettings: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3
        ]
        var made: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                      poolSettings as CFDictionary,
                                      settings as CFDictionary, &made) == kCVReturnSuccess
        else { return nil }
        pool = made
        return made
    }

    private func makeSample(_ frame: Frame) -> CMSampleBuffer? {
        let isScene = frame.layout == "portraitScene" || frame.layout == "portraitFocus"
        let requestedWidth = isScene ? GamePiPSceneLayout.portraitWidth :
            min(960, max(320, frame.renderWidth))
        let requestedHeight = isScene ? GamePiPSceneLayout.portraitHeight :
            min(640, max(200, frame.renderHeight))
        guard let pool = makePool(width: requestedWidth, height: requestedHeight) else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
                == kCVReturnSuccess, let buffer else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        let bytes = CVPixelBufferGetBaseAddress(buffer)
        guard let context = CGContext(data: bytes, width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                        | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if isScene {
            renderScene(frame, context: context)
        } else {
        context.setFillColor(accent)
        context.fill(CGRect(x: 0, y: height - 5, width: width, height: 5))
        let entries = frame.entries.isEmpty
            ? [Pair(original: "", translated: "等待翻译…")] : frame.entries
        let count = max(1, entries.count)
        let fullBilingual = frame.layout == "fullBilingual"
        let fullChinese = frame.layout == "fullChinese"
        let spatialMenu = frame.layout == "spatialMenu"
        let usableHeight = CGFloat(height - 18)
        let rowHeight = usableHeight / CGFloat(count)
        if fullBilingual {
            // Two flexible columns fill the whole PiP canvas on wide windows;
            // narrow render sizes switch to vertical bilingual cells.
            let wide = CGFloat(width) / CGFloat(height) >= 1.35
            for (index, entry) in entries.enumerated() {
                let top = 9 + CGFloat(index) * rowHeight
                if wide {
                    let column = CGFloat(width - 48) / 2
                    draw(entry.original, context: context,
                         rect: CGRect(x: 12, y: top, width: column, height: rowHeight - 4),
                         color: accent, maximum: 42 * frame.fontScale,
                         minimum: 13 * frame.fontScale, bold: false)
                    draw(entry.translated, context: context,
                         rect: CGRect(x: column + 36, y: top,
                                      width: column, height: rowHeight - 4),
                         color: white, maximum: 48 * frame.fontScale,
                         minimum: 14 * frame.fontScale, bold: true)
                } else {
                    draw(entry.original, context: context,
                         rect: CGRect(x: 13, y: top, width: CGFloat(width - 26),
                                      height: rowHeight * 0.45),
                         color: accent, maximum: 34 * frame.fontScale,
                         minimum: 13 * frame.fontScale, bold: false)
                    draw(entry.translated, context: context,
                         rect: CGRect(x: 13, y: top + rowHeight * 0.46,
                                      width: CGFloat(width - 26),
                                      height: rowHeight * 0.53 - 3),
                         color: white, maximum: 41 * frame.fontScale,
                         minimum: 14 * frame.fontScale, bold: true)
                }
            }
        } else if fullChinese {
            for (index, entry) in entries.enumerated() {
                draw(entry.translated, context: context,
                     rect: CGRect(x: 13, y: 9 + CGFloat(index) * rowHeight,
                                  width: CGFloat(width - 26), height: rowHeight - 4),
                     color: white, maximum: 48 * frame.fontScale,
                     minimum: 15 * frame.fontScale, bold: true)
            }
        } else if spatialMenu {
            // Coordinates from full-screen OCR influence row placement and
            // indentation; clamped to prevent overlapping rows in tiny PiP.
            var priorTop: CGFloat = -rowHeight
            for (index, entry) in entries.enumerated() {
                let desired = CGFloat(1 - min(1, max(0, entry.y ?? 1 - Double(index + 1) / Double(count + 1))))
                    * CGFloat(height - 22)
                let top = max(priorTop + rowHeight, min(desired, CGFloat(height - 9) - rowHeight))
                priorTop = top
                let indent = CGFloat(min(0.75, max(0, entry.x ?? 0))) * 28
                let sourceWidth = CGFloat(width - 44) * 0.40
                let targetWidth = CGFloat(width - 44) * 0.59
                draw(entry.original, context: context,
                     rect: CGRect(x: 10 + indent, y: top,
                                  width: sourceWidth - indent, height: rowHeight - 3),
                     color: accent, maximum: 28 * frame.fontScale,
                     minimum: 12 * frame.fontScale, bold: false)
                draw(entry.translated, context: context,
                     rect: CGRect(x: 18 + sourceWidth, y: top,
                                  width: targetWidth, height: rowHeight - 3),
                     color: white, maximum: 32 * frame.fontScale,
                     minimum: 13 * frame.fontScale, bold: true)
            }
        } else {
        for (index, entry) in entries.enumerated() {
            let top = 11 + CGFloat(index) * rowHeight
            let left: CGFloat = 19
            let areaWidth = CGFloat(width) - left * 2
            let space: CGFloat = 4
            if frame.mode == "chinese" || frame.layout == "denseChinese" {
                let value = frame.mode == "original" ? entry.original : entry.translated
                draw(value, context: context,
                     rect: CGRect(x: left, y: top, width: areaWidth, height: rowHeight - space),
                     color: white, maximum: 39 * frame.fontScale,
                     minimum: 17 * frame.fontScale, bold: true)
            } else if frame.mode == "original" {
                draw(entry.original, context: context,
                     rect: CGRect(x: left, y: top, width: areaWidth, height: rowHeight - space),
                     color: accent, maximum: 38 * frame.fontScale,
                     minimum: 17 * frame.fontScale, bold: false)
            } else {
                let topArea = CGRect(x: left, y: top, width: areaWidth,
                                     height: rowHeight * 0.43)
                let bottomArea = CGRect(x: left, y: top + rowHeight * 0.44,
                                        width: areaWidth, height: rowHeight * 0.53)
                draw(entry.original, context: context, rect: topArea, color: accent,
                     maximum: (count == 1 ? 45 : 29) * frame.fontScale,
                     minimum: 14 * frame.fontScale, bold: false)
                draw(entry.translated, context: context, rect: bottomArea, color: white,
                     maximum: (count == 1 ? 61 : 34) * frame.fontScale,
                     minimum: 17 * frame.fontScale, bold: true)
            }
        }
        }
        }
        if !isScene && frame.pageCount > 1 {
            let segment = CGFloat(width) / CGFloat(frame.pageCount)
            context.setFillColor(accent)
            context.fill(CGRect(x: CGFloat(frame.pageIndex) * segment,
                                y: 0, width: segment, height: 5))
        }
        context.flush()
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &description) == noErr, let description else { return nil }
        let now = CACurrentMediaTime()
        lastStamp = max(now, lastStamp + 0.001)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: CMTime(seconds: lastStamp, preferredTimescale: 1000),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: description, sampleTiming: &timing,
            sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachment = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachment.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }

    /// The live screen is an in-memory CVPixelBuffer (never written to disk).
    /// Vision boxes share the oriented image's normalized lower-left origin.
    private func renderScene(_ frame: Frame, context: CGContext) {
        guard let source = frame.sceneBuffer else {
            draw("等待屏幕采集画面…", context: context,
                 rect: CGRect(x: 12, y: CGFloat(height) * 0.4,
                              width: CGFloat(width - 24), height: 75),
                 color: white, maximum: 26, minimum: 16, bold: true)
            return
        }
        let image = CIImage(cvPixelBuffer: source).oriented(frame.sceneOrientation)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return }
        let entries = frame.sceneEntries.filter { !$0.translated.isEmpty }
        let crop = GamePiPSceneLayout.viewport(
            sourceWidth: Int(extent.width), sourceHeight: Int(extent.height),
            focus: frame.layout == "portraitFocus", boxes: entries)
        let cropRect = CGRect(x: extent.minX + crop.x * extent.width,
                              y: extent.minY + crop.y * extent.height,
                              width: crop.width * extent.width,
                              height: crop.height * extent.height)
        guard let still = imageContext.createCGImage(image, from: cropRect) else { return }
        let canvas = GamePiPSceneLayout.canvasRect(
            width: Double(width), height: Double(height),
            sourceAspect: Double(cropRect.width / cropRect.height))
        let imageRect = CGRect(x: canvas.x, y: canvas.y,
                               width: canvas.width, height: canvas.height)
        context.draw(still, in: imageRect)
        // Pixel data is the game snapshot only; add translucent translations
        // directly on top of their positions, not detached subtitle rows.
        let shade = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                            components: [0.035, 0.08, 0.12, 0.89])!
        for entry in entries.prefix(14) {
            guard GamePiPSceneLayout.visible(entry, in: crop) else { continue }
            let point = GamePiPSceneLayout.map(entry, sourceCrop: crop, canvas: canvas)
            let x = CGFloat(max(4, min(Double(width - 100), point.x)))
            let bottom = CGFloat(max(5, min(Double(height - 24), point.y)))
            let targetWidth = min(CGFloat(width) - x - 5,
                                  max(110, CGFloat(point.width) + 26))
            // Translation can be longer than OCR text. Allow at least two
            // lines and expand into adjacent safe space.
            let targetHeight = min(CGFloat(height) - 10, max(
                36, min(106, CGFloat(entry.translated.count / 12 + 1) * 22)))
            let y = max(5, min(CGFloat(height) - targetHeight - 5,
                               bottom + CGFloat(point.height) / 2 - targetHeight / 2))
            let rect = CGRect(x: x, y: y, width: targetWidth, height: targetHeight)
            context.setFillColor(shade)
            context.fill(rect)
            // draw() uses a top-origin rectangle for its CoreText layout.
            let textRect = CGRect(x: rect.minX + 5,
                                  y: CGFloat(height) - rect.maxY + 3,
                                  width: rect.width - 10, height: rect.height - 6)
            draw(entry.translated, context: context, rect: textRect,
                 color: white, maximum: 23 * frame.fontScale,
                 minimum: 12 * frame.fontScale, bold: true)
        }
    }

    /// Manual CoreText line wrapping keeps UIKit and UIFont off the worker.
    /// The renderer fits the text to the available rectangle without a
    /// per-frame temporary UIImage or CoreImage conversion.
    private func draw(_ value: String, context: CGContext, rect: CGRect,
                      color: CGColor, maximum: CGFloat, minimum: CGFloat,
                      bold: Bool) {
        guard !value.isEmpty, rect.height > 8 else { return }
        let name = bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
        let lower = max(12, minimum)
        let cacheKey = "\(name)|\(Int(maximum))|\(Int(lower))|" +
                       "\(Int(rect.width))|\(Int(rect.height))|\(value)"
        let layout: TextLayout
        if let hit = layoutCache[cacheKey] {
            layout = hit
        } else {
            var chosen: [(CTLine, CGFloat)] = []
            var chosenSize = lower
            let choices = Swift.stride(from: maximum, through: lower, by: -3)
            for point in choices {
                let font = CTFontCreateWithName(name as CFString, point, nil)
                let attr = NSAttributedString(string: value, attributes: [
                    NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
                    NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color
                ])
                let typesetter = CTTypesetterCreateWithAttributedString(attr)
                var index = 0
                var lines: [(CTLine, CGFloat)] = []
                while index < attr.length && lines.count < 48 {
                    let suggested = CTTypesetterSuggestLineBreak(
                        typesetter, index, Double(max(1, rect.width)))
                    let count = max(1, suggested)
                    let line = CTTypesetterCreateLine(typesetter, CFRangeMake(index, count))
                    let measured = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                    lines.append((line, measured))
                    index += count
                }
                let height = CGFloat(lines.count) * point * 1.16
                chosen = lines
                chosenSize = point
                if height <= rect.height - 4 { break }
            }
            layout = TextLayout(lines: chosen, fontSize: chosenSize)
            if layoutCache.count >= 96 { layoutCache.removeAll(keepingCapacity: true) }
            layoutCache[cacheKey] = layout
        }
        let chosen = layout.lines
        let chosenSize = layout.fontSize
        let lineHeight = chosenSize * 1.16
        let total = CGFloat(chosen.count) * lineHeight
        let firstY = CGFloat(height) - rect.minY -
            max(chosenSize, (rect.height - total) / 2 + chosenSize)
        context.textMatrix = .identity
        for (index, pair) in chosen.enumerated() {
            let baseline = firstY - CGFloat(index) * lineHeight
            if baseline < CGFloat(height) - rect.maxY + 2 { break }
            context.textPosition = CGPoint(
                x: rect.midX - pair.1 / 2, y: baseline)
            CTLineDraw(pair.0, context)
        }
    }
}
