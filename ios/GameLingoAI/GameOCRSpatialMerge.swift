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

    private static func overlaps(_ a: GamePiPSceneText,
                                 _ b: GamePiPSceneText) -> Bool {
        max(a.x, b.x) < min(a.x + a.width, b.x + b.width) &&
        max(a.y, b.y) < min(a.y + a.height, b.y + b.height)
    }

    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }.map { String($0) }.joined().lowercased()
    }

    static func merge(primary: String, positions: [GamePiPSceneText],
                      secondary: [GamePiPSceneText]) -> Result {
        let source = primary.isEmpty ? [] : primary.components(separatedBy: "\n")
        let canMap = source.count == positions.count
        var additional: [GamePiPSceneText] = []
        // Two distinct locations can legitimately show the same short game
        // text (HP, menu item). De-duplicate only if text AND boxes overlap.
        for line in secondary where !line.original.isEmpty {
            let existsInPrimary = source.enumerated().contains { index, text in
                guard normalized(text) == normalized(line.original) else { return false }
                return !canMap || overlaps(positions[index], line)
            }
            let alreadyAppended = additional.contains {
                normalized($0.original) == normalized(line.original)
                    && overlaps($0, line)
            }
            if !existsInPrimary && !alreadyAppended {
                additional.append(line)
            }
        }
        let combined = (source + additional.map(\.original)).joined(separator: "\n")
        return Result(text: combined,
                      positions: canMap ? positions + additional : [],
                      appended: additional.count)
    }
}
