import XCTest
@testable import FeatherCore

final class FeedbackTests: XCTestCase {
    func testRequestPostsTrimmedMessageAndVersions() throws {
        let request = try Feedback.request(
            base: "http://127.0.0.1:8787/",
            message: "  The panel hides behind Slack.\n",
            email: " user@example.com ",
            appVersion: "0.4.1",
            platform: "macOS 15.6"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8787/v1/feedback")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body, [
            "message": "The panel hides behind Slack.",
            "email": "user@example.com",
            "app_version": "0.4.1",
            "platform": "macOS 15.6",
        ])
    }

    func testRequestLeavesOutABlankEmail() throws {
        let request = try Feedback.request(base: "https://api.example.com", message: "Hi", email: "  ", appVersion: "1", platform: "p")
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertNil(body["email"])
    }

    func testOutcomeFollowsStatus() {
        XCTAssertEqual(Feedback.outcome(status: 204), .sent)
        XCTAssertEqual(Feedback.outcome(status: 400), .invalid)
        XCTAssertEqual(Feedback.outcome(status: 429), .rateLimited)
        XCTAssertEqual(Feedback.outcome(status: 502), .failed)
        XCTAssertEqual(Feedback.outcome(status: 0), .failed)
    }

    func testCanSendNeedsTextWithinTheLimit() {
        XCTAssertFalse(Feedback.canSend(" \n "))
        XCTAssertTrue(Feedback.canSend("Hi"))
        XCTAssertTrue(Feedback.canSend(String(repeating: "x", count: Feedback.maxMessageLength)))
        XCTAssertFalse(Feedback.canSend(String(repeating: "x", count: Feedback.maxMessageLength + 1)))
    }
}
