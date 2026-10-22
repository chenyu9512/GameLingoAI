import Foundation
import Combine
import CoreFoundation

private func onDarwinSubtitle(_ center: CFNotificationCenter?,
                              _ observer: UnsafeMutableRawPointer?,
                              _ name: CFNotificationName?,
                              _ object: UnsafeRawPointer?,
                              _ userInfo: CFDictionary?) {
    guard let observer else { return }
    let inbox = Unmanaged<SubtitleInbox>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async { inbox.refresh() }
}

final class SubtitleInbox: ObservableObject {
    @Published private(set) var current: SubtitleMessage = .empty
    @Published private(set) var history: [SubtitleMessage] = []
    @Published private(set) var telemetry = BroadcastTelemetry()
    private var timer: Timer?

    init() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        onDarwinSubtitle, SharedSubtitles.signal.rawValue, nil,
                                        .deliverImmediately)
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                           Unmanaged.passUnretained(self).toOpaque(),
                                           SharedSubtitles.signal, nil)
    }

    func refresh() {
        let newTelemetry = SharedSubtitles.loadTelemetry()
        if newTelemetry != telemetry { telemetry = newTelemetry }
        guard let message = SharedSubtitles.load() else { return }
        guard message.updatedAt > current.updatedAt else { return }
        current = message
        if !message.original.isEmpty, !message.translated.isEmpty {
            history.insert(message, at: 0)
            if history.count > 100 { history.removeLast(history.count - 100) }
        }
    }
}
