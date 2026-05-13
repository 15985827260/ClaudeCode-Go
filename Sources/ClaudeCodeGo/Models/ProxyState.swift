import Foundation

/// Represents the current state of the proxy process.
enum ProxyState: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case stopping
    case error(String)

    var displayText: String {
        switch self {
        case .stopped:
            return "已停止"
        case .starting:
            return "启动中…"
        case .running:
            return "运行中"
        case .stopping:
            return "关闭中…"
        case .error(let msg):
            return "错误: \(msg)"
        }
    }

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    var isTransitioning: Bool {
        switch self {
        case .starting, .stopping: true
        default: false
        }
    }
}
