import Foundation

/// Feather Cloud's streaming chat completions endpoint. It speaks the same OpenAI-compatible
/// wire format as OpenCode Go, but authenticates with the user's Feather account token and
/// leaves model routing and quotas to the server.
///
/// Not selectable in Settings yet: there is no `ConnectionKind` case, so nothing in the app
/// builds this provider until the service launches.
public struct FeatherCloudProvider: LLMProvider {
    public var accountToken: String
    public var baseURL: String

    public init(accountToken: String, baseURL: String) {
        self.accountToken = accountToken
        self.baseURL = baseURL
    }

    private var wire: OpenCodeGoProvider {
        OpenCodeGoProvider(apiKey: accountToken, baseURL: baseURL)
    }

    public func makeURLRequest(for request: GenerationRequest) throws -> URLRequest {
        try wire.makeURLRequest(for: request)
    }

    public func parse(_ event: SSEEvent) throws -> StreamChunk {
        try wire.parse(event)
    }

    public var controlsReasoning: Bool { wire.controlsReasoning }

    public var preconnectURL: URL? { wire.preconnectURL }
}
