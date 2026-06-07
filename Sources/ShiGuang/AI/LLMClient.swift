import Foundation

// MARK: - Public surface

/// Provider-agnostic chat message + completion API.
struct ChatMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable { case system, user, assistant }
    let id: UUID
    let role: Role
    var content: String
    /// Optional reasoning text extracted from `<think>...</think>` blocks.
    /// Rendered separately from `content` (typically as a collapsible disclosure).
    var thinking: String?

    init(id: UUID = UUID(), role: Role, content: String, thinking: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
    }
}

struct ChatRequest {
    var messages: [ChatMessage]
    var model: String
    var temperature: Double
    var maxTokens: Int = 2048
}

struct ChatResponse {
    var text: String
    var usage: Usage?
    struct Usage: Codable, Hashable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
    }
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case httpStatus(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "未设置 API Key"
        case .invalidBaseURL: return "Base URL 不合法"
        case .httpStatus(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .decoding(let msg): return "解析失败：\(msg)"
        case .network(let msg): return "网络错误：\(msg)"
        }
    }
}

protocol LLMClient: Sendable {
    /// Non-streaming: collects the full response and returns at the end.
    func chat(_ req: ChatRequest) async throws -> ChatResponse

    /// SSE streaming. `onChunk` is invoked for each new text fragment.
    /// Marked `async` so callers can hop actors (e.g. `@MainActor`) inside.
    func stream(_ req: ChatRequest, onChunk: @escaping @Sendable (String) async -> Void) async throws
}

// MARK: - OpenAI-compatible client

/// Implements the OpenAI Chat Completions wire format. Works against:
///   - api.openai.com
///   - MiniMax public API (api.minimax.chat)
///   - Azure OpenAI (set baseURL to your deployment endpoint)
///   - any other OpenAI-compatible host (vLLM, LocalAI, Ollama's /v1, etc.)
final class OpenAIClient: LLMClient, @unchecked Sendable {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: String, apiKey: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURL) else { throw LLMError.invalidBaseURL }
        self.baseURL = url
        self.apiKey = apiKey
        self.session = session
    }

    func chat(_ req: ChatRequest) async throws -> ChatResponse {
        let acc = StringAccumulator()
        let collector: @Sendable (String) async -> Void = { chunk in
            acc.append(chunk)
        }
        try await stream(req, onChunk: collector)
        return ChatResponse(text: acc.value, usage: nil)
    }

    /// OpenAI streaming format. Each SSE line is either:
    ///   `data: {"choices":[{"delta":{"content":"..."}}]}`
    ///   `data: [DONE]`
    func stream(_ req: ChatRequest, onChunk: @escaping @Sendable (String) async -> Void) async throws {
        let url = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": req.model,
            "messages": req.messages.map { m in
                ["role": m.role.rawValue, "content": m.content]
            },
            "temperature": req.temperature,
            "max_tokens": req.maxTokens,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.network("无 HTTP 响应") }
        if !(200..<300).contains(http.statusCode) {
            var errBody = ""
            for try await line in bytes.lines { errBody += line + "\n" }
            throw LLMError.httpStatus(http.statusCode, errBody)
        }

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String
            else { continue }
            await onChunk(content)
        }
    }
}

// MARK: - Anthropic client

/// Implements Anthropic Messages API. Default baseURL is https://api.anthropic.com
final class AnthropicClient: LLMClient, @unchecked Sendable {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: String, apiKey: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURL) else { throw LLMError.invalidBaseURL }
        self.baseURL = url
        self.apiKey = apiKey
        self.session = session
    }

    func chat(_ req: ChatRequest) async throws -> ChatResponse {
        let acc = StringAccumulator()
        let collector: @Sendable (String) async -> Void = { chunk in
            acc.append(chunk)
        }
        try await stream(req, onChunk: collector)
        return ChatResponse(text: acc.value, usage: nil)
    }

    /// Anthropic streaming format. We watch for `event: content_block_delta`
    /// and read `delta.text` from the following `data:` line.
    func stream(_ req: ChatRequest, onChunk: @escaping @Sendable (String) async -> Void) async throws {
        let url = baseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Send BOTH auth styles so the same client works against:
        //   - Anthropic's native API (reads x-api-key, ignores Authorization)
        //   - MiniMax / Mavis gateway (reads Authorization: Bearer, ignores x-api-key)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        // Anthropic expects system as a top-level string, not a message.
        var systemText = ""
        var msgs: [[String: String]] = []
        for m in req.messages {
            switch m.role {
            case .system: systemText += (systemText.isEmpty ? "" : "\n") + m.content
            case .user, .assistant:
                msgs.append(["role": m.role.rawValue, "content": m.content])
            }
        }

        var body: [String: Any] = [
            "model": req.model,
            "max_tokens": req.maxTokens,
            "temperature": req.temperature,
            "messages": msgs,
            "stream": true
        ]
        if !systemText.isEmpty {
            body["system"] = systemText
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.network("无 HTTP 响应") }
        if !(200..<300).contains(http.statusCode) {
            var errBody = ""
            for try await line in bytes.lines { errBody += line + "\n" }
            throw LLMError.httpStatus(http.statusCode, errBody)
        }

        var pendingEvent = ""
        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                pendingEvent = ""
                continue
            }
            if line.hasPrefix("event:") {
                pendingEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("data:") && pendingEvent == "content_block_delta" {
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let delta = json["delta"] as? [String: Any],
                      let text = delta["text"] as? String
                else { continue }
                await onChunk(text)
            }
        }
    }
}

/// `@Sendable` closures can't capture a `var`, so we wrap a mutable String
/// in a small class for the chat() accumulators.
final class StringAccumulator: @unchecked Sendable {
    private var buf: String = ""
    private let lock = NSLock()
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        buf += s
    }
    var value: String {
        lock.lock(); defer { lock.unlock() }
        return buf
    }
}

// MARK: - Factory

enum LLMClientFactory {
    static func make(settings: AppSettings) throws -> LLMClient {
        guard !settings.apiKey.isEmpty else { throw LLMError.missingAPIKey }
        switch settings.provider {
        case .minimax, .openAI:
            // MiniMax's public API (api.minimax.chat) uses the OpenAI
            // Chat Completions protocol with Bearer auth. Power users with
            // Mavis internal credentials can still point the baseURL at
            // agent.minimaxi.com and it'll be routed through the same client.
            return try OpenAIClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        case .anthropic:
            return try AnthropicClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        }
    }
}
