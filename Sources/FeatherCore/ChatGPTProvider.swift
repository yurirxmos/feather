import Foundation

/// ChatGPT account access through the Codex Responses API.
public struct ChatGPTProvider: LLMProvider {
    public var accessToken: String
    public var accountID: String?

    public static let endpoint = "https://chatgpt.com/backend-api/codex/responses"
    public static let userAgent = ProviderTransport.userAgent

    public init(accessToken: String, accountID: String? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw LLMError.missingAPIKey }
        guard !request.model.isEmpty else { throw LLMError.missingModel }
        var headers: [String: String] = [:]
        if let accountID, !accountID.isEmpty { headers["ChatGPT-Account-Id"] = accountID }
        return try ProviderTransport.request(
            endpoint: URL(string: Self.endpoint)!,
            token: accessToken,
            sessionHeader: ("session-id", request.sessionID),
            extraHeaders: headers,
            body: body(for: request)
        )
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
        if json["error"] != nil {
            throw ProviderTransport.streamError(from: Data(event.data.utf8))
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
