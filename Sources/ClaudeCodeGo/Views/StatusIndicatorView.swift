import SwiftUI

/// Shows the current proxy state with a colored dot and port.
/// When running: port is read-only.
/// When stopped: port is editable with a pencil button.
struct StatusIndicatorView: View {
    let state: ProxyState
    @Binding var port: Int

    @State private var editText: String = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 2)
                )

            Text(state.displayText)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            if case .running = state {
                Text("端口：\(port)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else if !state.isTransitioning {
                HStack(spacing: 4) {
                    if isEditing {
                        TextField("", text: $editText)
                            .textFieldStyle(.plain)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 50)
                            .focused($focused)
                            .onSubmit { commit() }
                            .onAppear { focused = true }
                    } else {
                        Text("端口：\(port)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if isEditing {
                        Button("确定") { commit() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Button("取消") { cancel() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button {
                            editText = "\(port)"
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onChange(of: focused) { f in
            if !f && isEditing { cancel() }
        }
    }

    private func commit() {
        guard let p = Int(editText), p >= 1, p <= 65535 else {
            cancel()
            return
        }
        port = p
        isEditing = false
        editText = ""
    }

    private func cancel() {
        isEditing = false
        editText = ""
    }

    private var color: Color {
        switch state {
        case .stopped:
            return .red
        case .starting, .stopping:
            return .yellow
        case .running:
            return .green
        case .error:
            return .red
        }
    }
}
