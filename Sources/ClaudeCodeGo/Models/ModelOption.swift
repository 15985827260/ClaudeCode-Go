import Foundation

/// Represents a selectable model option.
struct ModelOption: Identifiable, Codable, Equatable, Hashable {
    let id: String       // model_id sent to API
    let name: String     // display name
    let description: String
    let category: ModelCategory
    let supportsStreaming: Bool

    static let `default` = ModelOption(
        id: "kimi-k2.6",
        name: "Kimi K2.6",
        description: "默认推荐，均衡性能与速度",
        category: .balanced,
        supportsStreaming: true
    )
}

enum ModelCategory: String, CaseIterable, Codable {
    case powerful = "强能力"
    case balanced = "均衡型"
    case fast = "快速"
    case longContext = "超长上下文"

    var color: String {
        switch self {
        case .powerful: return "purple"
        case .balanced: return "blue"
        case .fast: return "green"
        case .longContext: return "orange"
        }
    }
}

// MARK: - Available Models

extension ModelOption {
    static let allModels: [ModelOption] = [
        // 强能力
        ModelOption(id: "glm-5.1", name: "GLM-5.1", description: "最强能力，适合复杂任务", category: .powerful, supportsStreaming: true),
        ModelOption(id: "glm-5", name: "GLM-5", description: "强推理能力", category: .powerful, supportsStreaming: true),
        ModelOption(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", description: "DeepSeek 专业版", category: .powerful, supportsStreaming: true),
        ModelOption(id: "mimo-v2.5-pro", name: "MiMo V2.5 Pro", description: "MiMo 专业增强版", category: .powerful, supportsStreaming: true),

        // 均衡型
        ModelOption(id: "kimi-k2.6", name: "Kimi K2.6", description: "默认推荐，均衡性能与速度", category: .balanced, supportsStreaming: true),
        ModelOption(id: "kimi-k2.5", name: "Kimi K2.5", description: "Kimi 上代版本", category: .balanced, supportsStreaming: true),
        ModelOption(id: "mimo-v2.5", name: "MiMo V2.5", description: "MiMo 标准版", category: .balanced, supportsStreaming: true),
        ModelOption(id: "mimo-v2-pro", name: "MiMo V2 Pro", description: "MiMo V2 专业版", category: .balanced, supportsStreaming: true),
        ModelOption(id: "mimo-v2-omni", name: "MiMo V2 Omni", description: "MiMo 全能版", category: .balanced, supportsStreaming: true),

        // 快速
        ModelOption(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", description: "快速响应，适合日常对话", category: .fast, supportsStreaming: true),
        ModelOption(id: "qwen3.6-plus", name: "Qwen3.6 Plus", description: "快速，低延迟", category: .fast, supportsStreaming: true),
        ModelOption(id: "qwen3.5-plus", name: "Qwen3.5 Plus", description: "经济实惠，速度优先", category: .fast, supportsStreaming: true),

        // 超长上下文
        ModelOption(id: "minimax-m2.7", name: "MiniMax M2.7", description: "超长上下文(1M)，Anthropic 原生格式", category: .longContext, supportsStreaming: true),
        ModelOption(id: "minimax-m2.5", name: "MiniMax M2.5", description: "长上下文，Anthropic 原生格式", category: .longContext, supportsStreaming: true),
    ]
}
