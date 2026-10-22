import Foundation
import Combine
import CoreFoundation

private func refreshOnDarwinSignal(_ center: CFNotificationCenter?,
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
                                        refreshOnDarwinSignal, SharedSubtitles.signal.rawValue, nil,
                                        .deliverImmediately)
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
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
        let data = SharedSubtitles.loadTelemetry()
        if data != telemetry { telemetry = data }
        guard let message = SharedSubtitles.load() else { return }
        guard message.updatedAt > current.updatedAt else { return }
        current = message
        if !message.original.isEmpty && !message.translated.isEmpty {
            history.insert(message, at: 0)
        }
        if history.count > 100 { history.removeLast(history.count - 100) }
    }
}
