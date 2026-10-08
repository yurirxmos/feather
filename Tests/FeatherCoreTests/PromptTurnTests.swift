import XCTest
@testable import FeatherCore

final class PromptTurnTests: XCTestCase {
    func testClosingCountdownHasThreeTicks() {
        XCTAssertEqual(PromptTurn.closingCountdownSeconds, [3, 2, 1])
    }

    func testMergeAddsOnlyNewWindowTextLines() {
        XCTAssertEqual(PromptTurn.mergeWindowText("one\ntwo\nthree", with: "one\ntwo"), "one\ntwo\nthree")
        XCTAssertEqual(PromptTurn.mergeWindowText("one\ntwo", with: "one\ntwo"), "one\ntwo")
        XCTAssertEqual(PromptTurn.mergeWindowText(nil, with: "existing"), "existing")
    }

    func testSubmissionChoosesGenerateInsertOrNoop() {
        XCTAssertEqual(PromptTurn.submission(instruction: "  refine  ", result: "answer", isGenerating: false), .generate("refine"))
        XCTAssertEqual(PromptTurn.submission(instruction: " \n", result: "answer", isGenerating: false), .insert)
        XCTAssertEqual(PromptTurn.submission(instruction: "", result: "answer", isGenerating: true), .none)
        XCTAssertEqual(PromptTurn.submission(instruction: "", result: "", isGenerating: false), .none)
    }

    func testAnAnswerWithoutASuggestionIsCopied() {
        XCTAssertEqual(PromptTurn.submission(instruction: "", result: "", answer: "Paris.", isGenerating: false), .copy)
        XCTAssertEqual(PromptTurn.submission(instruction: "", result: "Text", answer: "Paris.", isGenerating: false), .insert)
        XCTAssertEqual(PromptTurn.submission(instruction: "", result: "", answer: "Paris.", isGenerating: true), .none)
        XCTAssertEqual(PromptTurn.copyableText(result: "", answer: "Paris."), "Paris.")
        XCTAssertEqual(PromptTurn.copyableText(result: "Text", answer: "Paris."), "Text")
    }

    func testQuestionsAreRecognizedWithoutCatchingOrdinaryMessages() {
        for question in ["qual a capital da frança", "o que é vacilão", "what's the deadline", "tá atrasado?", "Por que não veio?"] {
            XCTAssertTrue(PromptTurn.looksLikeQuestion(question), question)
        }
        for message in ["fale que ele é um vacilão", "como combinado, segue o arquivo", "when you get home call me", ""] {
            XCTAssertFalse(PromptTurn.looksLikeQuestion(message), message)
        }
    }

    func testHistoryOnlyAppendsCompletedResults() {
        let existing = [Exchange(instruction: "first", result: "one")]
        XCTAssertEqual(PromptTurn.history(existing, lastInstruction: "second", result: "two", isGenerating: false), existing + [Exchange(instruction: "second", result: "two")])
        XCTAssertEqual(PromptTurn.history(existing, lastInstruction: "second", result: "two", isGenerating: true), existing)
        XCTAssertEqual(PromptTurn.history(existing, lastInstruction: "second", result: "", isGenerating: false), existing)
    }

    func testKeyCommandsMapOnlyExpectedModifierCombinations() {
        XCTAssertEqual(PromptTurn.command(for: PromptKeyInput(keyCode: 53, command: false)), .cancel)
        XCTAssertEqual(PromptTurn.command(for: PromptKeyInput(keyCode: 36, command: true)), .copy)
        XCTAssertEqual(PromptTurn.command(for: PromptKeyInput(keyCode: 76, command: false)), .submit)
        XCTAssertEqual(PromptTurn.command(for: PromptKeyInput(keyCode: 15, command: true, characters: "R")), .regenerate)
        XCTAssertNil(PromptTurn.command(for: PromptKeyInput(keyCode: 36, command: true, shift: true)))
        XCTAssertNil(PromptTurn.command(for: PromptKeyInput(keyCode: 36, command: false, option: true)))
    }
}
