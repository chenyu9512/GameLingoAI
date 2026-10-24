import Foundation

@main
struct PortraitSceneSmoke {
    static func main() {
        let left = GamePiPSceneText(original: "Hello", translated: "你好",
                                    x: 0.07, y: 0.18, width: 0.32, height: 0.07)
        let right = GamePiPSceneText(original: "Items", translated: "道具",
                                     x: 0.59, y: 0.25, width: 0.3, height: 0.06)
        let full = GamePiPSceneLayout.viewport(sourceWidth: 1920, sourceHeight: 1080,
                                               focus: false, boxes: [left])
        precondition(full == .init(x: 0, y: 0, width: 1, height: 1))
        let crop = GamePiPSceneLayout.viewport(sourceWidth: 1920, sourceHeight: 1080,
                                               focus: true, boxes: [left])
        precondition(crop.width < 1 && crop.height <= 1)
        precondition(abs((crop.width * 1920) / (crop.height * 1080) - 360.0 / 640.0) < 0.001)
        precondition(GamePiPSceneLayout.visible(left, in: crop))
        let canvas = GamePiPSceneLayout.canvasRect(width: 360, height: 640,
                                                    sourceAspect: 1080.0 / 1920.0)
        precondition(abs(canvas.width - 360) < 0.001)
        precondition(abs(canvas.height - 640) < 0.001)
        let mapped = GamePiPSceneLayout.map(left,
                                           sourceCrop: .init(x: 0, y: 0, width: 1, height: 1),
                                           canvas: canvas)
        precondition(abs(mapped.x - 0.07 * 360) < 0.001)
        precondition(abs(mapped.y - 0.18 * 640) < 0.001)
        let portrait = GamePiPSceneLayout.viewport(sourceWidth: 1080, sourceHeight: 1920,
                                                   focus: true, boxes: [right])
        precondition(portrait.x >= 0 && portrait.y >= 0)
        precondition(portrait.maxX <= 1.0001 && portrait.maxY <= 1.0001)
        print("PASS: portrait and landscape OCR overlay coordinate mapping")
    }
}
