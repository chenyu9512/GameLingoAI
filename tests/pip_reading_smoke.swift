import Foundation

@main
struct PiPReadingSmoke {
    static func main() {
        let twoLines = GamePiPReadingLayout.paginate(
            original: "おはよう\nまたね", translated: "早上好\n回头见",
            originalLimit: 20, translatedLimit: 20)
        precondition(twoLines.count == 2)
        precondition(twoLines[0].original == "おはよう")
        precondition(twoLines[0].translated == "早上好")
        precondition(twoLines[1].translated == "回头见")

        let source = String(repeating: "勇者の旅。", count: 40)
        let target = String(repeating: "勇者出发了。", count: 32)
        let pages = GamePiPReadingLayout.paginate(
            original: source, translated: target,
            originalLimit: 40, translatedLimit: 35)
        precondition(pages.count > 1)
        precondition(pages.map(\.original).joined() == source)
        precondition(pages.map(\.translated).joined() == target)
        precondition(pages.allSatisfy {
            $0.original.count <= 40 && $0.translated.count <= 35
        })
        let groups = GamePiPReadingLayout.group(pages, maxPairs: 3, maxCharacters: 100)
        precondition(groups.flatMap { $0 } == pages)
        precondition(groups.allSatisfy { $0.count <= 3 })
        precondition(GamePiPReadingLayout.group([], maxPairs: 2, maxCharacters: 100).isEmpty)
        print("PASS: paired pagination preserves all Unicode text and line pairing")
    }
}
