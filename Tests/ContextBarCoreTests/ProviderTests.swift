import XCTest
@testable import ContextBarCore

final class ProviderTests: XCTestCase {
    func testOpenCodeGoDecodesModels() throws {
        let data = Data(#"{"data":[{"id":"zeta"},{"id":"alpha"},{"id":"zeta"}]}"#.utf8)

        XCTAssertEqual(try OpenCodeGoModelCatalog.decodeModels(data), ["alpha", "zeta"])
    }

    private let image = Data([0xFF, 0xD8, 0xFF])

    private func request(image: Data?) -> GenerationRequest {
        GenerationRequest(
            system: "sys",
            turns: [Turn(role: .user, text: "hi"), Turn(role: .assistant, text: "yo"), Turn(role: .user, text: "shorter")],
            imageJPEG: image,
            model: "model-x",
            maxTokens: 100
        )
    }

    private func requestWithSession() -> GenerationRequest {
        GenerationRequest(
            system: "sys",
            turns: [Turn(role: .user, text: "hi")],
            imageJPEG: nil,
            model: "model-x",
            maxTokens: 100,
            sessionID: "session-123"
        )
    }

    private func json(_ urlRequest: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
    }

    func testOpenCodeGoDefaults() {
        XCTAssertEqual(OpenCodeGoProvider.defaultBaseURL, "https://opencode.ai/zen/go/v1")
        XCTAssertEqual(OpenCodeGoProvider.defaultModel, "deepseek-v4.1-flash")
    }

    func testOpenCodeGoRequestShape() throws {
        let urlRequest = try OpenCodeGoProvider(apiKey: "sk").makeURLRequest(for: request(image: image))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://opencode.ai/zen/go/v1/chat/completions")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk")

        let body = try json(urlRequest)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["max_tokens"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        let first = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(first.map { $0["type"] as? String }, ["text", "image_url"])
        let url = (first[1]["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url, "data:image/jpeg;base64,\(image.base64EncodedString())")
        XCTAssertEqual(messages[2]["content"] as? String, "yo")
    }

    func testOpenCodeGoSendsSessionAndUserAgentHeaders() throws {
        let urlRequest = try OpenCodeGoProvider(apiKey: "sk").makeURLRequest(for: requestWithSession())
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-opencode-session"), "session-123")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "User-Agent"), OpenCodeGoProvider.userAgent)
    }

    func testChatGPTRequestShape() throws {
        let urlRequest = try ChatGPTProvider(accessToken: "token", accountID: "acct").makeURLRequest(for: requestWithSession())
        XCTAssertEqual(urlRequest.url?.absoluteString, ChatGPTProvider.endpoint)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "session-id"), "session-123")
        let body = try json(urlRequest)
        XCTAssertEqual(body["model"] as? String, "model-x")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNotNil(body["input"] as? [[String: Any]])
    }

    func testChatGPTParsesResponseStream() throws {
        let provider = ChatGPTProvider(accessToken: "token")
        XCTAssertEqual(
            try provider.parse(SSEEvent(event: "response.output_text.delta", data: #"{"delta":"Hello"}"#)),
            .text("Hello")
        )
        XCTAssertEqual(try provider.parse(SSEEvent(event: "response.completed", data: "{}")), .done)
    }

    func testOpenCodeGoRequiresKey() {
        XCTAssertThrowsError(try OpenCodeGoProvider(apiKey: "").makeURLRequest(for: request(image: nil))) {
            XCTAssertEqual($0 as? LLMError, .missingAPIKey)
        }
    }

    func testOpenCodeGoRejectsInvalidBaseURL() {
        XCTAssertThrowsError(try OpenCodeGoProvider(apiKey: "key", baseURL: "localhost").makeURLRequest(for: request(image: nil))) {
            XCTAssertEqual($0 as? LLMError, .invalidBaseURL)
        }
    }

    func testOpenCodeGoParsesStream() throws {
        let provider = OpenCodeGoProvider(apiKey: "key")
        XCTAssertEqual(try provider.parse(SSEEvent(data: #"{"choices":[{"delta":{"role":"assistant"}}]}"#)), .ignore)
        XCTAssertEqual(try provider.parse(SSEEvent(data: #"{"choices":[{"delta":{"content":"Hi"}}]}"#)), .text("Hi"))
        XCTAssertEqual(try provider.parse(SSEEvent(data: "[DONE]")), .done)
        XCTAssertThrowsError(try provider.parse(SSEEvent(data: #"{"error":{"message":"bad model"}}"#))) {
            XCTAssertEqual($0 as? LLMError, .api(message: "bad model"))
        }
    }

    func testErrorMessageFromBody() {
        let provider = OpenCodeGoProvider(apiKey: "key")
        let body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        XCTAssertEqual(provider.errorMessage(fromBody: body), "invalid x-api-key")
    }
}
