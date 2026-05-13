// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCodeGo",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCodeGo",
            path: "Sources/ClaudeCodeGo"
        )
    ]
)
