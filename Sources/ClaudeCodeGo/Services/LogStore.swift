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

    init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }

    /// Append a new log entry (thread-safe).
    func append(level: LogEntry.LogLevel, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        queue.sync {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.dropFirst(self.entries.count - self.maxEntries))
            }
        }
        // Publish on main thread
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
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
        return entries.map { entry in
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
}
