# CLAUDE.md

本文件指导 Claude Code 在该仓库中协作。

## 构建与运行

```bash
swift build                          # 构建
swift run                            # 构建并运行（打开 macOS 图形界面）
./build-app.sh                       # 构建并打包成 .app
```

代理服务器默认监听端口 **3456**。

### 环境变量

- `CLAUDE_CODE_GO_API_KEY` — OpenCode API 的密钥。设置后启动时自动开启代理。

### Claude Code 集成

启动 App 后，在终端配置 Claude Code：

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
export ANTHROPIC_AUTH_TOKEN=unused
claude
```

## 项目结构

```
ClaudeCodeGo/
├── Sources/ClaudeCodeGo/    # 全部 Swift 源码
│   ├── App/                 # 入口 + 图标 + 异常处理
│   ├── Models/              # 数据模型
│   ├── ProxyEngine/         # ★ 核心代理引擎
│   ├── Services/            # 日志服务
│   ├── ViewModels/          # ProxyManager
│   └── Views/               # SwiftUI 界面
├── Package.swift            # SPM 包定义
├── README.md                # 中文文档
├── CLAUDE.md                # 项目指引
├── build-app.sh             # 一键打包 .app
└── .gitignore               # 排除构建产物
```

## 架构

纯 Swift 代理服务器内嵌于 macOS SwiftUI App，无外部依赖。

```
App (SwiftUI)                          ProxyManager (ViewModel)
  ├── ContentView / ControlPanelView    管理 ProxyServer 生命周期
  ├── ModelPickerView                   转发日志/状态回调
  └── LogView                           读取 LogStore

ProxyEngine (纯 Swift，无依赖)
  ├── ProxyServer        NWListener 的 HTTP 服务器
  │                       路由 POST /v1/messages → Transformer
  │                       处理流式 (SSE) 与非流式请求
  ├── Transformer        Anthropic Messages API ↔ OpenAI Chat Completions
  │                       请求/响应/流式块转换
  │                       DeepSeek/Kimi thinking mode 修复
  └── Types              两种 API 的所有 Codable 类型
                          包含 AnyCodable 处理动态 JSON
```

### 双模式流程

1. **非原生模型**（大部分）：Anthropic 请求 → `Transformer` → OpenAI 请求 → opencode.ai → OpenAI 响应 → `Transformer` → Anthropic 响应
2. **Anthropic 原生模型**（minimax-*）：请求直接代理到 opencode.ai 的 `/v1/messages` 接口

### 模型分类

| 模型 ID 前缀 | 格式 | 说明 |
|---|---|---|
| `minimax-` | Anthropic 原生 | 通过 `/v1/messages` 原始代理 |
| 其他 | OpenAI 转换 | 通过 `Transformer` 转换 |

### 流式处理

- 立即发送 SSE 头，防止 Claude Code 的 6 秒超时
- 3 秒心跳保活
- OpenAI 流式块逐块转换为 Anthropic SSE 事件（`content_block_start`、`content_block_delta`、`content_block_stop`、`message_delta`）
- `transformStreamChunk` 函数处理推理内容 → thinking 块、文本增量、工具调用增量和最终用量
