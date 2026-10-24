import Foundation

/// Vision text boxes are bottom-left normalized coordinates in the correctly
/// oriented captured image. All geometry below uses the same coordinates.
struct GamePiPSceneText: Equatable {
    var original: String
    var translated: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum GamePiPSceneLayout {
    struct Rect: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    static let portraitWidth = 360
    static let portraitHeight = 640

    /// Viewport of the oriented image. Full mode preserves the full picture
    /// with letterboxing; focus mode crops around current translated lines.
    static func viewport(sourceWidth: Int, sourceHeight: Int,
                         focus: Bool, boxes: [GamePiPSceneText]) -> Rect {
        let imageW = Double(max(1, sourceWidth))
        let imageH = Double(max(1, sourceHeight))
        let sourceRatio = imageW / imageH
        let outputRatio = Double(portraitWidth) / Double(portraitHeight)
        guard focus, !boxes.isEmpty else {
            return Rect(x: 0, y: 0, width: 1, height: 1)
        }
        let valid = boxes.filter { $0.width > 0 && $0.height > 0 }
        guard !valid.isEmpty else { return Rect(x: 0, y: 0, width: 1, height: 1) }
        let cx = valid.map { $0.x + $0.width / 2 }.reduce(0, +) / Double(valid.count)
        let cy = valid.map { $0.y + $0.height / 2 }.reduce(0, +) / Double(valid.count)
        let boxMinX = valid.map(\.x).min() ?? cx
        let boxMaxX = valid.map { $0.x + $0.width }.max() ?? cx
        let boxMinY = valid.map(\.y).min() ?? cy
        let boxMaxY = valid.map { $0.y + $0.height }.max() ?? cy
        let minW = min(1, max(0.33, boxMaxX - boxMinX + 0.18))
        let minH = min(1, max(0.27, boxMaxY - boxMinY + 0.19))
        // Crop aspect in physical pixels must match portrait canvas.
        let width: Double
        let height: Double
        if sourceRatio > outputRatio {
            height = min(1, max(minH, minW * sourceRatio / outputRatio))
            width = min(1, height * outputRatio / sourceRatio)
        } else {
            width = min(1, max(minW, minH * outputRatio / sourceRatio))
            height = min(1, width * sourceRatio / outputRatio)
        }
        return Rect(x: max(0, min(1 - width, cx - width / 2)),
                    y: max(0, min(1 - height, cy - height / 2)),
                    width: width, height: height)
    }

    /// An input box is allowed to spill past the focus crop. Do not invent a
    /// different location for it; hide boxes that are fully outside the view.
    static func visible(_ block: GamePiPSceneText, in crop: Rect) -> Bool {
        block.x < crop.maxX && block.x + block.width > crop.x &&
        block.y < crop.maxY && block.y + block.height > crop.y
    }

    static func canvasRect(width: Double, height: Double,
                           sourceAspect: Double) -> Rect {
        let destinationRatio = width / max(1, height)
        if sourceAspect > destinationRatio {
            let h = width / max(0.001, sourceAspect)
            return Rect(x: 0, y: (height - h) / 2, width: width, height: h)
        }
        let w = height * sourceAspect
        return Rect(x: (width - w) / 2, y: 0, width: w, height: height)
    }

    static func map(_ block: GamePiPSceneText, sourceCrop: Rect,
                    canvas: Rect) -> Rect {
        Rect(x: canvas.x + (block.x - sourceCrop.x) * canvas.width / sourceCrop.width,
             y: canvas.y + (block.y - sourceCrop.y) * canvas.height / sourceCrop.height,
             width: block.width * canvas.width / sourceCrop.width,
             height: block.height * canvas.height / sourceCrop.height)
    }
}
