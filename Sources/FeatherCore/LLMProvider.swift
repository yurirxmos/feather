import Foundation

public struct Turn: Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct GenerationRequest: Equatable, Sendable {
    public var system: String
    /// Alternating user/assistant turns, starting and ending with a user turn.
    public var turns: [Turn]
    /// Attached to the first user turn.
    public var imageJPEG: Data?
    public var model: String
    public var maxTokens: Int
    public var sessionID: String

    public init(
        system: String,
        turns: [Turn],
        imageJPEG: Data?,
        model: String,
        maxTokens: Int,
        sessionID: String = ""
    ) {
        self.system = system
        self.turns = turns
        self.imageJPEG = imageJPEG
        self.model = model
        self.maxTokens = maxTokens
        self.sessionID = sessionID
    }
}

public enum StreamChunk: Equatable, Sendable {
    case text(String)
    case done
    case ignore
}

public enum LLMError: Error, Equatable, Sendable {
    case missingAPIKey
    case missingModel
    case invalidBaseURL
    case http(status: Int, message: String?)
    case api(message: String)
    case refused
}

public enum ConnectionKind: String, CaseIterable, Sendable {
    case openCodeGo
    case chatGPT

    public var defaultModel: String {
        switch self {
        case .openCodeGo: OpenCodeGoProvider.defaultModel
        case .chatGPT: ChatGPTModelCatalog.defaultModel
        }
    }
}

/// A chat backend that streams text over server-sent events.
public protocol LLMProvider: Sendable {
    func makeURLRequest(for request: GenerationRequest) throws -> URLRequest
    func parse(_ event: SSEEvent) throws -> StreamChunk
    func errorMessage(fromBody body: Data) -> String?
}

extension LLMProvider {
    public func errorMessage(fromBody body: Data) -> String? {
        ProviderTransport.errorMessage(from: body)
    }

    /// Streams text deltas. Cancelling the consuming task cancels the HTTP request.
    public func stream(
        _ request: GenerationRequest,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(for: request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        let body = try await LLMStreamPump.readErrorBody(from: bytes)
                        throw LLMStreamPump.httpError(statusCode: status, body: body, provider: self)
                    }
                    for try await text in LLMStreamPump.stream(lines: bytes.lines, parse: { try self.parse($0) }) {
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension URL {
    /// Parses a user-entered base URL and appends `path`, tolerating a trailing slash.
    static func endpoint(base: String, path: String) throws -> URL {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + path), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil
        else {
            throw LLMError.invalidBaseURL
        }
        return url
    }
}
