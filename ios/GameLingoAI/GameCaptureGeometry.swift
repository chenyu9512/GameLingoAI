import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import UIKit

/// The rotation of pixels in a captured frame is not always the same as
/// the device orientation (some games lock their own interface).
enum GameScreenRotation: String, Codable, CaseIterable, Identifiable {
    case automatic, upright, left, right, upsideDown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动识别"
        case .upright: return "原始方向"
        case .left: return "左转 90°"
        case .right: return "右转 90°"
        case .upsideDown: return "旋转 180°"
        }
    }

    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .automatic, .upright: return .up
        case .left: return .left
        case .right: return .right
        case .upsideDown: return .down
        }
    }
}

enum GameFrameLayout: String, Codable, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }
    var title: String { self == .portrait ? "竖屏" : "横屏" }
}

/// Identifies the actual pixel layout on each frame, not by app window or
/// UIDevice orientation. In automatic mode ScreenCaptureKit's display pixels
/// are treated as upright; if a game rotates its artwork inside the buffer,
/// the user may override rotation without restarting the stream.
struct GameCaptureGeometry {
    let width: Int
    let height: Int
    let rotation: GameScreenRotation

    var imageOrientation: CGImagePropertyOrientation { rotation.imageOrientation }
    var layout: GameFrameLayout {
        let sideways = rotation == .left || rotation == .right
        let renderedWidth = sideways ? height : width
        let renderedHeight = sideways ? width : height
        return renderedWidth >= renderedHeight ? .landscape : .portrait
    }

    var identity: String {
        "\(width)x\(height):\(rotation.rawValue):\(layout.rawValue)"
    }

    /// Vision ROI and observation boxes are in the orientation-corrected
    /// image's normalized lower-left coordinates. Fingerprinting reads raw
    /// CVPixelBuffer bytes, so its ROI needs the inverse rotation.
    func rawRegion(for orientedROI: CGRect) -> CGRect {
        switch imageOrientation {
        case .up, .upMirrored:
            return orientedROI
        case .down, .downMirrored:
            return CGRect(x: 1 - orientedROI.maxX, y: 1 - orientedROI.maxY,
                          width: orientedROI.width, height: orientedROI.height)
        case .right, .rightMirrored:
            return CGRect(x: 1 - orientedROI.maxY, y: orientedROI.minX,
                          width: orientedROI.height, height: orientedROI.width)
        case .left, .leftMirrored:
            return CGRect(x: orientedROI.minY, y: 1 - orientedROI.maxX,
                          width: orientedROI.height, height: orientedROI.width)
        @unknown default:
            return orientedROI
        }
    }
}

/// UIImage.Orientation and CGImagePropertyOrientation have *different raw
/// values*. A CGImage from PhotosPicker must carry the corresponding
/// orientation when passed to Vision OCR, especially for portrait snapshots.
extension UIImage.Orientation {
    var gameVisionOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
