import Foundation
import CoreFoundation

struct SubtitleMessage: Codable, Equatable {
    let original: String
    let translated: String
    let status: String
    let updatedAt: TimeInterval
    static let empty = SubtitleMessage(original: "", translated: "等待游戏对白…", status: "待启动", updatedAt: 0)
}

struct BroadcastTelemetry: Codable, Equatable {
    var frames: Int = 0
    var scans: Int = 0
    var hits: Int = 0
    var translated: Int = 0
    var failures: Int = 0
    var phase: String = "未启动"
    var detail: String = ""
    var updatedAt: TimeInterval = 0
}

/// Shared storage between the main application and ReplayKit upload extension.
/// An App Groups entitlement on *both* targets is mandatory for this IPC.
enum SharedSubtitles {
    static let groupID = "group.com.gamelingoai.offline"
    static let key = "liveSubtitle_v1"
    static let diagnosticsKey = "captureDiagnostics_v2"
    static let signal = CFNotificationName(rawValue: CFStringCreateWithCString(
        kCFAllocatorDefault, "com.gamelingoai.offline.subtitle.changed",
        CFStringBuiltInEncodings.UTF8.rawValue
    ))

    static var isGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }
    private static var store: UserDefaults? { UserDefaults(suiteName: groupID) }

    static var sourceLanguage: String {
        let code = store?.string(forKey: "sourceLanguage") ?? "ja"
        return ["ja", "en", "ko"].contains(code) ? code : "ja"
    }
    static func setSourceLanguage(_ language: String) {
        guard ["ja", "en", "ko"].contains(language) else { return }
        store?.set(language, forKey: "sourceLanguage")
    }
    static var scanArea: String {
        let value = store?.string(forKey: "scanArea") ?? "bottom"
        return ["bottom", "full"].contains(value) ? value : "bottom"
    }
    static func setScanArea(_ area: String) {
        guard ["bottom", "full"].contains(area) else { return }
        store?.set(area, forKey: "scanArea")
    }

    static func glossary() -> [String: String] {
        guard let content = store?.string(forKey: "glossaryText") else { return [:] }
        var result: [String: String] = [:]
        for line in content.split(separator: "\n") {
            let pieces = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if pieces.count == 2 && !pieces[0].isEmpty && !pieces[1].isEmpty {
                result[pieces[0]] = pieces[1]
            }
        }
        return result
    }
    static func glossaryText() -> String { store?.string(forKey: "glossaryText") ?? "" }
    static func setGlossary(_ text: String) { store?.set(text, forKey: "glossaryText") }

    static func save(_ message: SubtitleMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        store?.set(data, forKey: key)
        notify()
    }
    static func load() -> SubtitleMessage? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SubtitleMessage.self, from: data)
    }
    static func saveTelemetry(_ health: BroadcastTelemetry) {
        guard let data = try? JSONEncoder().encode(health) else { return }
        store?.set(data, forKey: diagnosticsKey)
        notify()
    }
    static func loadTelemetry() -> BroadcastTelemetry {
        guard let data = store?.data(forKey: diagnosticsKey),
              let health = try? JSONDecoder().decode(BroadcastTelemetry.self, from: data)
        else { return BroadcastTelemetry() }
        return health
    }
    private static func notify() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), signal, nil, nil, true)
    }
}
