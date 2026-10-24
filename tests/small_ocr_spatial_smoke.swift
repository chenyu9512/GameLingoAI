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
        let twoLocations = GameOCRSpatialMerge.merge(
            primary: "HP 100", positions: [box("HP 100", 0.85)],
            secondary: [box("HP 100", 0.04)])
        precondition(twoLocations.appended == 1)
        precondition(twoLocations.positions.count == 2)
        precondition(twoLocations.positions[1].y == 0.04)
        let mismatch = GameOCRSpatialMerge.merge(primary: "Hello\nWorld",
                                                 positions: primary,
                                                 secondary: [box("small", 0.02)])
        precondition(mismatch.positions.isEmpty)
        precondition(mismatch.text == "Hello\nWorld\nsmall")
        let onlySmall = GameOCRSpatialMerge.merge(primary: "", positions: [],
                                                 secondary: [box("Tiny", 0.05)])
        precondition(onlySmall.positions.count == 1)
        precondition(onlySmall.text == "Tiny")
        let echo = GameOCRSpatialMerge.excludingOwnPiPText(
            "勇者进入村庄\n欢迎回来！\n实时译文 · 防递归安全显示",
            positions: [box("勇者进入村庄", 0.6), box("欢迎回来！", 0.3),
                        box("实时译文", 0.8)],
            visibleTranslations: ["欢迎回来！"])
        precondition(echo.text == "勇者进入村庄")
        precondition(echo.positions.count == 1)
        precondition(echo.appended == 2)
        let unrelated = GameOCRSpatialMerge.excludingOwnPiPText(
            "菜单\n生命值", positions: [box("菜单", 0.5), box("生命值", 0.4)],
            visibleTranslations: ["欢迎回来！"])
        precondition(unrelated.positions.count == 2)
        print("PASS: small OCR text keeps positions and mismatches fail closed")
    }
}
