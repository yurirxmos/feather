import XCTest
@testable import FeatherCore

final class ChatGPTModelCatalogTests: XCTestCase {
    func testReadsTheAccountModelsInServerOrder() {
        let body = Data(#"""
        {"models":[
            {"slug":"gpt-5.5","display_name":"GPT-5.5","visibility":"list"},
            {"slug":"internal","visibility":"hide"},
            {"id":"gpt-5.4-mini"},
            {"slug":"gpt-5.5"}
        ]}
        """#.utf8)
        XCTAssertEqual(
            ChatGPTModelCatalog.decodeModels(body),
            [ChatGPTModel(id: "gpt-5.5", name: "GPT-5.5"), ChatGPTModel(id: "gpt-5.4-mini", name: "gpt-5.4-mini")]
        )
        XCTAssertEqual(ChatGPTModelCatalog.decodeModels(Data(#"[{"slug":"a"}]"#.utf8)).count, 1)
        XCTAssertTrue(ChatGPTModelCatalog.decodeModels(Data("not json".utf8)).isEmpty)
    }

    func testAModelTheAccountLacksFallsBackToTheDefaultThenTheFirst() {
        let withDefault = [ChatGPTModel(id: "a", name: "a"), ChatGPTModel(id: ChatGPTModelCatalog.defaultModel, name: "d")]
        XCTAssertEqual(ChatGPTModelCatalog.model(for: withDefault, current: "a"), "a")
        XCTAssertEqual(ChatGPTModelCatalog.model(for: withDefault, current: "gone"), ChatGPTModelCatalog.defaultModel)
        let withoutDefault = [ChatGPTModel(id: "a", name: "a"), ChatGPTModel(id: "b", name: "b")]
        XCTAssertEqual(ChatGPTModelCatalog.model(for: withoutDefault, current: ChatGPTModelCatalog.defaultModel), "a")
        XCTAssertNil(ChatGPTModelCatalog.model(for: [], current: "a"))
    }
}
