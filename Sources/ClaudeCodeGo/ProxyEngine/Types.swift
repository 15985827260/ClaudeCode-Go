import Foundation

// MARK: - Anthropic Messages API Types

struct AnthropicRequest: Codable {
    let model: String
    let maxTokens: Int?
    let system: SystemContent?
    let messages: [AnthropicMessage]
    let stream: Bool?
    let tools: [AnthropicTool]?
    let temperature: Double?
    let topP: Double?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream, tools, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
    }
}

/// System prompt: can be a string or an array of content blocks.
enum SystemContent: Codable {
    case string(String)
    case blocks([SystemBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let blocks = try? container.decode([SystemBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    var text: String {
        switch self {
        case .string(let str): return str
        case .blocks(let blocks):
            return blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
    }
}

struct SystemBlock: Codable {
    let type: String
    let text: String
    let cacheControl: CacheControl?

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

struct CacheControl: Codable {
    let type: String
}

struct AnthropicMessage: Codable {
    let role: String
    let content: MessageContent
}

/// Message content: can be a string or an array of content blocks.
enum MessageContent: Codable {
    case string(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let blocks = try? container.decode([ContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    var textContent: String {
        switch self {
        case .string(let str): return str
        case .blocks(let blocks):
            return blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
    }

    var contentBlocks: [ContentBlock] {
        switch self {
        case .string(let str):
            return [ContentBlock(type: "text", text: str)]
        case .blocks(let blocks):
            return blocks
        }
    }
}

struct ContentBlock: Codable {
    let type: String
    var text: String?
    var id: String?          // tool_use
    var name: String?        // tool_use
    var input: [String: AnyCodable]? // tool_use
    var thinking: String?    // thinking
    var signature: String?   // thinking
    var toolUseId: String?   // tool_result
    var content: ContentBlockContent? // tool_result
    var isError: Bool?       // tool_result

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, thinking, signature, content
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    /// Text from tool_result content.
    var toolResultText: String {
        guard let content else { return "" }
        switch content {
        case .string(let str): return str
        case .blocks(let blocks):
            return blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
    }
}

/// For tool_result content (can be string or array of blocks).
enum ContentBlockContent: Codable {
    case string(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let blocks = try? container.decode([ContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

struct AnthropicTool: Codable {
    let name: String
    let description: String?
    let inputSchema: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct AnthropicResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }
}

struct Usage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    init(inputTokens: Int, outputTokens: Int, cacheCreationInputTokens: Int? = nil, cacheReadInputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - SSE Event types for streaming

struct SSEEvent: Codable {
    let type: String
    let message: AnthropicResponse?
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: Delta?
    let usage: Usage?

    init(type: String, message: AnthropicResponse? = nil, index: Int? = nil, contentBlock: ContentBlock? = nil, delta: Delta? = nil, usage: Usage? = nil) {
        self.type = type
        self.message = message
        self.index = index
        self.contentBlock = contentBlock
        self.delta = delta
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case type, message, index, contentBlock = "content_block", delta, usage
    }
}

struct Delta: Codable {
    let type: String?
    let text: String?
    let thinking: String?
    let partialJson: String?
    let stopReason: String?

    init(type: String? = nil, text: String? = nil, thinking: String? = nil, partialJson: String? = nil, stopReason: String? = nil) {
        self.type = type
        self.text = text
        self.thinking = thinking
        self.partialJson = partialJson
        self.stopReason = stopReason
    }

    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case partialJson = "partial_json"
        case stopReason = "stop_reason"
    }
}

// MARK: - OpenAI Chat Completions API Types

struct OpenAIRequest: Codable {
    let model: String
    var messages: [OpenAIMessage]
    var stream: Bool
    var streamOptions: StreamOptions?
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    var reasoningEffort: String?
    var tools: [OpenAITool]?
    var thinking: ThinkingConfig?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, topP, tools, thinking
        case streamOptions = "stream_options"
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }
}

enum ThinkingConfig: Codable {
    case enabled
    case disabled
    case budget(Int)

    var isDisabled: Bool {
        if case .disabled = self { true } else { false }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enabled:
            try container.encode(["type": "enabled"])
        case .disabled:
            try container.encode(["type": "disabled"])
        case .budget(let tokens):
            try container.encode([
                "type": AnyCodable("enabled"),
                "budget_tokens": AnyCodable(tokens)
            ])
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            let type = dict["type"]?.value as? String
            if type == "disabled" {
                self = .disabled
            } else if let budget = dict["budget_tokens"]?.value as? Int {
                self = .budget(budget)
            } else {
                self = .enabled
            }
        } else {
            self = .disabled
        }
    }
}


struct StreamOptions: Codable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    var content: String
    var reasoningContent: String?
    var toolCalls: [OpenAIToolCall]?
    var toolCallId: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    init(role: String = "assistant", content: String = "", reasoningContent: String? = nil, toolCalls: [OpenAIToolCall]? = nil, toolCallId: String? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Streaming deltas may omit `role` after the first chunk
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "assistant"
        // Streaming deltas (e.g. DeepSeek reasoning_content chunks) may have null content
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        toolCalls = try container.decodeIfPresent([OpenAIToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct OpenAIToolCall: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: OpenAIFunctionCall
}

struct OpenAIFunctionCall: Codable {
    let name: String?
    let arguments: String?
}

struct OpenAITool: Codable {
    let type: String
    let function: OpenAIFunctionDef
}

struct OpenAIFunctionDef: Codable {
    let name: String
    let description: String?
    let parameters: [String: AnyCodable]?
}

struct OpenAIResponse: Codable {
    let id: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
    let model: String?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage?
    let delta: OpenAIMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message, delta
        case finishReason = "finish_reason"
    }
}

struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int?
    let promptCacheHitTokens: Int?
    let promptCacheMissTokens: Int?

    init(promptTokens: Int, completionTokens: Int, totalTokens: Int? = nil, promptCacheHitTokens: Int? = nil, promptCacheMissTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptCacheHitTokens = "prompt_cache_hit_tokens"
        case promptCacheMissTokens = "prompt_cache_miss_tokens"
    }
}

struct OpenAIStreamChunk: Codable {
    let id: String?
    let choices: [OpenAIStreamChoice]?
    let usage: OpenAIUsage?
    let model: String?
}

struct OpenAIStreamChoice: Codable {
    let index: Int?
    let delta: OpenAIMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

// MARK: - Helper

/// Type-erased Codable wrapper for arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let dbl = try? container.decode(Double.self) { value = dbl }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value } }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr.map { $0.value } }
        else { value = [String: Any]() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let int = value as? Int { try container.encode(int) }
        else if let dbl = value as? Double { try container.encode(dbl) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        }
        else if let arr = value as? [Any] {
            try container.encode(arr.map { AnyCodable($0) })
        }
        else { try container.encodeNil() }
    }
}
