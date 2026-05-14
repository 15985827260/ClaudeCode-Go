import Foundation
import AppKit

/// Thread-safe store for log entries with a maximum capacity.
/// Automatically trims old entries when the limit is reached.
class LogStore: ObservableObject {
    @Published var entries: [LogEntry] = []

    /// Global/shared instance set up by ProxyManager, so uncaught
    /// exception handlers can write to it even when no ProxyManager
    /// is in scope.
    static weak var global: LogStore?

    private let maxEntries: Int
    private let queue = DispatchQueue(label: "com.claudecode.go.logstore", qos: .utility)
    private var pendingEntries: [LogEntry] = []
    private var flushScheduled = false
    private var rendersUpdates = true
    private var usesLowPowerMode = true

    init(maxEntries: Int = 500) {
        self.maxEntries = maxEntries
    }

    /// Append a new log entry (thread-safe).
    func append(level: LogEntry.LogLevel, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        var shouldScheduleFlush = false
        var flushDelay: TimeInterval = 0.1

        queue.sync {
            self.pendingEntries.append(entry)
            if self.rendersUpdates && !self.flushScheduled {
                self.flushScheduled = true
                shouldScheduleFlush = true
                flushDelay = self.usesLowPowerMode ? 0.5 : 0.1
            }
        }

        if shouldScheduleFlush {
            DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay) { [weak self] in
                self?.flushPendingEntries()
            }
        }
    }

    /// Append from a raw log line.
    func appendRawLine(_ line: String) {
        // Try to parse structured log: "LEVEL message"
        let upper = line.uppercased()
        let level: LogEntry.LogLevel
        if upper.contains("ERROR") || upper.contains("FAILED") {
            level = .error
        } else if upper.contains("WARN") {
            level = .warn
        } else if upper.contains("DEBUG") {
            level = .debug
        } else {
            level = .info
        }
        append(level: level, message: line)
    }

    /// Clear all log entries.
    func clear() {
        queue.sync {
            pendingEntries.removeAll()
            flushScheduled = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    /// Number of entries.
    var count: Int {
        entries.count
    }

    /// Return all log entries formatted as text (for clipboard copy).
    func formattedText() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let snapshot = entriesSnapshot(includePending: true)
        return snapshot.map { entry in
            "[\(df.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    /// Copy all logs to clipboard.
    func copyToClipboard() {
        let text = formattedText()
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func setRenderingEnabled(_ enabled: Bool) {
        var shouldFlush = false
        queue.sync {
            rendersUpdates = enabled
            if enabled, !pendingEntries.isEmpty, !flushScheduled {
                flushScheduled = true
                shouldFlush = true
            }
        }

        if shouldFlush {
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingEntries()
            }
        }
    }

    func setLowPowerMode(_ enabled: Bool) {
        queue.sync {
            usesLowPowerMode = enabled
        }
    }

    private func flushPendingEntries() {
        var batch: [LogEntry] = []
        queue.sync {
            guard rendersUpdates else {
                flushScheduled = false
                return
            }
            batch = pendingEntries
            pendingEntries.removeAll()
            flushScheduled = false
        }

        guard !batch.isEmpty else { return }

        entries.append(contentsOf: batch)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func entriesSnapshot(includePending: Bool) -> [LogEntry] {
        guard includePending else { return entries }

        var pending: [LogEntry] = []
        queue.sync {
            pending = pendingEntries
        }

        let combined = entries + pending
        guard combined.count > maxEntries else { return combined }
        return Array(combined.suffix(maxEntries))
    }
}
