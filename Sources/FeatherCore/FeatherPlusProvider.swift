import Foundation

/// Feather Plus's OpenAI-compatible endpoint. Every plan uses the same model, chosen by the
/// server, so the model sent is a placeholder and the request body is otherwise OpenCode Go's.
public struct FeatherPlusProvider: LLMProvider {
    public var token: String
    public var baseURL: String

    public static let defaultModel = "fast"
    /// Model names only Feather Plus used. `premium` was a tier that plans no longer have.
    private static let modelNames: Set<String> = ["fast", "premium"]

    public init(token: String, baseURL: String = FeatherPlus.defaultBaseURL) {
        self.token = token
        self.baseURL = baseURL
    }

    public static func isPlusModel(_ model: String) -> Bool {
        modelNames.contains(model)
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !token.isEmpty else { throw LLMError.missingAPIKey }
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        return try ProviderTransport.request(
            endpoint: .endpoint(base: baseURL, path: "/v1/chat/completions"),
            token: token,
            sessionHeader: nil,
            body: OpenCodeGoProvider(apiKey: token, baseURL: baseURL).body(for: request)
        )
    }

    /// Reasoning controls are model specific, and the client does not know the real model, so
    /// the server decides. The proxy also reports upstream 400s as 502, so the retry without
    /// the control would never run.
    public var controlsReasoning: Bool { false }

    public var preconnectURL: URL? { try? .endpoint(base: baseURL, path: "/health") }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        try OpenCodeGoProvider(apiKey: token, baseURL: baseURL).parse(event)
    }
}
