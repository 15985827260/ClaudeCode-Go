import Foundation
import OSLog

/// Installs global error handlers so that uncaught exceptions and
/// system-level errors get logged to LogStore.
enum GlobalErrorHandler {
    private static let logger = Logger(subsystem: "com.claudecode.go", category: "GlobalErrorHandler")

    /// Install uncaught exception handler and ignore SIGPIPE.
    ///
    /// Note: Swift fatal errors (force unwraps, array bounds) and POSIX
    /// signals (SIGSEGV, SIGABRT) cannot be safely caught from Swift —
    /// those go through the Swift runtime and crash the process directly.
    /// The uncaught exception handler covers Objective-C exceptions that
    /// may come through AppKit/Foundation APIs.
    static func install() {
        // Objective-C uncaught exceptions (e.g. from AppKit/Foundation)
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(10).joined(separator: "\n")
            let message = """
            ⚠️ 未捕获异常: \(exception.name.rawValue)
            原因: \(exception.reason ?? "未知")
            调用栈:
            \(stack)
            """
            LogStore.global?.append(level: .error, message: message)
            GlobalErrorHandler.logger.error("\(message, privacy: .public)")
        }

        // Ignore SIGPIPE silently — common with network connections that
        // close unexpectedly. The proxy code already handles write errors.
        signal(SIGPIPE, SIG_IGN)
    }
}
