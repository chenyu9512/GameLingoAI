import Foundation

@main
struct GlossaryTXTTests {
    static func main() throws {
        let text = """
        # 词库名称：我的 DQ 游戏
        ホイミ=霍伊米
        スライム=史莱姆
        HP\t生命值
        ホイミ=回复魔法
        这是没有分隔符的一行
        """
        let report = try GameGlossaryTXTParser.parse(Data(text.utf8),
                                                      filename: "import.txt")
        precondition(report.title == "我的 DQ 游戏")
        precondition(report.entries.count == 3)
        precondition(report.duplicates == 1)
        precondition(report.invalid == 1)
        precondition(report.entries[0].0 == "ホイミ")
        precondition(report.entries[0].1 == "回复魔法")
        precondition(report.entries[2].0 == "HP")
        let utf16 = text.data(using: .utf16)!
        let unicode = try GameGlossaryTXTParser.parse(utf16, filename: "utf16.txt")
        precondition(unicode.entries.count == 3)
        do {
            _ = try GameGlossaryTXTParser.parse(Data("# heading\n".utf8),
                                                filename: "empty.txt")
            preconditionFailure("Empty glossary must be rejected")
        } catch GameGlossaryTXTParser.ParseError.empty {}
        print("PASS: TXT glossary UTF-8, UTF-16, duplicates, invalid lines, order, error handling")
    }
}
