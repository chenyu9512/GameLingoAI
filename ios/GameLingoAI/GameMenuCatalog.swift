import Foundation
import SwiftUI
import Translation
import CoreGraphics

/// One spatially anchored menu/HUD string. All detected lines are kept:
/// PiP intentionally stays short, but the catalog does not impose a 7-line limit.
struct GameMenuBlock: Codable, Identifiable, Equatable {
    var id: String
    var original: String
    var chinese: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double
}

struct GameMenuPage: Codable, Identifiable {
    var id = UUID()
    var profileID: UUID
    var gameName: String
    var language: String
    var scannedAt: Date
    var blocks: [GameMenuBlock]
    // Optional for backwards-compatible decoding of pages saved before 3.2.
    var layout: GameFrameLayout? = nil
    var provider: GameTranslationProvider? = nil
    var endpointID: String? = nil
}

/// A local archive of full-screen OCR pages and previously translated strings.
/// The app never saves screenshots or sends pixels to a server.
@available(iOS 27.0, *)
@MainActor
final class GameMenuCatalog: ObservableObject {
    static let shared = GameMenuCatalog()
    @Published private(set) var currentPage: GameMenuPage?
    @Published private(set) var savedPages: [GameMenuPage] = []
    @Published private(set) var status = "等待整屏菜单扫描"
    @Published private(set) var translatedCount = 0
    @Published private(set) var isTranslating = false
    @Published private(set) var lastScanMilliseconds = 0
    @Published private(set) var lastError = ""

    private struct Saved: Codable {
        var pages: [GameMenuPage]
        var translationCache: [String: String]
    }
    private static let storageKey = "GameLingo.Direct.MenuPages.v1"
    private var cache: [String: String] = [:]
    private var job: Task<Void, Never>?
    private var revision = 0
    private var fingerprint: UInt64 = 0

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return
        }
        savedPages = saved.pages
        currentPage = saved.pages.first
        cache = saved.translationCache
        translatedCount = currentPage?.blocks.filter { $0.chinese != nil }.count ?? 0
    }

    func statusForUserRequest() {
        status = "请在约 3 秒内切回游戏；屏幕采集会自动扫描游戏画面"
    }

    func open(_ page: GameMenuPage) {
        // Browsing a previous page must not interrupt capture or a running translation.
        // Live OCR can keep updating the current page; this is read-only history.
        guard savedPages.contains(where: { $0.id == page.id }) else { return }
        currentPage = page
    }

    func clear() {
        revision += 1
        job?.cancel()
        job = nil
        savedPages = []
        currentPage = nil
        cache = [:]
        isTranslating = false
        translatedCount = 0
        status = "菜单记录已清空"
        persist()
    }

    func cancelForProfileChange() {
        revision += 1
        job?.cancel()
        job = nil
        isTranslating = false
        fingerprint = 0
    }

    func receive(_ recognized: [GameMenuBlock], profileID: UUID,
                 gameName: String, language: String,
                 glossary: [String: String], fingerprint newFingerprint: UInt64,
                 ocrMilliseconds: Int, explicitlyRequested: Bool = false,
                 layout: GameFrameLayout = .portrait,
                 overrideProvider: GameTranslationProvider? = nil) {
        guard profileID == GameLingoStore.shared.activeID else { return }
        lastScanMilliseconds = ocrMilliseconds
        guard !recognized.isEmpty else {
            status = "这次全屏扫描没有检测到文字；保留上次菜单"
            return
        }
        // Ignore sparse automatic scans of normal combat/dialogue scenes.
        // Explicit manual scans always keep every detected line.
        if recognized.count < 4 && !explicitlyRequested {
            status = "屏幕文字较少，保留上次菜单；可手动扫描少量文字的页面"
            return
        }

        // Do not retranslate or overwrite an unchanged page. This also keeps
        // complete menu translations available when the user returns to the app.
        let provider = overrideProvider ?? GameLingoStore.shared.provider
        let endpoint = GameLingoStore.shared.endpoint
        let endpointID = provider == .offline ? "" : endpoint.url
        let signature = recognized.map { $0.original }.joined(separator: "\n")
        let previousSignature = savedPages.first.map {
            $0.blocks.map { $0.original }.joined(separator: "\n")
        }
        let unchanged = (newFingerprint == fingerprint
            || previousSignature == signature)
            && savedPages.first?.profileID == profileID
            && savedPages.first?.layout == layout
            && (savedPages.first?.provider ?? .offline) == provider
            && (savedPages.first?.endpointID ?? "") == endpointID
        if unchanged {
            if isTranslating || savedPages.first?.blocks.allSatisfy({ $0.chinese != nil }) == true {
                status = "画面文字未改变，沿用已翻译的菜单"
                return
            }
            // A previous offline translation may have failed. Rescanning the
            // same page must retry outstanding blocks instead of deadlocking.
        }
        fingerprint = newFingerprint
        revision += 1
        lastError = ""
        let token = revision
        job?.cancel()

        var prepared = recognized
        for i in prepared.indices {
            let key = cacheKey(profileID: profileID, language: language,
                               source: prepared[i].original, provider: provider,
                               endpointID: endpointID)
            prepared[i].chinese = glossary[prepared[i].original] ?? cache[key]
        }
        let pageID = unchanged ? (savedPages.first?.id ?? UUID()) : UUID()
        var page = GameMenuPage(id: pageID, profileID: profileID, gameName: gameName,
                                language: language, scannedAt: Date(), blocks: prepared,
                                layout: layout, provider: provider, endpointID: endpointID)
        savedPages.removeAll { $0.profileID == profileID
            && ($0.provider ?? .offline) == provider
            && ($0.endpointID ?? "") == endpointID
            && $0.blocks.map { $0.original } == prepared.map { $0.original } }
        savedPages.insert(page, at: 0)
        savedPages = Array(savedPages.prefix(12))
        currentPage = page
        translatedCount = prepared.filter { $0.chinese != nil }.count
        status = "整屏检测到 \(prepared.count) 个文本块，已译 \(translatedCount) 个"
        persist()

        // Preserve text order; the response identifier is mapped to each
        // request, while the page itself stays in screen reading order.
        var seen = Set<String>()
        let unknown = prepared.compactMap { block -> String? in
            guard block.chinese == nil, seen.insert(block.original).inserted else { return nil }
            return block.original
        }
        if unknown.isEmpty {
            isTranslating = false
            status = "整屏双语清单已完成，共 \(prepared.count) 条"
            return
        }
        isTranslating = true

        job = Task { @MainActor [weak self] in
            guard let self else { return }
            // Online API is always an explicit opt-in. Cached RPG terms are
            // already filled in above; only unknown individual blocks leave
            // the device, never raw screenshots.
            if provider != .offline {
                for source in unknown {
                    guard token == self.revision && !Task.isCancelled else { return }
                    do {
                        let translated = try await GameOnlineTranslator.shared.translate(
                            source, source: language, provider: provider, endpoint: endpoint)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard token == self.revision && !Task.isCancelled else { return }
                        guard !translated.isEmpty else { continue }
                        let key = self.cacheKey(profileID: profileID, language: language,
                                                source: source, provider: provider,
                                                endpointID: endpointID)
                        self.cache[key] = translated
                        for idx in page.blocks.indices where page.blocks[idx].original == source {
                            page.blocks[idx].chinese = translated
                        }
                        self.translatedCount = page.blocks.filter { $0.chinese != nil }.count
                        self.update(page: page, persistNow: self.translatedCount % 5 == 0)
                    } catch {
                        guard token == self.revision && !Task.isCancelled else { return }
                        self.lastError = error.localizedDescription
                        self.status = "在线 API 错误，停止本页后续请求；已有译文仍保留"
                        break
                    }
                }
                guard token == self.revision && !Task.isCancelled else { return }
                self.isTranslating = false
                self.persist()
                return
            }

            let session = TranslationSession(
                installedSource: Locale.Language(identifier: language),
                target: Locale.Language(identifier: "zh-Hans"))
            // Batch in reasonably sized groups; do not truncate the screen.
            // Each batch streams completed responses with client identifiers.
            for start in stride(from: 0, to: unknown.count, by: 24) {
                guard token == self.revision && !Task.isCancelled else { return }
                let group = Array(unknown[start..<min(start + 24, unknown.count)])
                let requests = group.enumerated().map { index, string in
                    TranslationSession.Request(sourceText: string,
                                               clientIdentifier: String(index))
                }
                do {
                    for try await response in session.translate(batch: requests) {
                        guard token == self.revision && !Task.isCancelled else { return }
                        guard let identifier = response.clientIdentifier,
                              let index = Int(identifier), group.indices.contains(index)
                        else { continue }
                        let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !translated.isEmpty else { continue }
                        let source = group[index]
                        let key = self.cacheKey(profileID: profileID, language: language,
                                                source: source, provider: provider,
                                                endpointID: endpointID)
                        self.cache[key] = translated
                        for idx in page.blocks.indices where page.blocks[idx].original == source {
                            page.blocks[idx].chinese = translated
                        }
                        self.translatedCount = page.blocks.filter { $0.chinese != nil }.count
                        self.update(page: page, persistNow: self.translatedCount % 5 == 0)
                    }
                } catch {
                    guard token == self.revision && !Task.isCancelled else { return }
                    self.lastError = error.localizedDescription
                    self.status = "部分菜单文字翻译失败；已完成的结果已保存"
                    break
                }
            }
            guard token == self.revision && !Task.isCancelled else { return }
            self.isTranslating = false
            self.status = "整屏检测 \(page.blocks.count) 条 · 已翻译 \(self.translatedCount) 条"
            self.persist()
        }
    }

    private func update(page: GameMenuPage, persistNow: Bool) {
        guard let index = savedPages.firstIndex(where: { $0.id == page.id }) else { return }
        savedPages[index] = page
        // Don't replace the user's view if they opened a different saved page.
        if currentPage?.id == page.id { currentPage = page }
        status = "整屏翻译中：\(translatedCount)/\(page.blocks.count)"
        if persistNow { persist() }
    }

    private func cacheKey(profileID: UUID, language: String, source: String,
                          provider: GameTranslationProvider,
                          endpointID: String) -> String {
        profileID.uuidString + "|" + provider.rawValue + "|" + endpointID
            + "|" + language + "|" + source
    }

    private func persist() {
        // Old cached translations can be recovered by revisiting saved pages.
        if cache.count > 1800 {
            for key in Array(cache.keys).prefix(600) {
                cache.removeValue(forKey: key)
            }
        }
        guard let data = try? JSONEncoder().encode(
            Saved(pages: savedPages, translationCache: cache)) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    var exportText: String {
        guard let page = currentPage else { return "" }
        return (["[\(page.gameName)] \(page.scannedAt.formatted(date: .numeric, time: .shortened))"]
                + page.blocks.map { "\($0.original)\n\($0.chinese ?? "［尚未翻译］")" })
            .joined(separator: "\n\n")
    }
}
