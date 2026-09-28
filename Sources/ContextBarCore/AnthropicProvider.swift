import Foundation

/// Claude through the Messages API (`POST /v1/messages`) with streaming.
public struct AnthropicProvider: LLMProvider {
    public var apiKey: String
    public var baseURL: String

    public init(apiKey: String, baseURL: String = ProviderKind.anthropic.defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        var urlRequest = URLRequest(url: try .endpoint(base: baseURL, path: "/v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request), options: [.sortedKeys])
        return urlRequest
    }

    func body(for request: GenerationRequest) -> [String: Any] {
        let messages: [[String: Any]] = request.turns.enumerated().map { index, turn in
            var content: [[String: Any]] = []
            if index == 0, let image = request.imageJPEG {
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()],
                ])
            }
            content.append(["type": "text", "text": turn.text])
            return ["role": turn.role.rawValue, "content": content]
        }
        return [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "system": request.system,
            "messages": messages,
        ]
    }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return .ignore }
        switch type {
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return .ignore }
            return .text(text)
        case "message_delta":
            if let delta = json["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                throw LLMError.refused
            }
            return .ignore
        case "message_stop":
            return .done
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String
            throw LLMError.api(message: message ?? "Unknown error")
        default:
            return .ignore
        }
    }
}
