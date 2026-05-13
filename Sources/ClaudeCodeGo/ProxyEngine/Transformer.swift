import Foundation
import OSLog

/// Converts between Anthropic Messages API and OpenAI Chat Completions formats.
class Transformer {
    private let logger = Logger(subsystem: "com.claudecode.go.proxy", category: "Transformer")

    // MARK: - Request: Anthropic → OpenAI

    /// Check if ANY assistant message in the history has thinking blocks.
    func hasThinkingBlocks(in messages: [AnthropicMessage]) -> Bool {
        for msg in messages where msg.role == "assistant" {
            if case .blocks(let blocks) = msg.content {
                if blocks.contains(where: { $0.type == "thinking" }) {
                    return true
                }
            }
        }
        return false
    }

    /// Check if a model requires Anthropic-native format (MiniMax).
    func isAnthropicNativeModel(_ modelID: String) -> Bool {
        modelID.hasPrefix("minimax-")
    }

    /// Transform an Anthropic request to OpenAI format.
    func transformRequest(
        _ anthropicReq: AnthropicRequest,
        modelID: String,
        temperature: Double?,
        maxTokens: Int?
    ) -> OpenAIRequest {
        var messages = [OpenAIMessage]()

        // 1. System prompt → system role message
        let systemText = anthropicReq.system?.text ?? ""
        if !systemText.isEmpty {
            messages.append(OpenAIMessage(role: "system", content: systemText))
        }

        // 2. Check if any assistant message has thinking blocks
        let hasThinking = hasThinkingBlocks(in: anthropicReq.messages)

        // 3. Transform each message
        for msg in anthropicReq.messages {
            let openaiMsgs = transformMessage(msg, hasThinkingInHistory: hasThinking, modelID: modelID)
            messages.append(contentsOf: openaiMsgs)
        }

        // 4. Build request
        var req = OpenAIRequest(
            model: modelID,
            messages: messages,
            stream: anthropicReq.stream ?? false,
            temperature: temperature ?? anthropicReq.temperature,
            topP: anthropicReq.topP,
            maxTokens: maxTokens ?? anthropicReq.maxTokens
        )

        // 5. Streaming options
        if req.stream {
            req.streamOptions = StreamOptions(includeUsage: true)
        }

        // 6. Thinking mode handling
        let isDeepSeek = modelID.hasPrefix("deepseek-")
        if hasThinking {
            // History has thinking blocks → enable thinking mode
            // DeepSeek and other models need explicit thinking config
            if isDeepSeek {
                req.thinking = .enabled
                req.reasoningEffort = "high"
            } else {
                req.thinking = .enabled
            }
        } else if isDeepSeek {
            // DeepSeek always operates in thinking mode internally
            // If no thinking blocks in history, we MUST explicitly disable
            // so DeepSeek doesn't require reasoning_content we can't provide
            req.thinking = .disabled
        }

        // 7. Tools
        if let tools = anthropicReq.tools, !tools.isEmpty {
            req.tools = transformTools(tools)
        }

        return req
    }

    /// Transform a single Anthropic message to one or more OpenAI messages.
    private func transformMessage(
        _ msg: AnthropicMessage,
        hasThinkingInHistory: Bool,
        modelID: String
    ) -> [OpenAIMessage] {
        let blocks = msg.content.contentBlocks

        switch msg.role {
        case "user":
            return transformUserMessage(blocks)
        case "assistant":
            return transformAssistantMessage(blocks, hasThinkingInHistory: hasThinkingInHistory, modelID: modelID)
        default:
            return [OpenAIMessage(role: msg.role, content: msg.content.textContent)]
        }
    }

    /// Transform a user message (handles tool_result blocks).
    private func transformUserMessage(_ blocks: [ContentBlock]) -> [OpenAIMessage] {
        var result = [OpenAIMessage]()
        var textParts = [String]()

        for block in blocks {
            switch block.type {
            case "text":
                textParts.append(block.text ?? "")
            case "tool_result":
                // OpenAI: tool_result → tool role message
                let toolContent = block.toolResultText
                result.append(OpenAIMessage(
                    role: "tool",
                    content: toolContent,
                    toolCallId: block.toolUseId
                ))
            case "image":
                textParts.append("[Image]")
            default:
                break
            }
        }

        // Add collected text as user message (after tool results)
        if !textParts.isEmpty {
            result.append(OpenAIMessage(role: "user", content: textParts.joined()))
        }

        return result
    }

    /// Transform an assistant message (handles tool_use and thinking blocks).
    private func transformAssistantMessage(
        _ blocks: [ContentBlock],
        hasThinkingInHistory: Bool,
        modelID: String
    ) -> [OpenAIMessage] {
        var textParts = [String]()
        var thinkingParts = [String]()
        var toolCalls = [OpenAIToolCall]()

        for block in blocks {
            switch block.type {
            case "text":
                textParts.append(block.text ?? "")
            case "thinking":
                if let t = block.thinking {
                    thinkingParts.append(t)
                }
            case "tool_use":
                // Map to OpenAI function call format
                let args: String
                if let input = block.input {
                    let anyDict = input.mapValues { $0.value }
                    if let data = try? JSONSerialization.data(withJSONObject: anyDict, options: .fragmentsAllowed),
                       let str = String(data: data, encoding: .utf8) {
                        args = str
                    } else {
                        args = "{}"
                    }
                } else {
                    args = "{}"
                }
                toolCalls.append(OpenAIToolCall(
                    index: toolCalls.count,
                    id: block.id ?? "toolu_\(UUID().uuidString.prefix(8))",
                    type: "function",
                    function: OpenAIFunctionCall(
                        name: block.name,
                        arguments: args
                    )
                ))
            default:
                break
            }
        }

        // Build reasoning_content
        let reasoningContent: String?
        if !thinkingParts.isEmpty {
            // Real thinking content from history — preserve it
            reasoningContent = thinkingParts.joined()
        } else if hasThinkingInHistory || modelID.hasPrefix("deepseek-") {
            // 🐛 BUG FIX: When thinking mode is active and this is a tool-call
            // message without thinking content (Claude Code strips it),
            // we MUST provide a non-empty reasoning_content.
            //
            // DeepSeek in thinking mode validates that ALL assistant messages
            // have reasoning_content when the conversation has thinking blocks.
            // The API returns:
            //   "The reasoning_content in the thinking mode must be passed
            //    back to the API."
            //
            // A space character " " satisfies the validator.
            reasoningContent = " "
        } else if modelID.hasPrefix("kimi-") && !toolCalls.isEmpty {
            // Kimi/Moonshot validator also treats empty reasoning_content
            // as missing. Inject placeholder for tool-call messages.
            reasoningContent = " "
        } else {
            reasoningContent = nil
        }

        let content = textParts.joined()

        var msg = OpenAIMessage(
            role: "assistant",
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
        msg.reasoningContent = reasoningContent

        return [msg]
    }

    /// Transform tools from Anthropic to OpenAI format.
    private func transformTools(_ tools: [AnthropicTool]) -> [OpenAITool] {
        tools.map { tool in
            OpenAITool(
                type: "function",
                function: OpenAIFunctionDef(
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.inputSchema
                )
            )
        }
    }

    // MARK: - Response: OpenAI → Anthropic

    /// Transform OpenAI response to Anthropic format.
    func transformResponse(
        _ openaiResp: OpenAIResponse,
        originalModel: String
    ) -> AnthropicResponse {
        let choice = openaiResp.choices.first!

        // Extract message content
        let msg = choice.message ?? OpenAIMessage(role: "assistant", content: "")
        let blocks = transformContent(msg)
        let stopReason = mapFinishReason(choice.finishReason)

        // Calculate input_tokens: subtract cache tokens (matches Anthropic spec)
        let usage = openaiResp.usage ?? OpenAIUsage(promptTokens: 0, completionTokens: 0)
        let inputTokens = max(0, usage.promptTokens
            - (usage.promptCacheHitTokens ?? 0)
            - (usage.promptCacheMissTokens ?? 0))

        return AnthropicResponse(
            id: openaiResp.id,
            type: "message",
            role: "assistant",
            content: blocks,
            model: originalModel,
            stopReason: stopReason,
            usage: Usage(
                inputTokens: inputTokens,
                outputTokens: usage.completionTokens,
                cacheCreationInputTokens: usage.promptCacheMissTokens,
                cacheReadInputTokens: usage.promptCacheHitTokens
            )
        )
    }

    /// Transform OpenAI message content to Anthropic content blocks.
    private func transformContent(_ msg: OpenAIMessage) -> [ContentBlock] {
        var blocks = [ContentBlock]()

        // 1. Reasoning content → thinking block (preserved for round-trip)
        if let rc = msg.reasoningContent, !rc.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append(ContentBlock(type: "thinking", thinking: rc))
        }

        // 2. Tool calls → tool_use blocks
        if let toolCalls = msg.toolCalls {
            for tc in toolCalls {
                var input: [String: AnyCodable]?
                if let args = tc.function.arguments,
                   let data = args.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    input = json.mapValues { AnyCodable($0) }
                }

                blocks.append(ContentBlock(
                    type: "tool_use",
                    id: tc.id,
                    name: tc.function.name,
                    input: input
                ))
            }
        }

        // 3. Text content → text block
        if !msg.content.isEmpty {
            blocks.append(ContentBlock(type: "text", text: msg.content))
        }

        // Ensure at least one block
        if blocks.isEmpty {
            blocks.append(ContentBlock(type: "text", text: ""))
        }

        return blocks
    }

    // MARK: - Streaming

    /// Transform an OpenAI streaming chunk into one or more Anthropic SSE events.
    /// Returns an array of SSEEvent strings to write to the response.
    func transformStreamChunk(
        _ chunk: OpenAIStreamChunk,
        state: inout StreamState,
        originalModel: String,
        msgID: String
    ) -> [SSEEvent] {
        var events = [SSEEvent]()

        guard let choices = chunk.choices, let choice = choices.first else {
            // Non-choice chunks (e.g., usage-only)
            if let usage = chunk.usage, state.stopSent {
                events.append(SSEEvent(
                    type: "message_delta",
                    delta: Delta(stopReason: nil),
                    usage: transformUsage(usage)
                ))
            }
            return events
        }

        let delta = choice.delta ?? OpenAIMessage(role: "assistant", content: "")

        // 1. Handle reasoning content → thinking block
        if let rc = delta.reasoningContent, !rc.isEmpty {
            if !state.reasoningStarted {
                // Close text block if it was started
                if state.contentStarted {
                    events.append(SSEEvent(type: "content_block_stop", index: state.contentIndex))
                    state.contentIndex += 1
                    state.contentStarted = false
                }
                state.reasoningStarted = true
                events.append(SSEEvent(
                    type: "content_block_start",
                    index: state.contentIndex,
                    contentBlock: ContentBlock(type: "thinking", thinking: "")
                ))
            }
            events.append(SSEEvent(
                type: "content_block_delta",
                index: state.contentIndex,
                delta: Delta(type: "thinking_delta", thinking: rc)
            ))
        }

        // 2. Handle text content
        if !delta.content.isEmpty {
            if !state.contentStarted {
                if state.reasoningStarted {
                    events.append(SSEEvent(type: "content_block_stop", index: state.contentIndex))
                    state.contentIndex += 1
                    state.reasoningStarted = false
                }
                state.contentStarted = true
                events.append(SSEEvent(
                    type: "content_block_start",
                    index: state.contentIndex,
                    contentBlock: ContentBlock(type: "text", text: "")
                ))
            }
            events.append(SSEEvent(
                type: "content_block_delta",
                index: state.contentIndex,
                delta: Delta(type: "text_delta", text: delta.content)
            ))
        }

        // 3. Handle tool calls
        if let toolCalls = delta.toolCalls {
            for tc in toolCalls {
                let oi = tc.index ?? 0

                if let existingIdx = state.startedToolCalls[oi] {
                    // Continuation — send argument delta
                    if let args = tc.function.arguments, !args.isEmpty {
                        events.append(SSEEvent(
                            type: "content_block_delta",
                            index: existingIdx,
                            delta: Delta(type: "input_json_delta", partialJson: args)
                        ))
                    }
                } else {
                    guard let name = tc.function.name, !name.isEmpty else { continue }
                    // New tool call — start a new block
                    state.contentIndex += 1
                    state.toolUseCount += 1
                    let blockIdx = state.contentIndex
                    state.startedToolCalls[oi] = blockIdx

                    let toolID = tc.id ?? "toolu_\(generateID())"
                    events.append(SSEEvent(
                        type: "content_block_start",
                        index: blockIdx,
                        contentBlock: ContentBlock(
                            type: "tool_use",
                            id: toolID,
                            name: name
                        )
                    ))

                    // Send initial arguments if present
                    if let args = tc.function.arguments, !args.isEmpty {
                        events.append(SSEEvent(
                            type: "content_block_delta",
                            index: blockIdx,
                            delta: Delta(type: "input_json_delta", partialJson: args)
                        ))
                    }
                }
            }
        }

        // 4. Handle finish reason
        if let finishReason = choice.finishReason, !finishReason.isEmpty {
            // Close open content blocks
            if state.contentStarted || state.reasoningStarted {
                events.append(SSEEvent(type: "content_block_stop", index: state.contentIndex))
            }

            // Close tool_use blocks
            for (_, blockIdx) in state.startedToolCalls.sorted(by: { $0.value < $1.value }) {
                events.append(SSEEvent(type: "content_block_stop", index: blockIdx))
            }
            state.startedToolCalls.removeAll()

            state.stopSent = true

            // Get usage from chunk or nil
            let usage = chunk.usage.flatMap { transformUsage($0) }

            events.append(SSEEvent(
                type: "message_delta",
                delta: Delta(stopReason: mapFinishReason(finishReason)),
                usage: usage
            ))
        }

        // Non-choice, non-finish chunk with usage (separate usage chunk in stream)
        if chunk.choices == nil || choices.isEmpty {
            if let usage = chunk.usage, state.stopSent {
                events.append(SSEEvent(
                    type: "message_delta",
                    delta: Delta(stopReason: nil),
                    usage: transformUsage(usage)
                ))
            }
        }

        return events
    }

    private func transformUsage(_ usage: OpenAIUsage) -> Usage {
        Usage(
            inputTokens: max(0, usage.promptTokens
                - (usage.promptCacheHitTokens ?? 0)
                - (usage.promptCacheMissTokens ?? 0)),
            outputTokens: usage.completionTokens,
            cacheCreationInputTokens: usage.promptCacheMissTokens,
            cacheReadInputTokens: usage.promptCacheHitTokens
        )
    }

    // MARK: - Helpers

    private func mapFinishReason(_ reason: String?) -> String {
        switch reason {
        case "stop": return "end_turn"
        case "length": return "max_tokens"
        case "tool_calls": return "tool_use"
        case "content_filter": return "end_turn"
        default: return "end_turn"
        }
    }

    private func generateID() -> String {
        "\(Date.now.timeIntervalSince1970 * 1_000_000)"
    }
}

// MARK: - Streaming State

struct StreamState {
    var contentIndex = 0
    var contentStarted = false
    var reasoningStarted = false
    var stopSent = false
    var toolUseCount = 0
    var startedToolCalls: [Int: Int] = [:]
}
