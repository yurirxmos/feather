import XCTest
@testable import FeatherCore

final class FeatherPlusTests: XCTestCase {
    func testAuthorizeURLCarriesPKCEAndRedirect() throws {
        let url = try FeatherPlus.authorizeURL(
            base: "https://plus.example.com/",
            redirectURI: FeatherPlus.redirectURI(port: 51234),
            state: "state-1",
            codeChallenge: "challenge-1"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "plus.example.com")
        XCTAssertEqual(components.path, "/auth/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:51234/callback")
        XCTAssertEqual(items["state"], "state-1")
        XCTAssertEqual(items["code_challenge"], "challenge-1")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["response_type"], "code")
    }

    func testAuthorizeURLRejectsInvalidBase() {
        XCTAssertThrowsError(try FeatherPlus.authorizeURL(base: "not a url", redirectURI: "x", state: "s", codeChallenge: "c"))
    }

    func testAuthorizationCodeRequiresCallbackPathAndMatchingState() {
        XCTAssertEqual(FeatherPlus.authorizationCode(fromRequestTarget: "/callback?code=abc&state=s1", expectedState: "s1"), "abc")
        XCTAssertNil(FeatherPlus.authorizationCode(fromRequestTarget: "/callback?code=abc&state=other", expectedState: "s1"))
        XCTAssertNil(FeatherPlus.authorizationCode(fromRequestTarget: "/callback?state=s1", expectedState: "s1"))
        XCTAssertNil(FeatherPlus.authorizationCode(fromRequestTarget: "/callback?code=&state=s1", expectedState: "s1"))
        XCTAssertNil(FeatherPlus.authorizationCode(fromRequestTarget: "/favicon.ico", expectedState: "s1"))
    }

    func testTokenRequestPostsJSON() throws {
        let request = try FeatherPlus.tokenRequest(base: "http://127.0.0.1:8787", code: "c", verifier: "v", redirectURI: "r")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8787/v1/auth/token")
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body, ["code": "c", "code_verifier": "v", "redirect_uri": "r"])
    }

    func testAccountAndRevokeRequestsUseBearerToken() throws {
        let account = try FeatherPlus.accountRequest(base: "http://127.0.0.1:8787", token: "fth_x")
        XCTAssertEqual(account.url?.path, "/v1/account")
        XCTAssertEqual(account.value(forHTTPHeaderField: "Authorization"), "Bearer fth_x")

        let revoke = try FeatherPlus.revokeRequest(base: "http://127.0.0.1:8787", token: "fth_x")
        XCTAssertEqual(revoke.httpMethod, "POST")
        XCTAssertEqual(revoke.url?.path, "/v1/auth/revoke")
        XCTAssertEqual(revoke.value(forHTTPHeaderField: "Authorization"), "Bearer fth_x")
    }

    func testDecodeTokenRejectsEmptyToken() throws {
        XCTAssertEqual(try FeatherPlus.decodeToken(Data(#"{"token":"fth_abc"}"#.utf8)), "fth_abc")
        XCTAssertThrowsError(try FeatherPlus.decodeToken(Data(#"{"token":""}"#.utf8)))
        XCTAssertThrowsError(try FeatherPlus.decodeToken(Data("{}".utf8)))
    }

    func testDecodeAccountReadsPlanUsageAndJavaScriptDates() throws {
        let json = """
        {"email":"a@example.com","plan":"max","period_end":"2026-11-01T00:00:00.000Z",
         "usage":[{"tier":"fast","used":12,"limit":4000},{"tier":"premium","used":3,"limit":150}]}
        """
        let account = try FeatherPlus.decodeAccount(Data(json.utf8))
        XCTAssertEqual(account.email, "a@example.com")
        XCTAssertEqual(account.plan, .max)
        XCTAssertEqual(account.usage.map(\.tier), [.fast, .premium])
        XCTAssertEqual(account.usage.first?.used, 12)
        XCTAssertEqual(account.periodEnd, ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
    }

    func testDecodeAccountToleratesMissingAndUnknownValues() throws {
        let json = """
        {"email":"a@example.com","plan":"enterprise","period_end":"2026-11-01T00:00:00Z",
         "usage":[{"tier":"ultra","used":1,"limit":2},{"tier":"fast","used":0,"limit":500}]}
        """
        let account = try FeatherPlus.decodeAccount(Data(json.utf8))
        XCTAssertNil(account.plan)
        XCTAssertEqual(account.usage.map(\.tier), [.fast])
        XCTAssertNotNil(account.periodEnd)

        let minimal = try FeatherPlus.decodeAccount(Data(#"{"email":"b@example.com","plan":null}"#.utf8))
        XCTAssertNil(minimal.plan)
        XCTAssertEqual(minimal.usage, [])
        XCTAssertNil(minimal.periodEnd)
    }

    func testBaseURLUsesOverrideWhenSet() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatherPlusTests"))
        defaults.removePersistentDomain(forName: "FeatherPlusTests")
        XCTAssertEqual(FeatherPlus.baseURL(defaults), FeatherPlus.defaultBaseURL)
        defaults.set("  ", forKey: SettingsKey.plusBaseURL)
        XCTAssertEqual(FeatherPlus.baseURL(defaults), FeatherPlus.defaultBaseURL)
        defaults.set("https://plus.example.com", forKey: SettingsKey.plusBaseURL)
        XCTAssertEqual(FeatherPlus.baseURL(defaults), "https://plus.example.com")
        defaults.removePersistentDomain(forName: "FeatherPlusTests")
    }

    func testMemoryStoreKeepsPlusTokenSeparately() {
        let store = MemoryCredentialStore(apiKey: "go-key")
        XCTAssertNil(store.plusToken())
        XCTAssertTrue(store.setPlusToken("fth_x"))
        XCTAssertEqual(store.plusToken(), "fth_x")
        store.deletePlusToken()
        XCTAssertNil(store.plusToken())
        XCTAssertEqual(store.apiKey(), "go-key")
    }
}
