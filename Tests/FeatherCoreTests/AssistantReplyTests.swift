import XCTest
@testable import FeatherCore

final class AssistantReplyTests: XCTestCase {
    func testTypeAssistHasNoAnswer() {
        let reply = AssistantReply(parsing: "  <answer>x</answer> text ", mode: .typeAssist)
        XCTAssertEqual(reply, AssistantReply(suggestion: "<answer>x</answer> text"))
    }

    func testAssistantSplitsTheAnswerFromTheSuggestion() {
        let reply = AssistantReply(parsing: "<answer>Paris.</answer>\n\nIt is Paris!", mode: .assistant)
        XCTAssertEqual(reply, AssistantReply(answer: "Paris.", suggestion: "It is Paris!"))
        XCTAssertEqual(reply.raw, "<answer>Paris.</answer>\n\nIt is Paris!")
    }

    func testAssistantWithoutAnAnswerIsAllSuggestion() {
        let reply = AssistantReply(parsing: "Sure, tomorrow works.", mode: .assistant)
        XCTAssertEqual(reply, AssistantReply(suggestion: "Sure, tomorrow works."))
        XCTAssertEqual(reply.raw, "Sure, tomorrow works.")
    }

    func testStreamingNeverShowsAHalfWrittenTag() {
        XCTAssertEqual(AssistantReply(parsing: "<ans", mode: .assistant), AssistantReply())
        XCTAssertEqual(AssistantReply(parsing: "<answer>Par", mode: .assistant), AssistantReply(answer: "Par"))
        XCTAssertEqual(AssistantReply(parsing: "<answer>Paris.</ans", mode: .assistant).answer, "Paris.")
        XCTAssertEqual(
            AssistantReply(parsing: "<answer>Paris.</answer>\n\nIt is", mode: .assistant),
            AssistantReply(answer: "Paris.", suggestion: "It is")
        )
    }

    func testOnlyTheAssistantModeAnswersQuestions() {
        XCTAssertFalse(PromptBuilder.systemPrompt(customInstructions: "").contains("<answer>"))
        let assistant = PromptBuilder.systemPrompt(customInstructions: "No emojis", mode: .assistant)
        XCTAssertTrue(assistant.hasPrefix("You are Feather, a writing assistant"))
        XCTAssertTrue(assistant.contains("always suggest text"))
        XCTAssertTrue(assistant.contains("<writing-preferences>\nNo emojis\n</writing-preferences>"))
    }
}
