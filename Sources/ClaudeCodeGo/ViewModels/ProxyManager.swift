import Foundation
import SwiftUI
import Combine

/// Central ViewModel that manages the embedded proxy server.
@MainActor
class ProxyManager: ObservableObject {
    // MARK: - Published State

    @Published var state: ProxyState = .stopped {
        didSet { objectWillChange.send() }
    }
    @Published var currentModel: ModelOption {
        didSet { saveSelectedModel() }
    }
    @Published var apiKey: String {
        didSet { saveAPIKey() }
    }
    @Published var port: Int = 3456 {
        didSet { savePort() }
    }

    let logStore = LogStore()
    private let proxyServer = ProxyServer()

    // MARK: - Init

    init() {
        LogStore.global = logStore
        // Restore last used model
        if let savedModelID = UserDefaults.standard.string(forKey: "selectedModelID"),
           let model = ModelOption.allModels.first(where: { $0.id == savedModelID }) {
            self.currentModel = model
        } else {
            self.currentModel = ModelOption.default
        }

        // Restore saved port preference
        if let savedPort = UserDefaults.standard.value(forKey: "proxyPort") as? Int,
           savedPort >= 1, savedPort <= 65535 {
            self.port = savedPort
        } else {
            self.port = 3456
        }
        if let envKey = ProcessInfo.processInfo.environment["CLAUDE_CODE_GO_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
        } else if let savedKey = UserDefaults.standard.string(forKey: "claudecode_go_api_key"), !savedKey.isEmpty {
            self.apiKey = savedKey
        } else {
            self.apiKey = ""
        }

        // Set up server callbacks
        proxyServer.onLog = { [weak self] line in
            DispatchQueue.main.async {
                self?.logStore.appendRawLine(line)
            }
        }
        proxyServer.onStateChange = { [weak self] running in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = running ? .running(port: self.port) : .stopped
            }
        }
    }

    // MARK: - Public API

    func startProxy() {
        guard !state.isRunning, !state.isTransitioning else { return }

        // Ensure API key
        if apiKey.isEmpty {
            logStore.append(level: .error, message: "API Key 未设置。请点击工具栏的「API Key」按钮进行配置")
            state = .error("API Key 未设置")
            return
        }

        state = .starting
        logStore.append(level: .info, message: "正在启动代理服务...")
        logStore.append(level: .info, message: "模型: \(currentModel.name) (\(currentModel.id))")

        do {
            try proxyServer.start(
                port: port,
                apiKey: apiKey,
                modelID: currentModel.id,
                temperature: 0.7,
                maxTokens: 4096
            )
        } catch {
            logStore.append(level: .error, message: "启动失败: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    func stopProxy() {
        guard state.isRunning || state.isTransitioning else { return }
        state = .stopping
        logStore.append(level: .info, message: "正在停止代理服务...")
        proxyServer.stop()
        state = .stopped
    }

    func restartProxy() {
        if state.isRunning || state.isTransitioning {
            logStore.append(level: .info, message: "正在重启代理服务...")
            proxyServer.stop()
            state = .stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startProxy()
            }
        } else {
            startProxy()
        }
    }

    func switchModel(to model: ModelOption) {
        guard model != currentModel else { return }
        logStore.append(level: .info, message: "切换模型: \(currentModel.name) → \(model.name)")
        currentModel = model

        if proxyServer.isActive {
            // Hot-swap model at runtime — no restart needed
            proxyServer.updateModel(model.id)
            logStore.append(level: .info, message: "模型已切换，下次请求生效")
        }
    }

    func clearLogs() {
        logStore.clear()
    }

    // MARK: - Private

    private func saveSelectedModel() {
        UserDefaults.standard.set(currentModel.id, forKey: "selectedModelID")
    }

    private func savePort() {
        UserDefaults.standard.set(port, forKey: "proxyPort")
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        UserDefaults.standard.set(apiKey, forKey: "claudecode_go_api_key")
    }
}
