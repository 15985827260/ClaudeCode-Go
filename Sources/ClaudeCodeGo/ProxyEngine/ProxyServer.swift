import Foundation
import Network
import OSLog

/// Embedded proxy server that listens for Claude Code requests
/// and forwards them to OpenCode Go.
class ProxyServer {
    private let logger = Logger(subsystem: "com.claudecode.go.proxy", category: "ProxyServer")
    private let transformer = Transformer()
    private let session = URLSession(configuration: .default)

    private var listener: NWListener?
    private var _isRunning = false
    private let connectionsLock = NSLock()
    private var _connections = [UUID: NWConnection]()
    private let queue = DispatchQueue(label: "com.claudecode.go.proxy.server", qos: .utility)
    private let logsRequestBodyPreview = false

    // Configuration
    private var port: UInt16 = 3456
    private var apiKey = ""
    private var modelID = "kimi-k2.6"
    private var temperature: Double = 0.7
    private var maxTokens: Int = 4096
    private let baseURL = "https://opencode.ai/zen/go/v1/chat/completions"
    private let anthropicBaseURL = "https://opencode.ai/zen/go/v1/messages"

    var onLog: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    var isActive: Bool { _isRunning }

    /// Update model ID at runtime without restarting. Takes effect on the next request.
    func updateModel(_ modelID: String) {
        self.modelID = modelID
        log("模型已切换: \(modelID)")
    }

    // MARK: - Lifecycle

    func start(port: Int, apiKey: String, modelID: String, temperature: Double, maxTokens: Int) throws {
        guard !_isRunning else {
            logger.warning("Server already running")
            return
        }

        self.port = UInt16(port)
        self.apiKey = apiKey
        self.modelID = modelID
        self.temperature = temperature
        self.maxTokens = maxTokens

        log("正在启动代理服务器，监听端口 \(port)...")
        log("模型: \(modelID)")

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: self.port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self._isRunning = true
                self.onStateChange?(true)
                self.log("✅ 代理服务已就绪 - 监听端口 \(port)")
            case .failed(let error):
                self.log("❌ 监听失败: \(error.localizedDescription)")
                self._isRunning = false
                self.onStateChange?(false)
            case .cancelled:
                self._isRunning = false
                self.onStateChange?(false)
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] in self?.handleConnection($0) }
        listener?.start(queue: queue)
    }

    func stop() {
        guard _isRunning else { return }
        log("正在停止代理服务...")

        connectionsLock.lock()
        let conns = _connections
        _connections.removeAll()
        connectionsLock.unlock()

        for (_, conn) in conns { conn.cancel() }

        listener?.cancel()
        listener = nil
        _isRunning = false
        onStateChange?(false)
        log("代理服务已停止")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        let connID = UUID()
        connectionsLock.lock()
        _connections[connID] = connection
        connectionsLock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.connectionsLock.lock()
                self?._connections.removeValue(forKey: connID)
                self?.connectionsLock.unlock()
            default:
                break
            }
        }

        readRequest(connection: connection, connID: connID)
        connection.start(queue: queue)
    }

    // MARK: - HTTP Request Parsing

    private func readRequest(connection: NWConnection, connID: UUID, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.log("连接错误: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var currentBuffer = buffer
            if let data { currentBuffer.append(data) }

            if let (method, path, headers, body) = self.parseHTTPRequest(currentBuffer) {
                let host = headers["Host"] ?? "localhost"
                let contentLen = headers["Content-Length"] ?? "?"
                self.log("→ \(method) /\(path)  content-length:\(contentLen) 来自 \(host)")
                // Log request body preview for POST requests
                if self.logsRequestBodyPreview,
                   method == "POST",
                   let bodyStr = String(data: body, encoding: .utf8) {
                    let preview = bodyStr.prefix(500)
                    self.log("  POST body: \(preview)")
                }
                self.handleRequest(method: method, path: path, headers: headers, body: body, connection: connection)
            } else if isComplete || currentBuffer.count > 5_000_000 {
                self.log("❌ 请求解析失败: buffer=\(currentBuffer.count) isComplete=\(isComplete)")
                if let raw = String(data: currentBuffer, encoding: .utf8) {
                    self.log("  raw head: \(raw.prefix(300))")
                }
                self.sendError(connection, statusCode: 400, message: "Bad Request")
            } else {
                self.readRequest(connection: connection, connID: connID, buffer: currentBuffer)
            }
        }
    }

    private func parseHTTPRequest(_ data: Data) -> (String, String, [String: String], Data)? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else { return nil }

        let headerSection = parts[0]
        let headerLines = headerSection.components(separatedBy: "\r\n")
        guard headerLines.count >= 1 else { return nil }

        let requestParts = headerLines[0].components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0]
        var path = requestParts[1]
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        // Strip query string (e.g. "v1/messages?beta=true" → "v1/messages")
        if let qIdx = path.firstIndex(of: "?") { path = String(path[..<qIdx]) }

        var headers = [String: String]()
        for line in headerLines.dropFirst() {
            let hParts = line.components(separatedBy: ": ")
            if hParts.count >= 2 {
                headers[hParts[0]] = hParts.dropFirst().joined(separator: ": ")
            }
        }

        let contentLength = Int(headers["Content-Length"] ?? "0") ?? 0
        let headerEndData = headerSection.data(using: .utf8)!.count + 4
        let bodyBytes = data.count - headerEndData

        guard bodyBytes >= contentLength else { return nil }

        let bodyData = data.subdata(in: headerEndData..<(headerEndData + contentLength))
        return (method, path, headers, bodyData)
    }

    // MARK: - Request Routing

    private func handleRequest(method: String, path: String, headers: [String: String], body: Data, connection: NWConnection) {
        switch (method, path) {
        case ("POST", "v1/messages"):
            handleMessages(connection: connection, body: body)
        case ("POST", "v1/messages/count_tokens"), (_, "health"):
            handleHealthCheck(connection: connection)
        case (_, let p) where p == "v1/models" || p.hasPrefix("v1/models/"):
            handleListModels(connection: connection, path: p)
        default:
            sendError(connection, statusCode: 404, message: "Not Found")
        }
    }

    // MARK: - Messages Handler

    private func handleMessages(connection: NWConnection, body: Data) {
        let anthropicReq: AnthropicRequest
        do {
            anthropicReq = try JSONDecoder().decode(AnthropicRequest.self, from: body)
        } catch {
            let errMsg = "请求解析失败: \(error.localizedDescription)"
            log(errMsg)
            sendError(connection, statusCode: 400, message: errMsg)
            return
        }

        let isStreaming = anthropicReq.stream ?? false
        let isNative = transformer.isAnthropicNativeModel(modelID)
        // Preserve the model name Claude Code sent, so we return it in responses.
        // The actual upstream model is always self.modelID.
        let originalModel = anthropicReq.model
        log("收到请求: model=\(anthropicReq.model) stream=\(isStreaming) tools=\(anthropicReq.tools?.count ?? 0)")

        if isStreaming {
            handleStreamingRequest(connection: connection, anthropicReq: anthropicReq, isNative: isNative, originalModel: originalModel)
        } else {
            handleNonStreamingRequest(connection: connection, anthropicReq: anthropicReq, isNative: isNative, originalModel: originalModel)
        }
    }

    // MARK: - Non-Streaming

    private func handleNonStreamingRequest(connection: NWConnection, anthropicReq: AnthropicRequest, isNative: Bool, originalModel: String) {
        // Snapshot config for this request's lifetime
        let currentModelID = modelID
        let currentTemperature = temperature
        let currentMaxTokens = maxTokens

        if isNative {
            forwardAnthropicRequest(connection: connection, body: anthropicReq, modelID: currentModelID)
        } else {
            let openaiReq = transformer.transformRequest(anthropicReq, modelID: currentModelID, temperature: currentTemperature, maxTokens: currentMaxTokens)
            sendOpenAIRequest(connection: connection, openaiReq: openaiReq) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    do {
                        let openaiResp = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                        // Return the original model name Claude Code sent, not the backend model
                        let anthropicResp = self.transformer.transformResponse(openaiResp, originalModel: originalModel)
                        let respData = try JSONEncoder().encode(anthropicResp)
                        self.sendJSONResponse(connection, data: respData)
                    } catch {
                        let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? "非UTF8"
                        self.log("响应转换失败: \(error.localizedDescription)")
                        self.log("上游原始响应: \(bodyPreview)")
                        self.sendError(connection, statusCode: 502, message: "Response transform failed")
                    }
                case .failure(let error):
                    self.log("上游请求失败: \(error.localizedDescription)")
                    self.sendError(connection, statusCode: 502, message: "Upstream API error")
                }
            }
        }
    }

    // MARK: - Streaming

    private func handleStreamingRequest(connection: NWConnection, anthropicReq: AnthropicRequest, isNative: Bool, originalModel: String) {
        // Snapshot config for this request's lifetime
        let currentModelID = modelID
        let currentTemperature = temperature
        let currentMaxTokens = maxTokens

        // Send SSE headers immediately to prevent Claude Code's 6s timeout
        sendSSEHeaders(connection)

        // Start heartbeat every 3 seconds
        let heartbeatTimer = DispatchSource.makeTimerSource(queue: queue)
        heartbeatTimer.schedule(deadline: .now() + 3, repeating: 3)
        heartbeatTimer.setEventHandler { [weak connection] in
            connection?.send(content: ":keepalive\n\n".data(using: .utf8), completion: .idempotent)
        }
        heartbeatTimer.resume()

        let cleanup = { heartbeatTimer.cancel(); connection.cancel() }

        if isNative {
            proxyAnthropicStreamAsync(connection: connection, anthropicReq: anthropicReq, modelID: currentModelID, cleanup: cleanup)
        } else {
            let openaiReq = transformer.transformRequest(anthropicReq, modelID: currentModelID, temperature: currentTemperature, maxTokens: currentMaxTokens)
            // Use originalModel (from request) in events so Claude Code sees its own model name
            proxyOpenAIStreamAsync(connection: connection, openaiReq: openaiReq, modelID: originalModel, cleanup: cleanup)
        }
    }

    // MARK: - OpenAI Streaming (async/await bytes)

    private func proxyOpenAIStreamAsync(connection: NWConnection, openaiReq: OpenAIRequest, modelID: String, cleanup: @escaping () -> Void) {
        var req = openaiReq
        req.stream = true
        req.streamOptions = StreamOptions(includeUsage: true)

        let endpoint = getEndpoint(isAnthropic: false)
        var urlReq = URLRequest(url: URL(string: endpoint.url)!)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        urlReq.httpBody = try? JSONEncoder().encode(req)

        let msgID = "msg_\(UUID().uuidString.prefix(8).lowercased())"
        let taskID = UUID().uuidString.prefix(6)
        log("⬆️ [\(taskID)] 流式发送到上游: model=\(req.model)")

        Task { [weak self] in
            guard let self else { cleanup(); return }
            defer { cleanup() }

            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: urlReq)

                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 400 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    self.log("⬇️ [\(taskID)] 上游返回错误状态: \(code)")
                    return
                }
                self.log("⬇️ [\(taskID)] 上游连接成功，开始接收流")

                // Send message_start now that upstream confirmed
                let startEvent = SSEEvent(type: "message_start", message: AnthropicResponse(
                    id: msgID, type: "message", role: "assistant",
                    content: [], model: modelID, stopReason: nil,
                    usage: Usage(inputTokens: 0, outputTokens: 0)
                ))
                self.sendSSEEvent(connection, event: startEvent)

                var streamState = StreamState()
                var lineBuffer = Data()

                // Process stream byte-by-byte for real-time SSE
                for try await byte in asyncBytes {
                    if byte == UInt8(ascii: "\n") {
                        let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                        lineBuffer = Data()
                        self.processSSELine(line, connection: connection, streamState: &streamState, msgID: msgID, modelID: modelID)
                    } else {
                        lineBuffer.append(byte)
                    }
                }

                // Process remaining buffer
                if !lineBuffer.isEmpty {
                    let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                    self.processSSELine(line, connection: connection, streamState: &streamState, msgID: msgID, modelID: modelID)
                }

                // Send message_stop
                let stopSSE = "event: message_stop\ndata: {}\n\n"
                connection.send(content: stopSSE.data(using: .utf8), completion: .idempotent)

            } catch {
                self.log("流式请求失败: \(error.localizedDescription)")
            }
        }
    }

    private func processSSELine(_ line: String, connection: NWConnection, streamState: inout StreamState, msgID: String, modelID: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data: ") else { return }

        let jsonStr = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { return }

        guard let chunkData = jsonStr.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: chunkData)
        else { return }

        let events = transformer.transformStreamChunk(chunk, state: &streamState, originalModel: modelID, msgID: msgID)

        for event in events {
            sendSSEEvent(connection, event: event)
        }
    }

    // MARK: - Anthropic Native Streaming (async bytes, MiniMax)

    private func proxyAnthropicStreamAsync(connection: NWConnection, anthropicReq: AnthropicRequest, modelID: String, cleanup: @escaping () -> Void) {
        let endpoint = getEndpoint(isAnthropic: true)
        var urlReq = URLRequest(url: URL(string: endpoint.url)!)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        urlReq.setValue(endpoint.apiKey, forHTTPHeaderField: "x-api-key")

        guard var bodyData = try? JSONEncoder().encode(anthropicReq),
              var bodyStr = String(data: bodyData, encoding: .utf8)
        else {
            sendError(connection, statusCode: 500, message: "Failed to serialize request")
            cleanup()
            return
        }

        // Replace model field with our configured model ID
        if let range = bodyStr.range(of: "\"model\":\"") {
            let start = range.upperBound
            if let end = bodyStr[start...].firstIndex(of: "\"") {
                bodyStr = bodyStr[..<start] + modelID + bodyStr[end...]
            }
        }
        bodyData = bodyStr.data(using: .utf8) ?? bodyData
        urlReq.httpBody = bodyData

        Task { [weak self] in
            guard let self else { cleanup(); return }
            defer { cleanup() }

            do {
                let (asyncBytes, _) = try await URLSession.shared.bytes(for: urlReq)

                // MiniMax returns Anthropic-format SSE, proxy raw bytes
                var buffer = Data()
                for try await byte in asyncBytes {
                    buffer.append(byte)
                    if buffer.count >= 4096 {
                        connection.send(content: buffer, completion: .idempotent)
                        buffer.removeAll()
                    }
                }
                if !buffer.isEmpty {
                    connection.send(content: buffer, completion: .idempotent)
                }
            } catch {
                self.log("Anthropic 流式请求失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Forward Anthropic Request (Non-Streaming)

    private func forwardAnthropicRequest(connection: NWConnection, body: AnthropicRequest, modelID: String) {
        let endpoint = getEndpoint(isAnthropic: true)
        var urlReq = URLRequest(url: URL(string: endpoint.url)!)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        urlReq.setValue(endpoint.apiKey, forHTTPHeaderField: "x-api-key")

        guard var bodyData = try? JSONEncoder().encode(body),
              var bodyStr = String(data: bodyData, encoding: .utf8)
        else {
            sendError(connection, statusCode: 500, message: "Failed to serialize request")
            return
        }

        if let range = bodyStr.range(of: "\"model\":\"") {
            let start = range.upperBound
            if let end = bodyStr[start...].firstIndex(of: "\"") {
                bodyStr = bodyStr[..<start] + modelID + bodyStr[end...]
            }
        }
        bodyData = bodyStr.data(using: .utf8) ?? bodyData
        urlReq.httpBody = bodyData

        let task = session.dataTask(with: urlReq) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.log("Anthropic 请求失败: \(error.localizedDescription)")
                self.sendError(connection, statusCode: 502, message: "Upstream API error")
                return
            }
            guard let data else {
                self.sendError(connection, statusCode: 502, message: "Empty response")
                return
            }
            self.sendJSONResponse(connection, data: data)
        }
        task.resume()
    }

    // MARK: - OpenCode API Client

    private struct Endpoint { let url: String; let apiKey: String }

    private func getEndpoint(isAnthropic: Bool) -> Endpoint {
        Endpoint(url: isAnthropic ? anthropicBaseURL : baseURL, apiKey: apiKey)
    }

    private func sendOpenAIRequest(connection: NWConnection, openaiReq: OpenAIRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        let endpoint = getEndpoint(isAnthropic: false)
        var req = openaiReq
        req.stream = false

        var urlReq = URLRequest(url: URL(string: endpoint.url)!)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        urlReq.httpBody = try? JSONEncoder().encode(req)

        let taskID = UUID().uuidString.prefix(6)
        log("⬆️ [\(taskID)] 发送到上游: model=\(req.model) stream=\(req.stream)")
        if logsRequestBodyPreview,
           let bodyStr = urlReq.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) {
            log("  [\(taskID)] 请求体预览: \(bodyStr.prefix(300))")
        }

        session.dataTask(with: urlReq) { [weak self] data, resp, error in
            guard let self else { return }
            if let error { self.log("⬇️ [\(taskID)] 上游错误: \(error.localizedDescription)"); completion(.failure(error)); return }
            guard let data else {
                self.log("⬇️ [\(taskID)] 上游返回空")
                completion(.failure(NSError(domain: "proxy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                return
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            self.log("⬇️ [\(taskID)] 上游响应: \(status) (\(data.count) bytes)")
            completion(.success(data))
        }.resume()
    }

    // MARK: - Health

    private func handleHealthCheck(connection: NWConnection) {
        let health = ["status": "ok", "model": modelID]
        if let data = try? JSONEncoder().encode(health) {
            sendJSONResponse(connection, data: data)
        } else {
            connection.cancel()
        }
    }

    // MARK: - Models

    /// Handle GET /v1/models and GET /v1/models/{model_id}.
    /// Claude Code calls this to validate model availability.
    private func handleListModels(connection: NWConnection, path: String) {
        // Strip "v1/models" prefix to get optional model ID
        let modelIDPart = path
            .replacingOccurrences(of: "v1/models", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let isSpecificRequest = !modelIDPart.isEmpty

        // Build Anthropic-compatible model list response
        let models: [[String: Any]]

        if isSpecificRequest {
            // Return single model
            models = [[
                "type": "model",
                "id": modelIDPart,
                "display_name": modelIDPart,
                "created_at": "2024-01-01T00:00:00Z"
            ]]
        } else {
            // Return all models including the configured one and common Claude model IDs
            let allModels = ModelOption.allModels
            let configuredID = self.modelID
            // Claude Code validates its configured model against this list,
            // so include the most common Claude model IDs.
            let claudeModelIDs = [
                "claude-sonnet-4-20250514",
                "claude-sonnet-4-5",
                "claude-sonnet-4-6",
                "claude-opus-4-5",
                "claude-opus-4-5-20250514",
                "claude-sonnet-4-20250514",
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
            ]
            var modelIDs = Set(allModels.map { $0.id })
            modelIDs.insert(configuredID)
            for cid in claudeModelIDs { modelIDs.insert(cid) }
            models = modelIDs.map { id in
                [
                    "type": "model",
                    "id": id,
                    "display_name": id,
                    "created_at": "2024-01-01T00:00:00Z"
                ]
            }
        }

        let resp: [String: Any] = isSpecificRequest
            ? ["data": models.first ?? [:]]
            : ["data": models]

        if let data = try? JSONSerialization.data(withJSONObject: resp) {
            sendJSONResponse(connection, data: data)
        } else {
            connection.cancel()
        }
    }

    // MARK: - Response Writing

    private func sendJSONResponse(_ connection: NWConnection, data: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(data)
        connection.send(content: resp, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendError(_ connection: NWConnection, statusCode: Int, message: String) {
        let errorBody: [String: Any] = ["type": "error", "error": ["type": "api_error", "message": message]]
        let data = (try? JSONSerialization.data(withJSONObject: errorBody)) ?? Data()

        let reason: String
        switch statusCode {
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 500: reason = "Internal Server Error"
        case 502: reason = "Bad Gateway"
        default: reason = "Error"
        }

        let header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(data)
        connection.send(content: resp, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendSSEHeaders(_ connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n"
        connection.send(content: headers.data(using: .utf8), completion: .idempotent)
    }

    private func sendSSEEvent(_ connection: NWConnection, event: SSEEvent) {
        guard let eventData = try? JSONEncoder().encode(event),
              let eventStr = String(data: eventData, encoding: .utf8)
        else { return }
        let sse = "event: \(event.type)\ndata: \(eventStr)\n\n"
        connection.send(content: sse.data(using: .utf8), completion: .idempotent)
    }

    // MARK: - Logging

    private func log(_ message: String) {
        logger.log("\(message)")
        onLog?(message)
    }
}
