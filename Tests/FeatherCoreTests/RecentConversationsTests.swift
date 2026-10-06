import XCTest
@testable import FeatherCore

final class RecentConversationsTests: XCTestCase {
    private func conversation(_ result: String) -> SavedConversation {
        SavedConversation(history: [], lastInstruction: "Reply", answer: "", result: result)
    }

    func testOnlyConversationsWithAReplyAreSaved() {
        XCTAssertNil(RecentConversations.conversation(history: [], lastInstruction: "Reply", answer: "", result: ""))
        XCTAssertNotNil(RecentConversations.conversation(history: [], lastInstruction: "Why?", answer: "Because.", result: ""))
    }

    func testSavingPutsTheNewestFirstAndKeepsFive() {
        var list: [SavedConversation] = []
        for number in 1...7 { list = RecentConversations.saving(conversation("\(number)"), restoredFrom: nil, in: list) }
        XCTAssertEqual(list.map(\.result), ["7", "6", "5", "4", "3"])
    }

    func testAViewedConversationKeepsItsPlace() {
        let list = [conversation("b"), conversation("a")]
        XCTAssertEqual(RecentConversations.saving(conversation("a"), restoredFrom: conversation("a"), in: list), list)
    }

    func testARefinedConversationReplacesTheOriginal() {
        let list = [conversation("b"), conversation("a")]
        let refined = RecentConversations.saving(conversation("a, shorter"), restoredFrom: conversation("a"), in: list)
        XCTAssertEqual(refined.map(\.result), ["a, shorter", "b"])
    }

    func testBrowsingStopsAtBothEnds() {
        XCTAssertEqual(RecentConversations.browse(from: nil, .older, count: 3), 0)
        XCTAssertEqual(RecentConversations.browse(from: 1, .older, count: 3), 2)
        XCTAssertEqual(RecentConversations.browse(from: 2, .older, count: 3), 2)
        XCTAssertNil(RecentConversations.browse(from: nil, .older, count: 0))
        XCTAssertEqual(RecentConversations.browse(from: 2, .newer, count: 3), 1)
        XCTAssertNil(RecentConversations.browse(from: 0, .newer, count: 3))
        XCTAssertNil(RecentConversations.browse(from: nil, .newer, count: 3))
    }

    func testDecodingSurvivesBadDataAndRoundTrips() {
        XCTAssertEqual(RecentConversations.decode(nil), [])
        XCTAssertEqual(RecentConversations.decode(Data("nope".utf8)), [])
        let list = [SavedConversation(history: [Exchange(instruction: "Reply", result: "Hi")], lastInstruction: "Shorter", answer: "", result: "Hey")]
        XCTAssertEqual(RecentConversations.decode(RecentConversations.encode(list)), list)
    }

    func testArrowKeysBrowseWithoutModifiers() {
        XCTAssertEqual(PromptTurn.command(for: PromptKeyInput(keyCode: 126, command: false)), .older)
        XCTAssertEqual(PromptTurn.command(for: PromptKeyInput(keyCode: 125, command: false)), .newer)
        XCTAssertNil(PromptTurn.command(for: PromptKeyInput(keyCode: 126, command: false, shift: true)))
    }
}
