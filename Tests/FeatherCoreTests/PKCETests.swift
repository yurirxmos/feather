import XCTest
@testable import FeatherCore

final class PKCETests: XCTestCase {
    func testCodeChallengeIsURLSafeAndDeterministic() {
        let challenge = PKCE.codeChallenge(for: "test-verifier")
        XCTAssertEqual(challenge, PKCE.codeChallenge(for: "test-verifier"))
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }
}
