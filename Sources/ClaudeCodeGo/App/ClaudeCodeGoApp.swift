import SwiftUI

@main
struct ClaudeCodeGoApp: App {
    @StateObject private var proxyManager = ProxyManager()

    init() {
        GlobalErrorHandler.install()
        DispatchQueue.main.async {
            AppIconGenerator.setAppIcon()
        }
    }

    var body: some Scene {
        // Main window
        Window("ClaudeCode GO", id: "main") {
            ContentView()
                .environmentObject(proxyManager)
                .onAppear {
                    // Auto-start if there was a saved API key
                    if !proxyManager.apiKey.isEmpty {
                        proxyManager.startProxy()
                    } else if let envKey = ProcessInfo.processInfo.environment["CLAUDE_CODE_GO_API_KEY"], !envKey.isEmpty {
                        proxyManager.apiKey = envKey
                        proxyManager.startProxy()
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            // App menu
            CommandGroup(replacing: .appInfo) {
                Button("关于 ClaudeCode GO") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            // File menu
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar icon
        MenuBarExtra {
            StatusMenuView()
                .environmentObject(proxyManager)
        } label: {
            // Dynamic icon based on state
            if proxyManager.state.isRunning {
                Image(nsImage: AppIconGenerator.menuBarIcon())
            } else {
                Image(systemName: "circle.slash")
                    .foregroundStyle(.red)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
