import XCTest
@testable import FeatherCore

final class OpenAIModelCatalogTests: XCTestCase {
    func testKeepsChatModelsNewestFirst() throws {
        let body = Data(#"""
        {"data":[
            {"id":"gpt-5.4","created":200},
            {"id":"gpt-5.4-mini","created":300},
            {"id":"o4-mini","created":100},
            {"id":"gpt-5.4-2026-03-01","created":250},
            {"id":"gpt-image-2","created":400},
            {"id":"gpt-realtime","created":400},
            {"id":"gpt-4o-mini-tts","created":400},
            {"id":"gpt-5.3-codex","created":400},
            {"id":"gpt-5-pro","created":400},
            {"id":"text-embedding-3-large","created":400},
            {"id":"dall-e-3","created":400},
            {"id":"omni-moderation-latest","created":400}
        ]}
        """#.utf8)
        XCTAssertEqual(try OpenAIModelCatalog.decodeModels(body), ["gpt-5.4-mini", "gpt-5.4", "o4-mini"])
        XCTAssertThrowsError(try OpenAIModelCatalog.decodeModels(Data("not json".utf8)))
    }

    func testAModelTheKeyLacksFallsBackToTheDefaultThenTheNewest() {
        XCTAssertEqual(OpenAIModelCatalog.model(for: ["a", OpenAIProvider.defaultModel], current: "a"), "a")
        XCTAssertEqual(OpenAIModelCatalog.model(for: ["a", OpenAIProvider.defaultModel], current: "gone"), OpenAIProvider.defaultModel)
        XCTAssertEqual(OpenAIModelCatalog.model(for: ["a", "b"], current: "gone"), "a")
        XCTAssertNil(OpenAIModelCatalog.model(for: [], current: "a"))
    }
}
