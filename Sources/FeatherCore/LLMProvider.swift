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
    public enum Reasoning: Equatable, Sendable {
        /// Asks the model to skip extended reasoning. Writing short text rarely needs it, and it
        /// can delay the first word by tens of seconds.
        case minimal
        /// Leaves reasoning to the model's own default.
        case providerDefault
    }

    public var system: String
    /// Alternating user/assistant turns, starting and ending with a user turn.
    public var turns: [Turn]
    /// Attached to the first user turn.
    public var imageJPEG: Data?
    public var model: String
    public var maxTokens: Int
    public var sessionID: String
    public var reasoning: Reasoning

    public init(
        system: String,
        turns: [Turn],
        imageJPEG: Data?,
        model: String,
        maxTokens: Int,
        sessionID: String = "",
        reasoning: Reasoning = .minimal
    ) {
        self.system = system
        self.turns = turns
        self.imageJPEG = imageJPEG
        self.model = model
        self.maxTokens = maxTokens
        self.sessionID = sessionID
        self.reasoning = reasoning
    }
}

public enum StreamChunk: Equatable, Sendable {
    case text(String)
    /// The last text of the response; the stream ends after it.
    case finalText(String)
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
    case timedOut
    /// The stream stopped sending text before it said it was done.
    case stalled
    /// The request never reached the provider.
    case network
}

public enum ConnectionKind: String, CaseIterable, Sendable {
    case openCodeGo
    case openAI
    case claude
    case featherPlus

    public var defaultModel: String {
        switch self {
        case .openCodeGo: OpenCodeGoProvider.defaultModel
        case .openAI: OpenAIProvider.defaultModel
        case .claude: ClaudeProvider.defaultModel
        case .featherPlus: FeatherPlusProvider.defaultModel
        }
    }
}

/// A chat backend that streams text over server-sent events.
public protocol LLMProvider: Sendable {
    func makeURLRequest(for request: GenerationRequest) throws -> URLRequest
    func parse(_ event: SSEEvent) throws -> StreamChunk
    func errorMessage(fromBody body: Data) -> String?
    /// Whether `GenerationRequest.reasoning` changes the request body.
    var controlsReasoning: Bool { get }
    /// A URL on the provider's host that is cheap to request without credentials.
    var preconnectURL: URL? { get }
}

extension LLMProvider {
    public func errorMessage(fromBody body: Data) -> String? {
        ProviderTransport.errorMessage(from: body)
    }

    public var controlsReasoning: Bool { false }
    public var preconnectURL: URL? { nil }

    /// Opens the connection to the provider before the prompt is ready, so DNS, TCP, and TLS
    /// are done when the user submits. Sends no credentials, prompt, or screen content.
    public func preconnect(session: URLSession = .shared) async {
        guard let url = preconnectURL else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        request.setValue(ProviderTransport.userAgent, forHTTPHeaderField: "User-Agent")
        _ = try? await session.data(for: request)
    }

    /// Streams text deltas. Cancelling the consuming task cancels the HTTP request. The stream
    /// fails with `LLMError.timedOut` once `deadline` passes.
    public func stream(
        _ request: GenerationRequest,
        session: URLSession = .shared,
        deadline: Duration = LLMStreamPump.responseDeadline
    ) -> AsyncThrowingStream<String, Error> {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    var request = request
                    if !controlsReasoning || ReasoningSupport.shared.rejectsMinimal(request.model) {
                        request.reasoning = .providerDefault
                    }
                    var (bytes, status) = try await open(request, session: session)
                    // Some models reject the reasoning control. Ask again with the model's
                    // default and remember it, so later requests skip the failed attempt.
                    if status == 400, request.reasoning == .minimal {
                        request.reasoning = .providerDefault
                        (bytes, status) = try await open(request, session: session)
                        if (200..<300).contains(status) {
                            ReasoningSupport.shared.markMinimalRejected(request.model)
                        }
                    }
                    guard (200..<300).contains(status) else {
                        let body = try await LLMStreamPump.readErrorBody(from: bytes)
                        throw LLMStreamPump.httpError(statusCode: status, body: body, provider: self)
                    }
                    for try await text in LLMStreamPump.stream(lines: bytes.lines, parse: { try self.parse($0) }) {
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch let error as URLError where error.code != .cancelled {
                    continuation.finish(throwing: LLMError.network)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return LLMStreamPump.limit(stream, to: deadline)
    }

    private func open(
        _ request: GenerationRequest,
        session: URLSession
    ) async throws -> (URLSession.AsyncBytes, Int) {
        let (bytes, response) = try await session.bytes(for: makeURLRequest(for: request))
        return (bytes, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Models that returned HTTP 400 for `GenerationRequest.Reasoning.minimal` during this launch.
public final class ReasoningSupport: @unchecked Sendable {
    public static let shared = ReasoningSupport()

    private let lock = NSLock()
    private var rejectingModels: Set<String> = []

    public init() {}

    public func rejectsMinimal(_ model: String) -> Bool {
        lock.withLock { rejectingModels.contains(model) }
    }

    public func markMinimalRejected(_ model: String) {
        lock.withLock { _ = rejectingModels.insert(model) }
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
