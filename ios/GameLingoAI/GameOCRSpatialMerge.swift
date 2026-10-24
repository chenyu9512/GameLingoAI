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

    /// A second defense after disabling video mirroring: suppress OCR lines
    /// that exactly reproduce the text currently rendered inside our own
    /// PiP. Do not remove partial matches or guess a window rectangle.
    static func excludingOwnPiPText(_ text: String, positions: [GamePiPSceneText],
                                    visibleTranslations: [String]) -> Result {
        let source = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let owned = Set((visibleTranslations + ["实时译文 · 防递归安全显示"])
            .map(normalized).filter { $0.count >= 3 })
        let positionAligned = source.count == positions.count
        var retained: [String] = []
        var locations: [GamePiPSceneText] = []
        var dropped = 0
        for (index, line) in source.enumerated() {
            if owned.contains(normalized(line)) {
                dropped += 1
                continue
            }
            retained.append(line)
            if positionAligned { locations.append(positions[index]) }
        }
        return Result(text: retained.joined(separator: "\n"),
                      positions: positionAligned ? locations : [],
                      appended: dropped)
    }

    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }.map { String($0) }.joined().lowercased()
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
