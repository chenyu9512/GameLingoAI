import Foundation

/// Local diagnostic event log. No captured frames, OCR text, translation,
/// URLs, tokens or user-provided strings are written to this log.
final class GameDiagnosticLog {
    static let shared = GameDiagnosticLog()
    private let queue = DispatchQueue(label: "GameLingo.Diagnostics.IO", qos: .utility)
    private let maximumBytes = 512_000
    private let directory: URL
    private var lastMetricAt: TimeInterval = 0
    private var lastDecisionAt: [Int: TimeInterval] = [:]

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        directory = root.appendingPathComponent("GameLingoDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var active: URL { directory.appendingPathComponent("events.jsonl") }
    private var previous: URL { directory.appendingPathComponent("events.previous.jsonl") }

    func event(_ name: String, metrics: [String: Int] = [:]) {
        // Deliberately strict schema: caller-provided text never reaches disk.
        let allowed = Set(["capture_start", "capture_stop", "capture_failure",
                           "capture_interrupted", "ocr_sample", "pipeline_skip", "translation_failure",
                           "translation_complete", "diagnostic_export",
                           "startup_vision", "startup_translation", "startup_ready",
                           "first_ocr", "first_translation", "pip_startup"])
        guard allowed.contains(name) else { return }
        queue.async {
            if name == "ocr_sample" {
                let now = Date().timeIntervalSince1970
                guard now - self.lastMetricAt >= 5 else { return }
                self.lastMetricAt = now
            }
            if name == "pipeline_skip" {
                // Diagnostics stay bounded even when OCR processes many frames.
                // Sample independently by reason so a later failure isn't hidden.
                let now = Date().timeIntervalSince1970
                let reason = metrics["reason_code"] ?? 0
                guard now - (self.lastDecisionAt[reason] ?? 0) >= 5 else { return }
                self.lastDecisionAt[reason] = now
            }
            let accepted = ["ocr_ms", "queue_ms", "dropped", "confidence_pct",
                            "rejected_lines", "bottom_ms", "translation_ms",
                            "capture_to_translation_ms", "failure_count", "accurate_rescans",
                            "sampled_out", "ocr_backend", "confidence_available",
                             "ocr_requested_backend", "ocr_paddle_available", "paddle_ms",
                             "configured_auto", "reason_code", "retry_after_ms",
                             "provider_code", "error_domain_code", "error_code", "error_negative",
                             "cold_vision_ms", "cold_translation_ms", "cold_total_ms",
                             "context_source_uses",
                             "language_state", "first_ocr_ms", "first_translation_ms",
                             "pip_start_ms", "pip_result", "accurate_suppressed"]
            let clean = metrics.filter { accepted.contains($0.key) }
                .mapValues { max(0, min($0, 600_000)) }
            let record = Record(timestamp: ISO8601DateFormatter().string(from: Date()),
                                event: name, metrics: clean)
            guard let data = try? JSONEncoder().encode(record) else { return }
            self.append(data + Data([10]))
        }
    }

    func export(completion: @escaping (URL?) -> Void) {
        queue.async {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("GameLingo-diagnostics-\(UUID().uuidString).jsonl")
            var data = (try? Data(contentsOf: self.previous)) ?? Data()
            data.append((try? Data(contentsOf: self.active)) ?? Data())
            do {
                try data.write(to: destination, options: .atomic)
                DispatchQueue.main.async { completion(destination) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    func clear(completion: @escaping () -> Void) {
        queue.async {
            try? FileManager.default.removeItem(at: self.active)
            try? FileManager.default.removeItem(at: self.previous)
            self.lastMetricAt = 0
            self.lastDecisionAt.removeAll()
            DispatchQueue.main.async { completion() }
        }
    }

    private func append(_ data: Data) {
        let size = (try? active.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size + data.count > maximumBytes {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: active, to: previous)
        }
        if !FileManager.default.fileExists(atPath: active.path) {
            FileManager.default.createFile(atPath: active.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: active) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { }
    }

    private struct Record: Codable {
        let timestamp: String
        let event: String
        let metrics: [String: Int]
    }
}
