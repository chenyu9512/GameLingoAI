import Foundation
import CoreVideo
import CoreImage
import UIKit

#if MLKIT_OCR
import MLKitTextRecognitionCommon
import MLKitTextRecognitionJapanese
import MLKitVision
#endif

/// Optional experimental engine. This file also compiles in the normal Direct
/// build (without CocoaPods), where isAvailable is false and Vision remains the
/// only active OCR. No image bytes or recognized strings are persisted.
enum GameMLKitJapaneseOCR {
    struct Output {
        let text: String
        let raw: String
        let candidates: Int
        let rejected: Int
    }

    static var isAvailable: Bool {
        #if MLKIT_OCR
        return true
        #else
        return false
        #endif
    }

    /// Synchronous call ONLY from GameLingo.latestFrameOCR background queue.
    /// The source frame is cropped before recognition to avoid full-screen
    /// processing and the conversion is kept on the OCR worker.
    static func recognize(_ buffer: CVPixelBuffer,
                          orientation: CGImagePropertyOrientation,
                          normalizedRegion: CGRect) throws -> Output? {
        #if MLKIT_OCR
        precondition(!Thread.isMainThread, "ML Kit synchronous OCR must run off main")
        let oriented = CIImage(cvPixelBuffer: buffer)
            .oriented(forExifOrientation: Int32(orientation.rawValue))
        let extent = oriented.extent
        let roi = normalizedRegion.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !roi.isNull, roi.width > 0, roi.height > 0 else { return nil }
        let crop = CGRect(x: extent.minX + extent.width * roi.minX,
                          y: extent.minY + extent.height * roi.minY,
                          width: extent.width * roi.width,
                          height: extent.height * roi.height).integral
            .intersection(extent)
        guard !crop.isNull, !crop.isEmpty,
              let cgImage = context.createCGImage(oriented, from: crop) else { return nil }

        // The cropped image is already in display orientation.
        let image = VisionImage(image: UIImage(cgImage: cgImage))
        image.orientation = .up
        let recognition = try japaneseRecognizer.results(in: image)
        let lines = recognition.blocks.flatMap(\.lines).sorted {
            let delta = abs($0.frame.midY - $1.frame.midY)
            return delta < 8 ? $0.frame.minX < $1.frame.minX
                : $0.frame.minY < $1.frame.minY
        }
        let raw = lines.map(\.text).joined(separator: "\n")
        // ML Kit v2 has no comparable per-line confidence API. The caller
        // applies a fixed conservative multi-frame confirmation policy.
        let accepted = lines.compactMap { line -> String? in
            GameOCRQuality.evaluate(line.text, confidence: 0.70, language: "ja")?.text
        }
        return Output(text: accepted.joined(separator: "\n"),
                      raw: raw, candidates: lines.count,
                      rejected: lines.count - accepted.count)
        #else
        return nil
        #endif
    }

    #if MLKIT_OCR
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let japaneseRecognizer =
        TextRecognizer.textRecognizer(options: JapaneseTextRecognizerOptions())
    #endif
}
