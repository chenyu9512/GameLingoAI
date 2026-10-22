import Foundation
import CoreFoundation

struct SubtitleMessage: Codable, Equatable {
    let original: String
    let translated: String
    let status: String
    let updatedAt: TimeInterval

    static let empty = SubtitleMessage(original: "", translated: "等待游戏文字…", status: "等待广播", updatedAt: 0)
}

// Official app-extension-to-container IPC requires the App Groups entitlement.
// If the sideloading signer strips the entitlement, manual screenshot translation
// still works, but the broadcast's same-phone PiP subtitles will NOT work.
enum SharedSubtitles {
    static let groupID = "group.com.gamelingoai.offline"
    static let key = "liveSubtitle_v1"
    // Darwin CFNotificationName requires CFString, not a Swift String.
    // Construct it explicitly rather than relying on an unavailable bridge.
    static let signal = CFNotificationName(rawValue: CFStringCreateWithCString(
        kCFAllocatorDefault,
        "com.gamelingoai.offline.subtitle.changed",
        CFStringBuiltInEncodings.UTF8.rawValue
    ))

    static func glossary() -> [String: String] {
        guard let content = UserDefaults(suiteName: groupID)?.string(forKey: "glossaryText") else { return [:] }
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

    static func setGlossary(_ text: String) {
        UserDefaults(suiteName: groupID)?.set(text, forKey: "glossaryText")
    }

    static func save(_ message: SubtitleMessage) {
        guard let store = UserDefaults(suiteName: groupID),
              let data = try? JSONEncoder().encode(message) else { return }
        store.set(data, forKey: key)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), signal, nil, nil, true)
    }

    static func load() -> SubtitleMessage? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SubtitleMessage.self, from: data)
    }
}
