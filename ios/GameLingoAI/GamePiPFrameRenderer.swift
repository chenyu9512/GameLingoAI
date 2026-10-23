import Foundation
import CoreGraphics
import CoreText
import CoreVideo
import CoreMedia
import QuartzCore

/// Only renders pixels on a serial utility queue. It never touches UIKit,
/// SwiftUI, AVPictureInPictureController, or AVSampleBufferDisplayLayer.
final class GamePiPFrameRenderer: @unchecked Sendable {
    struct Pair {
        let original: String
        let translated: String
    }

    struct Frame {
        let generation: Int
        let entries: [Pair]
        let layout: String
        let mode: String
        let fontScale: CGFloat
        let pageIndex: Int
        let pageCount: Int
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "GameLingo.PiP.CoreText", qos: .userInitiated)
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
    private let width = 640
    private let height = 360
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

    private func makePool() -> CVPixelBufferPool? {
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
        guard let pool = makePool() else { return nil }
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
        context.setFillColor(accent)
        context.fill(CGRect(x: 0, y: height - 5, width: width, height: 5))
        let entries = frame.entries.isEmpty
            ? [Pair(original: "", translated: "等待翻译…")] : frame.entries
        let count = max(1, entries.count)
        let rowHeight = CGFloat(height - 22) / CGFloat(count)
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
        if frame.pageCount > 1 {
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
