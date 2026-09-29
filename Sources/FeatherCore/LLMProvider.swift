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
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return String(data: body, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = json["error"] as? String { return message }
        return json["message"] as? String
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
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 64_000 { break }
                        }
                        throw LLMError.http(status: status, message: errorMessage(fromBody: body))
                    }
                    var parser = SSEParser()
                    lineLoop: for try await line in bytes.lines {
                        for event in parser.push(line + "\n") {
                            switch try parse(event) {
                            case .text(let text): continuation.yield(text)
                            case .done: break lineLoop
                            case .ignore: continue
                            }
                        }
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
