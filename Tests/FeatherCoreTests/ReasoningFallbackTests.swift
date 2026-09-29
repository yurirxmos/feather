import XCTest
@testable import FeatherCore

final class ReasoningFallbackTests: XCTestCase {
    override func tearDown() {
        StubProtocol.handler = nil
        super.tearDown()
    }

    func testOpenCodeGoAsksForMinimalReasoningByDefault() throws {
        let request = GenerationRequest(system: "s", turns: [Turn(role: .user, text: "hi")], imageJPEG: nil, model: "m", maxTokens: 10)
        let body = OpenCodeGoProvider(apiKey: "key").body(for: request)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")

        var fallback = request
        fallback.reasoning = .providerDefault
        XCTAssertNil(OpenCodeGoProvider(apiKey: "key").body(for: fallback)["reasoning_effort"])
    }

    func testChatGPTBodyIsUnchangedByReasoning() {
        let request = GenerationRequest(system: "s", turns: [Turn(role: .user, text: "hi")], imageJPEG: nil, model: "m", maxTokens: 10)
        XCTAssertNil(ChatGPTProvider(accessToken: "t").body(for: request)["reasoning"])
        XCTAssertFalse(ChatGPTProvider(accessToken: "t").controlsReasoning)
    }

    func testRetriesWithoutReasoningControlWhenTheModelRejectsIt() async throws {
        let model = "rejects-\(UUID().uuidString)"
        let bodies = RequestLog()
        StubProtocol.handler = { request in
            let body = request.bodyJSON()
            bodies.append(body)
            if body["reasoning_effort"] != nil {
                return (400, Data(#"{"error":{"message":"invalid thinking"}}"#.utf8))
            }
            return (200, Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n".utf8))
        }
        let provider = OpenCodeGoProvider(apiKey: "key")
        let request = GenerationRequest(system: "s", turns: [Turn(role: .user, text: "hi")], imageJPEG: nil, model: model, maxTokens: 10)

        var text = ""
        for try await chunk in provider.stream(request, session: .stubbed) { text += chunk }
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(bodies.count, 2)
        XCTAssertTrue(ReasoningSupport.shared.rejectsMinimal(model))

        // The remembered model skips the rejected attempt.
        text = ""
        for try await chunk in provider.stream(request, session: .stubbed) { text += chunk }
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(bodies.count, 3)
    }

    func testReportsTheErrorWhenTheRetryAlsoFails() async {
        let model = "broken-\(UUID().uuidString)"
        StubProtocol.handler = { _ in (400, Data(#"{"error":{"message":"bad image"}}"#.utf8)) }
        let request = GenerationRequest(system: "s", turns: [Turn(role: .user, text: "hi")], imageJPEG: nil, model: model, maxTokens: 10)
        do {
            for try await _ in OpenCodeGoProvider(apiKey: "key").stream(request, session: .stubbed) {}
            XCTFail("Expected an HTTP error")
        } catch {
            XCTAssertEqual(error as? LLMError, .http(status: 400, message: "bad image"))
        }
        XCTAssertFalse(ReasoningSupport.shared.rejectsMinimal(model))
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []

    var count: Int { lock.withLock { bodies.count } }

    func append(_ body: [String: Any]) {
        lock.withLock { bodies.append(body) }
    }
}

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static let stubbed: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }()
}

private extension URLRequest {
    /// URLProtocol receives uploads as a stream rather than `httpBody`.
    func bodyJSON() -> [String: Any] {
        var data = httpBody ?? Data()
        if data.isEmpty, let stream = httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
