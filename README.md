# ClaudeCode Go

适用于 macOS 的原生图形化管理器，内嵌代理引擎（纯 Swift，无外部依赖），让 Claude Code 可以使用 OpenCode Go 的低成本模型。

通过将 Claude Code 的 Anthropic Messages API 请求转换为 OpenAI Chat Completions 格式，转发到 OpenCode Go，实现零修改、零依赖的代理服务。

## 功能

- **纯 Swift 实现** — 无需编译二进制，开箱即用
- **内嵌代理引擎** — 基于 NWListener 的 HTTP 服务器内嵌在 App 中，不依赖外部进程
- **手动模型切换** — 从 15 种模型中选择，切换自动重启
- **一键启停** — 开启/关闭/重启代理服务
- **实时日志** — 颜色编码的日志面板（INFO/WARN/ERROR）
- **菜单栏集成** — 状态图标 + 快捷菜单操作
- **思考回传修复** — 正确处理 DeepSeek/Kimi 的 thinking mode 验证

## 系统要求

- macOS 13.0+ (Ventura)

## 快速开始

```bash
# 运行
swift run

# 或在 Xcode 中打开
open Package.swift
```

启动后配置 Claude Code：
```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
export ANTHROPIC_AUTH_TOKEN=unused
claude
```

## 架构

```
┌──────────────────────────────────────────────────┐
│                    App (SwiftUI)                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ 主窗口    │ │ 菜单栏    │ │ ProxyManager     │  │
│  │ 状态/控制 │ │ 状态图标  │ │ (ViewModel)      │  │
│  │ 模型选择  │ │ 快捷菜单  │ │ 生命周期管理     │  │
│  │ 日志面板  │ │          │ │ 状态管理         │  │
│  └──────────┘ └──────────┘ └────────┬─────────┘  │
└─────────────────────────────────────┼────────────┘
                                      │
┌─────────────────────────────────────▼────────────┐
│              ProxyEngine (Pure Swift)              │
│                                                    │
│  ProxyServer (NWListener HTTP Server)              │
│    ↓ 解析 POST /v1/messages                        │
│  Transformer (Anthropic ↔ OpenAI 格式转换)        │
│    ↓ OpenAI Chat Completions 请求                  │
│  URLSession → OpenCode Go API                     │
│    ↓ SSE 流实时转换                                 │
│  ProxyServer → Claude Code                         │
└────────────────────────────────────────────────────┘
```

## 项目结构

```
Sources/ClaudeCodeGo/
├── App/
│   ├── ClaudeCodeGoApp.swift       # @main 入口 + 菜单栏
│   ├── AppIconGenerator.swift       # 自定义 App 图标
│   └── GlobalErrorHandler.swift     # 全局异常处理
├── Models/
│   ├── ProxyState.swift            # 状态枚举
│   ├── ModelOption.swift           # 模型定义
│   └── LogEntry.swift              # 日志条目
├── ProxyEngine/                    # ★ 核心代理引擎
│   ├── Types.swift                 # HTTP/HTTPS 类型定义
│   ├── Transformer.swift           # 格式转换（含思考回传修复）
│   └── ProxyServer.swift           # HTTP 服务器 + 请求处理
├── Services/
│   └── LogStore.swift              # 线程安全日志存储
├── ViewModels/
│   └── ProxyManager.swift          # 核心 ViewModel
└── Views/
    ├── ContentView.swift           # 主窗口
    ├── StatusIndicatorView.swift   # 状态指示器
    ├── ModelPickerView.swift       # 模型选择
    ├── ControlPanelView.swift      # 控制按钮
    ├── LogView.swift               # 实时日志面板
    └── StatusMenuView.swift        # 菜单栏菜单
```

## 模型列表

| 模型 ID | 名称 | 类别 |
|---------|------|------|
| glm-5.1 | GLM-5.1 | 强能力 |
| glm-5 | GLM-5 | 强能力 |
| deepseek-v4-pro | DeepSeek V4 Pro | 强能力 |
| kimi-k2.6 | **Kimi K2.6** (默认) | 均衡型 |
| deepseek-v4-flash | DeepSeek V4 Flash | 快速 |
| qwen3.6-plus | Qwen3.6 Plus | 快速 |
| minimax-m2.7 | MiniMax M2.7 | 超长上下文(1M) |
