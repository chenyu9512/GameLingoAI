import Foundation
import SwiftUI
import CoreGraphics

// All data is local to the main app. No App Groups, network calls, or raw-frame storage.
struct GameOCRBox: Codable, Equatable {
    var x: Double = 0.03
    var y: Double = 0.03
    var width: Double = 0.94
    var height: Double = 0.62

    var rect: CGRect {
        let ox = min(0.98, max(0, x))
        let oy = min(0.98, max(0, y))
        return CGRect(x: ox, y: oy,
                      width: min(max(width, 0.03), 1 - ox),
                      height: min(max(height, 0.03), 1 - oy))
    }

    static let dialogue = GameOCRBox()
    static let landscapeDialogue = GameOCRBox(x: 0.03, y: 0.03,
                                               width: 0.94, height: 0.48)
    static let full = GameOCRBox(x: 0.02, y: 0.02, width: 0.96, height: 0.96)
}

/// Persisted as an optional profile field to avoid breaking existing saves.
enum GameOCREngine: String, Codable, CaseIterable, Identifiable {
    case vision
    case paddleHybrid
    // Preserve decoding old saved profiles; never select or load Google OCR.
    case mlkitJapanese

    static var allCases: [GameOCREngine] { [.vision, .paddleHybrid] }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vision: return "Apple Vision · 多语言实时"
        case .paddleHybrid: return "Vision + PaddleOCR · 智能增强"
        case .mlkitJapanese: return "旧 Google 配置（已弃用）"
        }
    }
}

struct GameProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var language: String = "auto"
    // Old profiles decode without this field; Vision remains the fallback.
    var experimentalOCR: GameOCREngine? = nil
    var selectedOCR: GameOCREngine {
        experimentalOCR == .mlkitJapanese ? .vision : (experimentalOCR ?? .vision)
    }
    var region: GameOCRBox = .dialogue                 // portrait / old profiles
    var landscapeRegion: GameOCRBox? = nil             // optional, for migration
    var rotation: GameScreenRotation? = nil            // nil = automatic
    var glossary: String = ""
    // nil for old saved profiles; auto-enable only when the game name matches.
    var useDragonQuestLexicon: Bool? = nil
    // Optional normalized region of screen to ignore (e.g. HUD or PiP location).
    var excluded: GameOCRBox? = nil
    var bottomBoost: Bool? = nil
    var bottomScanEnabled: Bool { bottomBoost ?? true }

    var screenRotation: GameScreenRotation { rotation ?? .automatic }
    var dragonQuestEnabled: Bool {
        useDragonQuestLexicon ?? (
            name.localizedCaseInsensitiveContains("ドラゴンクエスト")
            || name.localizedCaseInsensitiveContains("ドラクエ")
            || name.localizedCaseInsensitiveContains("勇者斗恶龙")
            || name.localizedCaseInsensitiveContains("dragon quest")
        )
    }
    func region(for layout: GameFrameLayout) -> GameOCRBox {
        layout == .portrait ? region : (landscapeRegion ?? .landscapeDialogue)
    }
}

struct GameSubtitleLine: Identifiable, Codable {
    var id = UUID()
    let original: String
    let translated: String
    let game: String
    let timestamp: Date
    let elapsedMs: Int
}

enum GamePerformance: String, Codable, CaseIterable, Identifiable {
    case fast, balanced, battery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fast: return "快速"
        case .balanced: return "平衡"
        case .battery: return "省电"
        }
    }
    var minimumInterval: TimeInterval {
        switch self {
        case .fast: return 0.30
        case .balanced: return 0.48
        case .battery: return 1.20
        }
    }
}

enum GamePiPLayout: String, Codable, CaseIterable, Identifiable {
    // Preserve old raw cases, so saved v3.3.1 preferences still decode.
    case compact, standard, learning
    case multiBilingual, denseChinese, menuPages
    case fullBilingual, fullChinese, spatialMenu
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "精简"
        case .standard: return "标准双语"
        case .learning: return "学习双语"
        case .multiBilingual: return "多行双语"
        case .denseChinese: return "译文高密度"
        case .menuPages: return "菜单分页"
        case .fullBilingual: return "满窗双语阅读"
        case .fullChinese: return "满窗译文阅读"
        case .spatialMenu: return "原位菜单阅读"
        }
    }
}

// Legacy serialized case names are kept, but target content is now user-selectable.
enum GameSubtitleMode: String, Codable, CaseIterable, Identifiable {
    case bilingual, chinese, original
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bilingual: return "双语"
        case .chinese: return "仅译文"
        case .original: return "仅原文"
        }
    }
}

@MainActor
final class GameLingoStore: ObservableObject {
    static let shared = GameLingoStore()
    private static let storageKey = "GameLingo.Direct.3.0"

    private struct Saved: Codable {
        var profiles: [GameProfile]
        var activeID: UUID
        var performance: GamePerformance
        var provider: GameTranslationProvider?
        var endpoint: GameTranslationEndpoint?
        var targetLanguage: String?
        var autoplay: Bool?
        var playbackSeconds: Double?
        var readAloud: Bool?
        var pipLayout: GamePiPLayout
        var subtitleMode: GameSubtitleMode
        var fontScale: Double
        var history: [GameSubtitleLine]
        var onboardingComplete: Bool
    }

    @Published var profiles: [GameProfile] { didSet { persist() } }
    @Published var activeID: UUID { didSet { persist() } }
    @Published var performance: GamePerformance { didSet { persist() } }
    @Published var provider: GameTranslationProvider { didSet { persist() } }
    @Published var endpoint: GameTranslationEndpoint { didSet { persist() } }
    @Published var targetLanguage: String { didSet { persist() } }
    @Published var autoplay: Bool { didSet { persist() } }
    @Published var playbackSeconds: Double { didSet { persist() } }
    @Published var readAloud: Bool { didSet { persist() } }
    @Published var pipLayout: GamePiPLayout { didSet { persist() } }
    @Published var subtitleMode: GameSubtitleMode { didSet { persist() } }
    @Published var fontScale: Double { didSet { persist() } }
    @Published var history: [GameSubtitleLine] { didSet { scheduleHistoryPersist() } }
    private var historyPersistTask: DispatchWorkItem?
    @Published var onboardingComplete: Bool { didSet { persist() } }

    private init() {
        let stored = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        // Preserve source-language and scan-area choices from the working 2.2 build.
        var defaultProfile = GameProfile(name: "默认游戏")
        defaultProfile.language = UserDefaults.standard.string(forKey: "direct.sourceLanguage") ?? "auto"
        if UserDefaults.standard.string(forKey: "direct.scanArea") == "full" {
            defaultProfile.region = .full
        }
        var restoredProfiles = stored?.profiles.isEmpty == false ? stored!.profiles : [defaultProfile]
        var shouldPersistAutoMigration = false
        // One-time opt-in migration for the original unconfigured default game.
        // Named/customized game profiles retain their explicit language choice.
        let migrationKey = "direct.autoSource.migrated.3_5_2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            for index in restoredProfiles.indices
            where restoredProfiles[index].name == "默认游戏"
                  && restoredProfiles[index].language == "ja" {
                restoredProfiles[index].language = "auto"
                shouldPersistAutoMigration = true
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        profiles = restoredProfiles
        activeID = stored?.activeID ?? defaultProfile.id
        performance = stored?.performance ?? .balanced
        provider = stored?.provider ?? .offline
        endpoint = stored?.endpoint ?? GameTranslationEndpoint()
        targetLanguage = stored?.targetLanguage ?? GameTranslationLanguages.preferredTarget()
        autoplay = stored?.autoplay ?? false
        playbackSeconds = stored?.playbackSeconds ?? 5.0
        readAloud = stored?.readAloud ?? false
        pipLayout = stored?.pipLayout ?? .fullBilingual
        subtitleMode = stored?.subtitleMode ?? .bilingual
        fontScale = stored?.fontScale
            ?? (UserDefaults.standard.object(forKey: "pip.subtitle.scale") as? Double)
            ?? 1.0
        history = stored?.history ?? []
        onboardingComplete = stored?.onboardingComplete ?? false
        // One-time 3.7.1 migration: replace the old scrolling default with
        // static full-window paired reading. Preserve other custom layouts.
        var shouldPersistReadingMigration = false
        let readingMigrationKey = "direct.fullPage.migrated.3_7_1"
        if !UserDefaults.standard.bool(forKey: readingMigrationKey) {
            if pipLayout == .standard {
                pipLayout = .fullBilingual
                autoplay = false
                shouldPersistReadingMigration = true
            }
            UserDefaults.standard.set(true, forKey: readingMigrationKey)
        }
        if !profiles.contains(where: { $0.id == activeID }), let first = profiles.first {
            activeID = first.id
        }
        // Persist the migrated default immediately. Otherwise the one-time
        // migration marker would be set but an old saved "ja" reappears next run.
        if shouldPersistAutoMigration || shouldPersistReadingMigration { persist() }
    }

    var activeProfile: GameProfile {
        profiles.first(where: { $0.id == activeID }) ?? profiles[0]
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    @discardableResult
    func selectSourceLanguage(_ language: String, for id: UUID) -> Bool {
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].language = value
        return profiles[index].language == value
    }

    @discardableResult
    func selectOCREngine(_ engine: GameOCREngine, for id: UUID) -> Bool {
        guard engine == .vision || engine == .paddleHybrid,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].experimentalOCR = engine
        return profiles[index].selectedOCR == engine
    }

    func saveProfile(_ profile: GameProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        activeID = profile.id
    }

    // A single tap enables/disables all 89 DQ-specific entries for one game.
    // Only the flag is saved; no entries are appended to the user's glossary.
    @discardableResult
    func setDragonQuestPackEnabled(_ enabled: Bool, for id: UUID) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        profiles[index].useDragonQuestLexicon = enabled
        return true
    }

    func createProfile() {
        let p = GameProfile(name: "新游戏 \(profiles.count + 1)")
        profiles.append(p)
        activeID = p.id
    }

    func deleteActiveProfile() {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == activeID }
        if let first = profiles.first { activeID = first.id }
    }

    func add(_ line: GameSubtitleLine) {
        if let last = history.first,
           last.original == line.original,
           last.translated == line.translated,
           last.game == line.game {
            return
        }
        history.insert(line, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
    }

    func clearHistory() { history.removeAll() }

    var profileBackupJSON: String {
        guard let data = try? JSONEncoder().encode(profiles) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    @discardableResult
    func restoreProfiles(from json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode([GameProfile].self, from: data),
              !imported.isEmpty,
              imported.count <= 100 else { return false }
        let safe = imported.map { profile -> GameProfile in
            var result = profile
            result.name = String(profile.name.prefix(70))
            result.glossary = String(profile.glossary.prefix(10000))
            return result
        }
        profiles = safe
        activeID = safe[0].id
        return true
    }

    nonisolated static func glossaryMap(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let divider = line.firstIndex(of: "=") else { continue }
            let a = String(line[..<divider]).trimmingCharacters(in: .whitespacesAndNewlines)
            let b = String(line[line.index(after: divider)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty && !b.isEmpty { result[a] = b }
        }
        return result
    }

    private func scheduleHistoryPersist() {
        // Translating every dialogue line should not synchronously encode
        // a 200-entry history blob on the main thread.
        historyPersistTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        historyPersistTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func flushHistory() {
        historyPersistTask?.cancel()
        historyPersistTask = nil
        persist()
    }

    private func persist() {
        historyPersistTask?.cancel()
        historyPersistTask = nil
        let state = Saved(profiles: profiles, activeID: activeID,
                          performance: performance, provider: provider, endpoint: endpoint,
                          targetLanguage: targetLanguage,
                          autoplay: autoplay, playbackSeconds: playbackSeconds,
                           readAloud: readAloud, pipLayout: pipLayout,
                          subtitleMode: subtitleMode, fontScale: fontScale,
                          history: history, onboardingComplete: onboardingComplete)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
