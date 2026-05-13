import SwiftUI

/// Start / Stop / Restart buttons.
struct ControlPanelView: View {
    let state: ProxyState
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("操作", systemImage: "gearshape")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Start / Stop toggle
                if state.isRunning {
                    PanelButton(
                        title: "关闭",
                        icon: "stop.fill",
                        color: .red,
                        action: onStop,
                        disabled: state.isTransitioning
                    )
                } else {
                    PanelButton(
                        title: "开启",
                        icon: "play.fill",
                        color: .green,
                        action: onStart,
                        disabled: state.isTransitioning
                    )
                }

                // Restart (only enabled when running or stopped)
                PanelButton(
                    title: "重启",
                    icon: "arrow.clockwise",
                    color: .blue,
                    action: onRestart,
                    disabled: state.isTransitioning
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

/// A styled action button.
struct PanelButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    var disabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 80)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(disabled ? Color.gray : color)
        .disabled(disabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
