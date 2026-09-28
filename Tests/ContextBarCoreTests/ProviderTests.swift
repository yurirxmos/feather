import XCTest
@testable import ContextBarCore

final class ProviderTests: XCTestCase {
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

    private func json(_ urlRequest: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
    }

    // MARK: Anthropic

    func testAnthropicRequestShape() throws {
        let urlRequest = try AnthropicProvider(apiKey: "key", baseURL: "https://api.anthropic.com/").makeURLRequest(for: request(image: image))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "key")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try json(urlRequest)
        XCTAssertEqual(body["model"] as? String, "model-x")
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["system"] as? String, "sys")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let first = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(first.map { $0["type"] as? String }, ["image", "text"])
        let source = try XCTUnwrap(first[0]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, image.base64EncodedString())
        let second = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(second.map { $0["type"] as? String }, ["text"])
    }

    func testAnthropicWithoutImageSendsTextOnly() throws {
        let body = try json(AnthropicProvider(apiKey: "key").makeURLRequest(for: request(image: nil)))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let first = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(first.map { $0["type"] as? String }, ["text"])
    }

    func testAnthropicRequiresKey() {
        XCTAssertThrowsError(try AnthropicProvider(apiKey: "").makeURLRequest(for: request(image: nil))) {
            XCTAssertEqual($0 as? LLMError, .missingAPIKey)
        }
    }

    func testAnthropicParsesStream() throws {
        let provider = AnthropicProvider(apiKey: "key")
        XCTAssertEqual(try provider.parse(SSEEvent(event: "message_start", data: #"{"type":"message_start","message":{}}"#)), .ignore)
        XCTAssertEqual(
            try provider.parse(SSEEvent(data: #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#)),
            .text("Hello")
        )
        XCTAssertEqual(
            try provider.parse(SSEEvent(data: #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"x"}}"#)),
            .ignore
        )
        XCTAssertEqual(try provider.parse(SSEEvent(data: #"{"type":"message_stop"}"#)), .done)
        XCTAssertThrowsError(try provider.parse(SSEEvent(data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))) {
            XCTAssertEqual($0 as? LLMError, .api(message: "Overloaded"))
        }
        XCTAssertThrowsError(try provider.parse(SSEEvent(data: #"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#))) {
            XCTAssertEqual($0 as? LLMError, .refused)
        }
    }

    // MARK: OpenAI-compatible

    func testOpenAIRequestShape() throws {
        let urlRequest = try OpenAICompatibleProvider(apiKey: "sk", baseURL: "http://localhost:11434/v1").makeURLRequest(for: request(image: image))
        XCTAssertEqual(urlRequest.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
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

    func testOpenAIWithoutKeyOmitsAuthorization() throws {
        let urlRequest = try OpenAICompatibleProvider(apiKey: "").makeURLRequest(for: request(image: nil))
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenAIRejectsInvalidBaseURL() {
        XCTAssertThrowsError(try OpenAICompatibleProvider(apiKey: "", baseURL: "localhost").makeURLRequest(for: request(image: nil))) {
            XCTAssertEqual($0 as? LLMError, .invalidBaseURL)
        }
    }

    func testOpenAIParsesStream() throws {
        let provider = OpenAICompatibleProvider(apiKey: "")
        XCTAssertEqual(try provider.parse(SSEEvent(data: #"{"choices":[{"delta":{"role":"assistant"}}]}"#)), .ignore)
        XCTAssertEqual(try provider.parse(SSEEvent(data: #"{"choices":[{"delta":{"content":"Hi"}}]}"#)), .text("Hi"))
        XCTAssertEqual(try provider.parse(SSEEvent(data: "[DONE]")), .done)
        XCTAssertThrowsError(try provider.parse(SSEEvent(data: #"{"error":{"message":"bad model"}}"#))) {
            XCTAssertEqual($0 as? LLMError, .api(message: "bad model"))
        }
    }

    func testErrorMessageFromBody() {
        let provider = AnthropicProvider(apiKey: "key")
        let body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        XCTAssertEqual(provider.errorMessage(fromBody: body), "invalid x-api-key")
    }
}
