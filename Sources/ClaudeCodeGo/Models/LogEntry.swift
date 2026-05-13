import Foundation

/// A single log entry from the proxy process or app itself.
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String, Equatable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "primary"
            case .warn: return "orange"
            case .error: return "red"
            }
        }
    }
}
