import Foundation

/// OpenAI's streaming chat completions API, with an API key from the OpenAI Platform. The request
/// and stream formats are the same as OpenCode Go's, which is OpenAI-compatible.
public struct OpenAIProvider: LLMProvider {
    public var apiKey: String
    public var baseURL: String

    public static let defaultBaseURL = "https://api.openai.com/v1"
    public static let defaultModel = "gpt-5.4-mini"

    public init(apiKey: String, baseURL: String = OpenAIProvider.defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        return try ProviderTransport.request(
            endpoint: .endpoint(base: baseURL, path: "/chat/completions"),
            token: apiKey,
            sessionHeader: nil,
            body: body(for: request)
        )
    }

    func body(for request: GenerationRequest) -> [String: Any] {
        OpenCodeGoProvider(apiKey: apiKey, baseURL: baseURL).body(for: request)
    }

    public var controlsReasoning: Bool { true }

    public var preconnectURL: URL? { try? .endpoint(base: baseURL, path: "/models") }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        try OpenCodeGoProvider(apiKey: apiKey, baseURL: baseURL).parse(event)
    }
}

/// Fetches the chat models available to an OpenAI API key.
public enum OpenAIModelCatalog {
    public static let fallbackModels = [OpenAIProvider.defaultModel, "gpt-5.4", "gpt-5.5"]

    public static func fetchModels(
        apiKey: String,
        baseURL: String = OpenAIProvider.defaultBaseURL
    ) async throws -> [String] {
        var request = URLRequest(url: try .endpoint(base: baseURL, path: "/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    /// Words in the IDs of models that cannot write chat replies, such as audio, image, and
    /// embedding models, or that only work through other APIs.
    static let excludedWords = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "moderation", "instruct", "codex", "pro", "deep-research", "computer-use"]

    /// Keeps the GPT and o-series chat models, newest first, without dated snapshots.
    static func decodeModels(_ data: Data) throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable {
                let id: String
                let created: Int?
            }
            let data: [Model]
        }
        let models = try JSONDecoder().decode(Response.self, from: data).data
        return models
            .filter { isChatModel($0.id) }
            .sorted { ($0.created ?? 0) > ($1.created ?? 0) }
            .map(\.id)
    }

    static func isChatModel(_ id: String) -> Bool {
        let isFamily = id.hasPrefix("gpt-") || id.range(of: #"^o\d"#, options: .regularExpression) != nil
        let isSnapshot = id.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        let parts = Set(id.split(separator: "-").map(String.init))
        let isExcluded = excludedWords.contains { word in word.contains("-") ? id.contains(word) : parts.contains(word) }
        return isFamily && !isSnapshot && !isExcluded
    }

    /// Keeps `current` when the key can use it; otherwise the default, else the newest model.
    public static func model(for models: [String], current: String) -> String? {
        if models.contains(current) { return current }
        return models.contains(OpenAIProvider.defaultModel) ? OpenAIProvider.defaultModel : models.first
    }
}
