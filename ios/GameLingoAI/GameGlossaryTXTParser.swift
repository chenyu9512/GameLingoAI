import Foundation

struct GameGlossaryTXTResult {
    let title: String
    let entries: [(String, String)]
    let duplicates: Int
    let invalid: Int
}

enum GameGlossaryTXTParser {
    enum ParseError: LocalizedError {
        case tooLarge, invalidEncoding, tooManyEntries, empty
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "TXT 文件超过 4 MB"
            case .invalidEncoding: return "请使用 UTF-8 或 UTF-16 保存 TXT"
            case .tooManyEntries: return "单个词库不能超过 25,000 条"
            case .empty: return "没有找到合法的 日语=中文 词条"
            }
        }
    }

    static func parse(_ data: Data, filename: String) throws -> GameGlossaryTXTResult {
        guard data.count <= 4_000_000 else { throw ParseError.tooLarge }
        guard var content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
        else { throw ParseError.invalidEncoding }
        content = content.replacingOccurrences(of: "\r\n", with: "\n")
        var title = filename.replacingOccurrences(of: ".txt", with: "",
                                                   options: .caseInsensitive)
        var pairs: [String: String] = [:]
        var ordered: [String] = []
        var duplicates = 0
        var invalid = 0
        for raw in content.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let comment = String(line.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                for prefix in ["词库名称：", "词库名称:", "名称：", "名称:"] {
                    if comment.hasPrefix(prefix) {
                        let provided = String(comment.dropFirst(prefix.count))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !provided.isEmpty { title = String(provided.prefix(60)) }
                    }
                }
                continue
            }
            let separator = line.firstIndex(of: "=") ?? line.firstIndex(of: "\t")
            guard let separator else { invalid += 1; continue }
            let japanese = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let chinese = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !japanese.isEmpty && !chinese.isEmpty,
                  japanese.count <= 200 && chinese.count <= 500 else {
                invalid += 1
                continue
            }
            if pairs[japanese] == nil { ordered.append(japanese) }
            else { duplicates += 1 }
            pairs[japanese] = chinese
            guard ordered.count <= 25_000 else { throw ParseError.tooManyEntries }
        }
        guard !ordered.isEmpty else { throw ParseError.empty }
        return GameGlossaryTXTResult(
            title: String(title.prefix(60)),
            entries: ordered.compactMap {
                guard let translation = pairs[$0] else { return nil }
                return ($0, translation)
            },
            duplicates: duplicates, invalid: invalid)
    }
}
