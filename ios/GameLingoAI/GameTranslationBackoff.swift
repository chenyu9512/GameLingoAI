import Foundation

/// Main-actor translation retry gate. Time values use wall-clock seconds.
// A service failure must not spawn a new request for every changed OCR line.
struct GameTranslationBackoff {
    private static let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
    private(set) var consecutiveFailures = 0
    private(set) var nextAllowedAt: TimeInterval = 0

    mutating func failed(at now: TimeInterval) -> Int {
        consecutiveFailures = min(consecutiveFailures + 1, Self.delays.count)
        let delay = Self.delays[consecutiveFailures - 1]
        nextAllowedAt = now + delay
        return Int(delay * 1000)
    }

    func remainingMilliseconds(at now: TimeInterval) -> Int {
        let seconds = max(0, nextAllowedAt - now)
        return Int((seconds * 1000).rounded(.up))
    }

    mutating func reset() {
        consecutiveFailures = 0
        nextAllowedAt = 0
    }
}
