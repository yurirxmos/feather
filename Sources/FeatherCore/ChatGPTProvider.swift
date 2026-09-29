import Foundation

/// ChatGPT account access through the Codex Responses API.
public struct ChatGPTProvider: LLMProvider {
    public var accessToken: String
    public var accountID: String?

    public static let endpoint = "https://chatgpt.com/backend-api/codex/responses"
    public static let userAgent = "Feather/0.1.0"

    public init(accessToken: String, accountID: String? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw LLMError.missingAPIKey }
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        var urlRequest = URLRequest(url: URL(string: Self.endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            urlRequest.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        if !request.sessionID.isEmpty {
            urlRequest.setValue(request.sessionID, forHTTPHeaderField: "session-id")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request), options: [.sortedKeys])
        return urlRequest
    }

    func body(for request: GenerationRequest) -> [String: Any] {
        var input: [[String: Any]] = []
        for (index, turn) in request.turns.enumerated() {
            var content: [[String: Any]] = [["type": "input_text", "text": turn.text]]
            if index == 0, let image = request.imageJPEG {
                content.append(["type": "input_image", "image_url": "data:image/jpeg;base64,\(image.base64EncodedString())"])
            }
            input.append(["role": turn.role.rawValue, "content": content])
        }
        return [
            "model": request.model,
            "instructions": request.system,
            "input": input,
            "stream": true,
        ]
    }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        guard let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignore }
        if let error = json["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? (error as? String)
            throw LLMError.api(message: message ?? "Unknown error")
        }
        switch event.event {
        case "response.output_text.delta":
            return (json["delta"] as? String).map(StreamChunk.text) ?? .ignore
        case "response.completed", "response.done":
            return .done
        default:
            return .ignore
        }
    }
}
