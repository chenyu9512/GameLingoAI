import Foundation
import Vision
import CoreVideo
import CoreImage
import CoreGraphics
import ImageIO

/// Secondary OCR recognizer: Vision supplies text bounding boxes, and the
/// actual PP-OCRv6 Small ONNX recognition model re-reads selected image crops.
/// This intentionally avoids running a second full-screen detector per frame.
enum GamePaddleOCR {
    struct Output {
        let text: String
        let confidence: Double
        let lines: Int
    }

    #if PADDLE_OCR
    private final class Worker {
        let env: ORTEnv
        let session: ORTSession
        let inputName: String
        let outputNames: Set<String>
        let dictionary: [String]
        let context = CIContext(options: [.useSoftwareRenderer: false])

        init() throws {
            guard let model = Bundle.main.path(forResource: "inference", ofType: "onnx",
                                              inDirectory: "PaddleModels/rec"),
                  let dict = Bundle.main.path(forResource: "characters", ofType: "txt",
                                             inDirectory: "PaddleModels/rec") else {
                throw NSError(domain: "GamePaddleOCR", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "PP-OCRv6 model or dictionary is missing"])
            }
            let vocabulary = try String(contentsOfFile: dict, encoding: .utf8)
                .components(separatedBy: .newlines)
            guard vocabulary.count > 100 else {
                throw NSError(domain: "GamePaddleOCR", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid character dictionary"])
            }
            dictionary = [""] + vocabulary.filter { !$0.isEmpty } + [" "]
            env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            session = try ORTSession(env: env, modelPath: model, sessionOptions: options)
            guard let input = try session.inputNames().first else {
                throw NSError(domain: "GamePaddleOCR", code: 3)
            }
            inputName = input
            outputNames = Set(try session.outputNames())
        }

        func recognize(_ image: CGImage) throws -> (text: String, confidence: Double) {
            let height = 48
            let width = max(32, min(640, Int(ceil(Double(image.width) * 48 /
                                                   Double(max(1, image.height))))))
            var pixels = [UInt8](repeating: 0, count: height * width * 4)
            let available = pixels.withUnsafeMutableBytes { ptr -> Bool in
                guard let base = ptr.baseAddress,
                      let ctx = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                          | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                // Fixed height, bounded width; full line is retained in each crop.
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard available else { return ("", 0) }
            let stride = width * height
            var tensor = [Float](repeating: 0, count: 3 * stride)
            for pos in 0..<stride {
                let pixel = pos * 4
                // PaddleOCR decode uses BGR and normalization from 0..255 to -1..1.
                tensor[pos] = Float(pixels[pixel + 2]) / 127.5 - 1
                tensor[stride + pos] = Float(pixels[pixel + 1]) / 127.5 - 1
                tensor[2 * stride + pos] = Float(pixels[pixel]) / 127.5 - 1
            }
            let data = tensor.withUnsafeBytes { bytes in
                NSMutableData(bytes: bytes.baseAddress!, length: bytes.count)
            }
            let input = try ORTValue(tensorData: data, elementType: .float,
                                     shape: [NSNumber(value: 1), NSNumber(value: 3),
                                             NSNumber(value: height), NSNumber(value: width)])
            let result = try session.run(withInputs: [inputName: input],
                                         outputNames: outputNames, runOptions: nil)
            guard let value = result.values.first else { return ("", 0) }
            let dims = try value.tensorTypeAndShapeInfo().shape.map { $0.intValue }
            guard dims.count == 3, dims[0] == 1, dims[1] > 0,
                  dims[2] == dictionary.count else { return ("", 0) }
            let probabilities = try value.tensorData() as Data
            let floats = probabilities.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let timesteps = dims[1], classes = dims[2]
            guard floats.count == timesteps * classes else { return ("", 0) }
            var resultText = ""
            var previous = -1
            var confidence: Double = 0
            var characters = 0
            for t in 0..<timesteps {
                let start = t * classes
                var index = 0
                var score = floats[start]
                for c in 1..<classes where floats[start + c] > score {
                    index = c
                    score = floats[start + c]
                }
                if index > 0 && index != previous {
                    resultText += dictionary[index]
                    confidence += Double(score)
                    characters += 1
                }
                previous = index
            }
            return (resultText, characters == 0 ? 0 : confidence / Double(characters))
        }

        func run(buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                 boxes: [CGRect], region: CGRect) throws -> Output? {
            guard !boxes.isEmpty else { return nil }
            let oriented = CIImage(cvPixelBuffer: buffer)
                .oriented(forExifOrientation: Int32(orientation.rawValue))
            let extent = oriented.extent
            // Vision text boxes have normalized bottom-left coordinates.
            let ordered = boxes.sorted {
                abs($0.midY - $1.midY) < 0.025
                    ? $0.minX < $1.minX : $0.midY > $1.midY
            }
            var lines: [String] = []
            var sums = 0.0
            for box in ordered.prefix(8) {
                let padded = box.insetBy(dx: -0.006, dy: -0.003)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard padded.width > 0, padded.height > 0 else { continue }
                let crop = CGRect(x: extent.minX + padded.minX * extent.width,
                                  y: extent.minY + padded.minY * extent.height,
                                  width: padded.width * extent.width,
                                  height: padded.height * extent.height)
                    .integral.intersection(extent)
                guard let image = context.createCGImage(oriented, from: crop) else { continue }
                let output = try recognize(image)
                if output.confidence >= 0.55,
                   GameOCRQuality.evaluate(output.text, confidence: Float(min(1, output.confidence)),
                                           language: "auto") != nil {
                    lines.append(output.text)
                    sums += output.confidence
                }
            }
            guard !lines.isEmpty else { return nil }
            return Output(text: lines.joined(separator: "\n"),
                          confidence: sums / Double(lines.count), lines: lines.count)
        }
    }

    // Called only from the serialized background OCR lane. Model loading is lazy.
    private static var worker: Worker?
    private static var initializationFailed = false
    static var isAvailable: Bool {
        Bundle.main.path(forResource: "inference", ofType: "onnx",
                         inDirectory: "PaddleModels/rec") != nil
    }

    static func recognize(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                          boxes: [CGRect], region: CGRect) throws -> Output? {
        precondition(!Thread.isMainThread, "PaddleOCR must run on background OCR queue")
        guard isAvailable && !initializationFailed else { return nil }
        if worker == nil {
            do { worker = try Worker() }
            catch {
                initializationFailed = true
                throw error
            }
        }
        return try worker?.run(buffer: buffer, orientation: orientation,
                               boxes: boxes, region: region)
    }
    #else
    static let isAvailable = false
    static func recognize(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                          boxes: [CGRect], region: CGRect) throws -> Output? { nil }
    #endif
}
