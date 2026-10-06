import XCTest
@testable import FeatherCore

final class FeatherPlusProviderTests: XCTestCase {
    private func request(model: String = "fast", image: Data? = Data([0xFF, 0xD8])) -> GenerationRequest {
        GenerationRequest(
            system: "sys",
            turns: [Turn(role: .user, text: "hi")],
            imageJPEG: image,
            model: model,
            maxTokens: 100,
            sessionID: "session-123",
            reasoning: .providerDefault
        )
    }

    func testRequestTargetsPlusWithToken() throws {
        let provider = FeatherPlusProvider(token: "fth_x", baseURL: "https://plus.example.com/")
        let urlRequest = try provider.makeURLRequest(for: request())
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://plus.example.com/v1/chat/completions")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer fth_x")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "x-opencode-session"))

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "fast")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["reasoning_effort"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertNotNil(messages[1]["content"] as? [[String: Any]], "the screenshot is attached")
    }

    func testLeavesReasoningToTheServer() {
        XCTAssertFalse(FeatherPlusProvider(token: "t").controlsReasoning)
    }

    func testRequiresTokenAndModel() {
        XCTAssertThrowsError(try FeatherPlusProvider(token: "").makeURLRequest(for: request())) {
            XCTAssertEqual($0 as? LLMError, .missingAPIKey)
        }
        XCTAssertThrowsError(try FeatherPlusProvider(token: "t").makeURLRequest(for: request(model: ""))) {
            XCTAssertEqual($0 as? LLMError, .missingModel)
        }
    }

    func testPreconnectsToHealth() {
        XCTAssertEqual(FeatherPlusProvider(token: "", baseURL: "https://plus.example.com").preconnectURL?.absoluteString, "https://plus.example.com/health")
    }

    func testParsesOpenAICompatibleStream() throws {
        let provider = FeatherPlusProvider(token: "t")
        XCTAssertEqual(try provider.parse(SSEEvent(event: nil, data: #"{"choices":[{"delta":{"content":"Hi"}}]}"#)), .text("Hi"))
        XCTAssertEqual(try provider.parse(SSEEvent(event: nil, data: "[DONE]")), .done)
    }

    func testSettingsBuildPlusProviderFromStoredToken() {
        let store = MemoryCredentialStore()
        let settings = Settings(connection: .featherPlus, model: "fast", hotkey: .optionSpace, includeScreenshot: true, plusBaseURL: "https://plus.example.com")
        XCTAssertFalse(settings.hasCredentials(using: store))
        XCTAssertTrue(store.setPlusToken("fth_x"))
        XCTAssertTrue(settings.hasCredentials(using: store))
        let provider = settings.makeProvider(plusToken: store.plusToken())
        XCTAssertEqual((provider as? FeatherPlusProvider)?.token, "fth_x")
        XCTAssertEqual((provider as? FeatherPlusProvider)?.baseURL, "https://plus.example.com")
    }

    func testStoredPlusConnectionNeedsTheTesterDefaultBeforeLaunch() throws {
        let name = "FeatherPlusProviderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(ConnectionKind.featherPlus.rawValue, forKey: SettingsKey.connection)
        defaults.set("premium", forKey: SettingsKey.model)

        XCTAssertFalse(FeatherPlus.providerLaunched)
        XCTAssertFalse(FeatherPlus.isProviderEnabled(defaults))
        XCTAssertEqual(Settings.current(defaults).connection, .openCodeGo, "a stored Plus choice is ignored before launch")

        defaults.set(true, forKey: SettingsKey.plusProviderEnabled)
        XCTAssertTrue(FeatherPlus.isProviderEnabled(defaults))
        XCTAssertEqual(Settings.current(defaults).connection, .featherPlus)
        XCTAssertEqual(Settings.current(defaults).model, FeatherPlusProvider.defaultModel, "Plus always uses its own model")
    }

    func testModelSwitchesNeverCarryPlusModels() {
        XCTAssertEqual(Settings.model(afterChangingTo: .featherPlus, preserving: OpenCodeGoProvider.defaultModel), "fast")
        XCTAssertEqual(Settings.model(afterChangingTo: .featherPlus, preserving: "custom-model"), "fast")
        XCTAssertEqual(Settings.model(afterChangingTo: .featherPlus, preserving: "premium"), "fast")
        XCTAssertEqual(Settings.model(afterChangingTo: .openCodeGo, preserving: "premium"), OpenCodeGoProvider.defaultModel)
        XCTAssertEqual(Settings.model(afterChangingTo: .chatGPT, preserving: "fast"), ChatGPTModelCatalog.defaultModel)
    }
}
