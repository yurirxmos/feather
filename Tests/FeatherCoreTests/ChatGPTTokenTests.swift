import XCTest
@testable import FeatherCore

final class ChatGPTTokenTests: XCTestCase {
    func testAccountIDReadsSupportedClaims() throws {
        let payload: [String: Any] = ["https://api.openai.com/auth": ["chatgpt_account_id": "acct-123"]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let token = "header.\(ChatGPTToken.base64URL(data)).signature"
        XCTAssertEqual(ChatGPTToken.accountID(from: token), "acct-123")

        let orgPayload: [String: Any] = ["organizations": [["id": "org-123"]]]
        let orgData = try JSONSerialization.data(withJSONObject: orgPayload)
        XCTAssertEqual(ChatGPTToken.accountID(from: "h.\(ChatGPTToken.base64URL(orgData)).s"), "org-123")
        XCTAssertNil(ChatGPTToken.accountID(from: "not-a-token"))
    }

    func testFormDataEscapesValuesDeterministically() {
        let encoded = String(decoding: ChatGPTToken.formData(["z": "last", "a": "space & plus+"]), as: UTF8.self)
        XCTAssertEqual(encoded, "a=space+%26+plus%2B&z=last")
    }

    func testCodeChallengeIsURLSafeAndDeterministic() {
        let challenge = ChatGPTToken.codeChallenge(for: "test-verifier")
        XCTAssertEqual(challenge, ChatGPTToken.codeChallenge(for: "test-verifier"))
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }
}
