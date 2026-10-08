import Foundation

/// Anthropic's streaming Messages API, with an API key from the Anthropic Console.
public struct ClaudeProvider: LLMProvider {
    public var apiKey: String
    public var baseURL: String

    public static let defaultBaseURL = "https://api.anthropic.com/v1"
    public static let defaultModel = "claude-haiku-5-5"
    public static let apiVersion = "2023-06-01"

    public init(apiKey: String, baseURL: String = ClaudeProvider.defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        var urlRequest = try ProviderTransport.request(
            endpoint: .endpoint(base: baseURL, path: "/messages"),
            token: apiKey,
            sessionHeader: nil,
            extraHeaders: Self.headers(apiKey: apiKey),
            body: body(for: request)
        )
        // Anthropic authenticates with `x-api-key`, not a bearer token.
        urlRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    static func headers(apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": apiVersion]
    }

    func body(for request: GenerationRequest) -> [String: Any] {
        var messages: [[String: Any]] = []
        for (index, turn) in request.turns.enumerated() {
            if index == 0, let image = request.imageJPEG {
                messages.append([
                    "role": turn.role.rawValue,
                    "content": [
                        [
                            "type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()],
                        ],
                        ["type": "text", "text": turn.text],
                    ],
                ])
            } else {
                messages.append(["role": turn.role.rawValue, "content": turn.text])
            }
        }
        return [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "system": request.system,
            "messages": messages,
        ]
    }

    public var preconnectURL: URL? { try? .endpoint(base: baseURL, path: "/models") }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignore }
        switch json["type"] as? String ?? event.event ?? "" {
        case "content_block_delta":
            let delta = json["delta"] as? [String: Any]
            guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String, !text.isEmpty
            else { return .ignore }
            return .text(text)
        case "message_delta":
            let delta = json["delta"] as? [String: Any]
            if delta?["stop_reason"] as? String == "refusal" { throw LLMError.refused }
            return .ignore
        case "message_stop":
            return .done
        case "error":
            throw ProviderTransport.streamError(from: Data(event.data.utf8))
        default:
            return .ignore
        }
    }
}

/// Fetches the models available to an Anthropic API key.
public enum ClaudeModelCatalog {
    public static let fallbackModels = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]

    public static func fetchModels(
        apiKey: String,
        baseURL: String = ClaudeProvider.defaultBaseURL
    ) async throws -> [String] {
        var request = URLRequest(url: try .endpoint(base: baseURL, path: "/models?limit=100"))
        for (name, value) in ClaudeProvider.headers(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(ProviderTransport.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.api(message: "The models request did not return an HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw LLMError.http(status: http.statusCode, message: ProviderTransport.errorMessage(from: data))
        }
        return try decodeModels(data)
    }

    static func decodeModels(_ data: Data) throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        // The API lists the newest models first, which is the order worth keeping.
        return try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
    }
}
