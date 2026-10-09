import XCTest
@testable import FeatherCore

final class ReplyCleanupTests: XCTestCase {
    private let comment = "Essa publicação resume muito bem a jornada de qualquer programador. A primeira vez que conseguimos fazer algo funcionar é sempre um momento de realização."

    func testStripsAnIntroductionSeparatorsAndAClosingRemark() {
        let wrapped = "Aqui está um comentário inteligente e bem elaborado para a publicação de Michael Santos:\n\n---\n\n\(comment)\n\n---\n\nEspero que isso ajude!"
        XCTAssertEqual(ReplyCleanup.unwrap(wrapped), comment)
        XCTAssertEqual(ReplyCleanup.unwrap("```\n\(comment)\n```"), comment)
    }

    func testStripsAnIntroductionWithoutSeparators() {
        XCTAssertEqual(ReplyCleanup.unwrap("Here's a reply:\n\n\(comment)\n\nHope this helps!"), comment)
        XCTAssertEqual(ReplyCleanup.unwrap("Claro! Segue a mensagem:\n\(comment)"), comment)
    }

    func testHidesAnIntroductionUntilTheTextArrives() {
        XCTAssertEqual(ReplyCleanup.unwrap("Aqui está um comentário:"), "")
        XCTAssertEqual(ReplyCleanup.unwrap("Aqui está um comentário:\n\n---\n\nEssa publi"), "Essa publi")
    }

    func testKeepsOrdinaryMessages() {
        XCTAssertEqual(ReplyCleanup.unwrap("Dear team:\n\nThe report is ready."), "Dear team:\n\nThe report is ready.")
        XCTAssertEqual(ReplyCleanup.unwrap("The report is ready.\n\nLet me know if you have questions."), "The report is ready.\n\nLet me know if you have questions.")
        let sections = "\(comment)\n\n---\n\nSecond part of a longer text that is clearly not a short remark, with enough words."
        XCTAssertEqual(ReplyCleanup.unwrap(sections), sections)
        XCTAssertEqual(ReplyCleanup.unwrap("Sure, tomorrow works."), "Sure, tomorrow works.")
        XCTAssertEqual(ReplyCleanup.unwrap("Surely not:\nok"), "Surely not:\nok")
    }

    func testStripsQuotesAroundTheWholeTextOnly() {
        XCTAssertEqual(ReplyCleanup.unwrap("\"Tomorrow at 2 pm works!\""), "Tomorrow at 2 pm works!")
        XCTAssertEqual(ReplyCleanup.unwrap("“Combinado!”"), "Combinado!")
        XCTAssertEqual(ReplyCleanup.unwrap("\"Yes\" is my answer, \"no\" is not"), "\"Yes\" is my answer, \"no\" is not")
    }

    func testRepliesAreCleanedInBothModes() {
        let wrapped = "Aqui está:\n\n---\n\nCombinado!\n\n---"
        XCTAssertEqual(AssistantReply(parsing: wrapped, mode: .typeAssist).suggestion, "Combinado!")
        XCTAssertEqual(AssistantReply(parsing: wrapped, mode: .assistant).suggestion, "Combinado!")
        XCTAssertEqual(AssistantReply(parsing: "<answer>Sim.</answer>\n\n\(wrapped)", mode: .assistant).suggestion, "Combinado!")
    }
}
