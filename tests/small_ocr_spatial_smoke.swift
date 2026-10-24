import Foundation

@main
struct SmallOCRSpatialSmoke {
    static func main() {
        func box(_ text: String, _ y: Double) -> GamePiPSceneText {
            GamePiPSceneText(original: text, translated: "",
                             x: 0.1, y: y, width: 0.5, height: 0.015)
        }
        let primary = [box("Village", 0.50)]
        let secondary = [box("Village", 0.50), box("Small item", 0.03)]
        let result = GameOCRSpatialMerge.merge(primary: "Village",
                                              positions: primary, secondary: secondary)
        precondition(result.text == "Village\nSmall item")
        precondition(result.positions.count == 2)
        precondition(result.positions[1].y == 0.03)
        precondition(result.appended == 1)
        let mismatch = GameOCRSpatialMerge.merge(primary: "Hello\nWorld",
                                                 positions: primary,
                                                 secondary: [box("small", 0.02)])
        precondition(mismatch.positions.isEmpty)
        precondition(mismatch.text == "Hello\nWorld\nsmall")
        let onlySmall = GameOCRSpatialMerge.merge(primary: "", positions: [],
                                                 secondary: [box("Tiny", 0.05)])
        precondition(onlySmall.positions.count == 1)
        precondition(onlySmall.text == "Tiny")
        print("PASS: small OCR text keeps positions and mismatches fail closed")
    }
}
