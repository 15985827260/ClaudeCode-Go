import SwiftUI

/// Real-time scrolling log view.
struct LogView: View {
    @ObservedObject var logStore: LogStore
    let onClear: () -> Void

    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label("日志输出", systemImage: "text.alignleft")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Toggle("自动滚动", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .controlSize(.small)

                Button("复制日志") {
                    logStore.copyToClipboard()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .help("复制所有日志到剪贴板")

                Button("清空日志") {
                    onClear()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .help("清空所有日志")
            }

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(logStore.entries.reversed(), id: \.id) { entry in
                            LogLineView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: logStore.entries.count) { _ in
                    if autoScroll, let last = logStore.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if logStore.entries.isEmpty {
                    Text("暂无日志")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

/// Lightweight placeholder used while the app is not in the foreground.
struct SuspendedLogView: View {
    let message: String
    let onCopy: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("日志输出", systemImage: "text.alignleft")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Button("复制日志") {
                    onCopy()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .help("复制所有日志到剪贴板")

                Button("清空日志") {
                    onClear()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .help("清空所有日志")
            }

            Text(message)
                .frame(maxWidth: .infinity, minHeight: 120)
                .font(.caption)
                .foregroundColor(.secondary)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

/// A single log line with timestamp and color-coded level.
struct LogLineView: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)

            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(levelColor)
                .frame(width: 44, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(entry.level == .error ? .red : .primary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(
            entry.level == .error
                ? Color.red.opacity(0.05)
                : Color.clear
        )
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
