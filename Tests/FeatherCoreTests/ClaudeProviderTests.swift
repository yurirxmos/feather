import XCTest
@testable import FeatherCore

final class ClaudeProviderTests: XCTestCase {
    private let image = Data([0xFF, 0xD8, 0xFF])

    private func request(image: Data?) -> GenerationRequest {
        GenerationRequest(
            system: "sys",
            turns: [Turn(role: .user, text: "hi"), Turn(role: .assistant, text: "yo"), Turn(role: .user, text: "shorter")],
            imageJPEG: image,
            model: "claude-haiku-5-5",
            maxTokens: 100
        )
    }

    private func json(_ urlRequest: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
    }

    func testDefaults() {
        XCTAssertEqual(ClaudeProvider.defaultBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(ConnectionKind.claude.defaultModel, ClaudeProvider.defaultModel)
    }

    func testRequestShape() throws {
        let urlRequest = try ClaudeProvider(apiKey: "sk-ant").makeURLRequest(for: request(image: image))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))

        let body = try json(urlRequest)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        XCTAssertEqual(body["system"] as? String, "sys")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let first = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(first.map { $0["type"] as? String }, ["image", "text"])
        let source = try XCTUnwrap(first[0]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, image.base64EncodedString())
    }

    func testRequestWithoutImageUsesPlainText() throws {
        let body = try json(ClaudeProvider(apiKey: "k").makeURLRequest(for: request(image: nil)))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, "hi")
    }

    func testRequiresKeyAndModel() {
        XCTAssertThrowsError(try ClaudeProvider(apiKey: "").makeURLRequest(for: request(image: nil))) {
            XCTAssertEqual($0 as? LLMError, .missingAPIKey)
        }
        var noModel = request(image: nil)
        noModel.model = ""
        XCTAssertThrowsError(try ClaudeProvider(apiKey: "k").makeURLRequest(for: noModel)) {
            XCTAssertEqual($0 as? LLMError, .missingModel)
        }
    }

    func testParsesStream() throws {
        let provider = ClaudeProvider(apiKey: "k")
        let delta = SSEEvent(event: "content_block_delta", data: #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#)
        XCTAssertEqual(try provider.parse(delta), .text("Hel"))
        let ping = SSEEvent(event: "ping", data: #"{"type":"ping"}"#)
        XCTAssertEqual(try provider.parse(ping), .ignore)
        let stop = SSEEvent(event: "message_stop", data: #"{"type":"message_stop"}"#)
        XCTAssertEqual(try provider.parse(stop), .done)
    }

    func testStreamErrorAndRefusal() {
        let provider = ClaudeProvider(apiKey: "k")
        let error = SSEEvent(event: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        XCTAssertThrowsError(try provider.parse(error)) {
            XCTAssertEqual($0 as? LLMError, .api(message: "Overloaded"))
        }
        let refusal = SSEEvent(event: "message_delta", data: #"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#)
        XCTAssertThrowsError(try provider.parse(refusal)) {
            XCTAssertEqual($0 as? LLMError, .refused)
        }
    }

    func testDecodesModels() throws {
        let data = Data(#"{"data":[{"id":"claude-b","display_name":"B"},{"id":"claude-a"}],"has_more":false}"#.utf8)
        XCTAssertEqual(try ClaudeModelCatalog.decodeModels(data), ["claude-b", "claude-a"])
    }

    func testCredentialsAndSetUp() {
        let store = MemoryCredentialStore()
        XCTAssertFalse(Settings.providersSetUp(in: store, plusAvailable: false).contains(.claude))
        _ = store.setClaudeAPIKey(" sk-ant ")
        XCTAssertEqual(store.claudeAPIKey(), "sk-ant")
        XCTAssertTrue(Settings.providersSetUp(in: store, plusAvailable: false).contains(.claude))
        store.deleteClaudeAPIKey()
        XCTAssertNil(store.claudeAPIKey())
    }
}
