import Foundation

/// Aligns precise OCR lines with their original screen coordinates. A
/// mismatch deliberately produces no positioned output instead of attaching
/// a translation to a different text box.
enum GameOCRSpatialMerge {
    struct Result {
        let text: String
        let positions: [GamePiPSceneText]
        let appended: Int
    }

    static func merge(primary: String, positions: [GamePiPSceneText],
                      secondary: [GamePiPSceneText]) -> Result {
        let source = primary.isEmpty ? [] : primary.components(separatedBy: "\n")
        var additional: [GamePiPSceneText] = []
        for line in secondary where !line.original.isEmpty {
            let existsInPrimary = source.contains { GameOCRQuality.isSimilar($0, line.original) }
            let alreadyAppended = additional.contains {
                GameOCRQuality.isSimilar($0.original, line.original)
            }
            if !existsInPrimary && !alreadyAppended {
                additional.append(line)
            }
        }
        let combined = (source + additional.map(\.original)).joined(separator: "\n")
        let canMap = source.count == positions.count
        return Result(text: combined,
                      positions: canMap ? positions + additional : [],
                      appended: additional.count)
    }
}
