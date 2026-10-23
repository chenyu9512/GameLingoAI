import Foundation
import SwiftUI

struct GameGlossaryEntry: Codable, Hashable {
    let source: String
    let target: String
}

struct GameGlossaryPack: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var entries: [GameGlossaryEntry]
}

struct GameGlossaryImportReport {
    let imported: Int
    let duplicates: Int
    let invalid: Int
    let title: String
}

/// Saved to Application Support, not UserDefaults: large TXT packs should not
/// re-encode into unrelated UI settings at every keystroke.
@MainActor
final class GameGlossaryLibrary: ObservableObject {
    static let shared = GameGlossaryLibrary()

    @Published private(set) var packs: [GameGlossaryPack] = []
    @Published private(set) var enabledByGame: [UUID: Set<UUID>] = [:]
    @Published private(set) var lastNotice = ""

    private struct Database: Codable {
        var packs: [GameGlossaryPack]
        var enabledByGame: [UUID: Set<UUID>]
    }

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("GameLingoDirect", isDirectory: true)
        return folder.appendingPathComponent("glossary-packs-v1.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let value = try? JSONDecoder().decode(Database.self, from: data) {
            packs = value.packs
            enabledByGame = value.enabledByGame
        }
    }

    func isEnabled(_ id: UUID, game: UUID) -> Bool {
        enabledByGame[game, default: []].contains(id)
    }

    func setEnabled(_ enabled: Bool, pack id: UUID, game: UUID) {
        var set = enabledByGame[game] ?? []
        if enabled { set.insert(id) } else { set.remove(id) }
        enabledByGame[game] = set
        save()
    }

    func setAll(_ enabled: Bool, game: UUID) {
        enabledByGame[game] = enabled ? Set(packs.map(\.id)) : []
        save()
    }

    func remove(_ id: UUID) {
        packs.removeAll { $0.id == id }
        for game in Array(enabledByGame.keys) {
            enabledByGame[game]?.remove(id)
        }
        save()
    }

    var totalTerms: Int { packs.reduce(0) { $0 + $1.entries.count } }

    func activeDictionary(game: UUID) -> [String: String] {
        let active = enabledByGame[game] ?? []
        var result: [String: String] = [:]
        // Later imported packs win. Game-specific manual overrides are applied
        // separately by GameRPGDictionary.glossary(for:).
        for pack in packs where active.contains(pack.id) {
            for entry in pack.entries { result[entry.source] = entry.target }
        }
        return result
    }

    func search(_ query: String) -> [(String, String, String)] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return packs.flatMap { pack in
            pack.entries.compactMap { entry -> (String, String, String)? in
                guard term.isEmpty ||
                    entry.source.localizedCaseInsensitiveContains(term) ||
                    entry.target.localizedCaseInsensitiveContains(term) else { return nil }
                return (entry.source, entry.target, pack.title)
            }
        }
    }

    /// TXT (UTF-8, optionally UTF-16), one term per line:
    /// Japanese=Chinese OR Japanese<TAB>Chinese.
    /// # 词库名称：My RPG Pack
    func importText(_ data: Data, suggestedName: String, game: UUID) throws -> GameGlossaryImportReport {
        let result = try GameGlossaryTXTParser.parse(data, filename: suggestedName)
        let entries = result.entries.map {
            GameGlossaryEntry(source: $0.0, target: $0.1)
        }
        guard packs.count < 30, totalTerms + entries.count <= 100_000 else {
            throw ImportError.tooManyPacks
        }
        let pack = GameGlossaryPack(title: result.title, entries: entries)
        packs.append(pack)
        enabledByGame[game, default: []].insert(pack.id)
        guard save() else {
            packs.removeAll { $0.id == pack.id }
            enabledByGame[game]?.remove(pack.id)
            throw ImportError.saveFailed
        }
        lastNotice = "已导入「\(pack.title)」\(entries.count) 条；重复 \(result.duplicates)，无效 \(result.invalid)。当前游戏已启用。"
        return GameGlossaryImportReport(imported: entries.count,
                                        duplicates: result.duplicates,
                                        invalid: result.invalid,
                                        title: pack.title)
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let location = Self.fileURL
            try FileManager.default.createDirectory(
                at: location.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(
                Database(packs: packs, enabledByGame: enabledByGame))
            try data.write(to: location, options: .atomic)
            return true
        } catch {
            lastNotice = "词库保存失败：\(error.localizedDescription)"
            return false
        }
    }

    enum ImportError: LocalizedError {
        case tooLarge, invalidEncoding, tooManyEntries, empty
        case tooManyPacks, saveFailed
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "TXT 文件超过 4 MB，请分成多份"
            case .invalidEncoding: return "TXT 编码应为 UTF-8 或 UTF-16"
            case .tooManyEntries: return "单个词库不能超过 25,000 条"
            case .empty: return "没有找到有效的 日语=中文 词条"
            case .tooManyPacks: return "最多支持 30 套词库，合计 100,000 条，请删除无用词库"
            case .saveFailed: return "写入词库文件失败（可能是存储空间不足）"
            }
        }
    }
}
