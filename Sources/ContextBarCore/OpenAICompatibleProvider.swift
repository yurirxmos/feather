import Foundation

/// Any backend speaking `POST {baseURL}/chat/completions` with streaming: OpenAI, OpenRouter,
/// Groq, Ollama (`http://localhost:11434/v1`), LM Studio, and similar.
public struct OpenAICompatibleProvider: LLMProvider {
    public var apiKey: String
    public var baseURL: String

    public init(apiKey: String, baseURL: String = ProviderKind.openAICompatible.defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        var urlRequest = URLRequest(url: try .endpoint(base: baseURL, path: "/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request), options: [.sortedKeys])
        return urlRequest
    }

    /// Omits a token limit on purpose: servers disagree on `max_tokens` vs.
    /// `max_completion_tokens`, and reasoning models reject the former.
    func body(for request: GenerationRequest) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": request.system]]
        for (index, turn) in request.turns.enumerated() {
            if index == 0, let image = request.imageJPEG {
                messages.append([
                    "role": turn.role.rawValue,
                    "content": [
                        ["type": "text", "text": turn.text],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image.base64EncodedString())"]],
                    ],
                ])
            } else {
                messages.append(["role": turn.role.rawValue, "content": turn.text])
            }
        }
        return ["model": request.model, "stream": true, "messages": messages]
    }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        if event.data == "[DONE]" { return .done }
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignore }
        if let error = json["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? (error as? String)
            throw LLMError.api(message: message ?? "Unknown error")
        }
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return .ignore }
        if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
            return .text(text)
        }
        if choice["finish_reason"] as? String == "content_filter" { throw LLMError.refused }
        return .ignore
    }
}
