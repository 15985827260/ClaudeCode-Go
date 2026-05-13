import SwiftUI

/// Menu bar dropdown content shown when clicking the menu bar icon.
struct StatusMenuView: View {
    @EnvironmentObject var proxyManager: ProxyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                Text("ClaudeCode GO")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Divider()

            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(proxyManager.state.displayText)
                    .font(.caption)
            }
            .padding(.vertical, 2)

            // Model switching submenu
            Menu {
                ForEach(ModelCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(ModelOption.allModels.filter { $0.category == category }) { model in
                            Button {
                                proxyManager.switchModel(to: model)
                            } label: {
                                HStack {
                                    Text(model.name)
                                    if model.id == proxyManager.currentModel.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "cpu")
                        .font(.caption)
                    Text(proxyManager.currentModel.name)
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)

            Divider()

            // Start / Stop toggle
            if proxyManager.state.isRunning {
                Button {
                    proxyManager.stopProxy()
                } label: {
                    Label("关闭代理", systemImage: "stop.fill")
                }
                .keyboardShortcut("s", modifiers: .command)
            } else {
                Button {
                    proxyManager.startProxy()
                } label: {
                    Label("开启代理", systemImage: "play.fill")
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            // Restart
            Button {
                proxyManager.restartProxy()
            } label: {
                Label("重启代理", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            // Show window
            Button {
                if let window = NSApp.windows.first(where: { $0.title == "ClaudeCode GO" }) {
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("显示窗口", systemImage: "macwindow")
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            // Quit
            Button {
                // Stop proxy first, then quit
                if proxyManager.state.isRunning {
                    proxyManager.stopProxy()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApp.terminate(nil)
                }
            } label: {
                Label("退出", systemImage: "xmark")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch proxyManager.state {
        case .stopped: return .red
        case .starting, .stopping: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }
}
