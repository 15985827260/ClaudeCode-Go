import SwiftUI

/// Main window content for ClaudeCode Go proxy manager.
struct ContentView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingAPIKeySheet = false
    @State private var showingAbout = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area
            HStack {
                Text("ClaudeCode GO")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Toggle("低功耗", isOn: $proxyManager.lowPowerMode)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .help("减少后台日志刷新和界面渲染")

                // API Key button
                Button {
                    showingAPIKeySheet = true
                } label: {
                    Label("API Key", systemImage: "key")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("设置 OpenCode API Key")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Status
                    StatusIndicatorView(state: proxyManager.state, port: $proxyManager.port)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Model picker + controls in one row
                    HStack(alignment: .top, spacing: 12) {
                        ModelPickerView(
                            selectedModel: $proxyManager.currentModel,
                            models: ModelOption.allModels,
                            onSwitch: { model in
                                proxyManager.switchModel(to: model)
                            }
                        )

                        ControlPanelView(
                            state: proxyManager.state,
                            onStart: { proxyManager.startProxy() },
                            onStop: { proxyManager.stopProxy() },
                            onRestart: { proxyManager.restartProxy() }
                        )
                    }
                    .padding(.horizontal)

                    // Log output
                    if !proxyManager.lowPowerMode {
                        Group {
                            if shouldRenderLogs {
                                LogView(
                                    logStore: proxyManager.logStore,
                                    onClear: { proxyManager.clearLogs() }
                                )
                            } else {
                                SuspendedLogView(
                                    message: suspendedLogMessage,
                                    onCopy: { proxyManager.logStore.copyToClipboard() },
                                    onClear: { proxyManager.clearLogs() }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 16)
            }

            Divider()

            // Footer
            HStack {
                Text("ClaudeCode GO v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("关于") {
                    showingAbout = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 540, height: proxyManager.lowPowerMode ? 380 : 620)
        .sheet(isPresented: $showingAPIKeySheet) {
            APIKeySettingsView(apiKey: $proxyManager.apiKey)
        }
        .alert("关于 ClaudeCode GO", isPresented: $showingAbout) {
            Button("确定") {}
        } message: {
            Text("""
            ClaudeCode GO v1.0

            用于管理 ClaudeCode GO 代理服务的 macOS 图形界面工具。

            通过将 Claude Code 的请求转发到 OpenCode Go，
            让你可以用低成本的开源模型替代 Claude API。

            支持的模型包括：GLM、Kimi、Qwen、DeepSeek、MiMo、MiniMax 等。
            """)
        }
        .onAppear {
            updateLogRendering()
        }
        .onChange(of: scenePhase) { _ in
            updateLogRendering()
        }
        .onChange(of: proxyManager.lowPowerMode) { _ in
            updateLogRendering()
        }
    }

    private var shouldRenderLogs: Bool {
        scenePhase == .active && !proxyManager.lowPowerMode
    }

    private var suspendedLogMessage: String {
        "窗口回到台前后继续显示日志"
    }

    private func updateLogRendering() {
        proxyManager.setLogRenderingActive(shouldRenderLogs)
    }
}

/// API Key configuration sheet.
struct APIKeySettingsView: View {
    @Binding var apiKey: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundColor(.accentColor)

            Text("OpenCode Go API Key")
                .font(.headline)

            Text("输入你的 OpenCode Go API Key。也可以设置 CLAUDE_CODE_GO_API_KEY 环境变量。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("保存") {
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
