import Foundation

/// Client side of Feather Plus, the hosted plans served by `feather-api`.
///
/// Sign-in is an OAuth-style authorization code flow with PKCE over a loopback redirect:
/// the browser returns a short-lived code to `http://127.0.0.1:<port>/callback`, and the app
/// exchanges it for a long-lived account token stored in the Keychain.
public enum FeatherPlus {
    /// Every build talks to production; set the `plusBaseURL` default to use `wrangler dev`
    /// (`http://127.0.0.1:8787`) in `feather-api` instead.
    public static let defaultBaseURL = "https://feather-api.rxmos.dev"
    public static let callbackPath = "/callback"

    // Feather Plus rolled out in two stages: accounts (sign-in, plan, usage), then generating
    // through it. Both are launched. Setting either back to false hides that stage again in
    // release builds, except for testers with the `plusEnabled` or `plusProviderEnabled` default.
    public static let accountsLaunched = true
    public static let providerLaunched = true

    /// Whether Settings shows the Feather Plus pane. Debug builds always do.
    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        return true
        #else
        return accountsLaunched || defaults.bool(forKey: SettingsKey.plusEnabled)
        #endif
    }

    /// Whether Feather Plus can be chosen as the provider that generates replies.
    public static func isProviderEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        isEnabled(defaults) && (providerLaunched || defaults.bool(forKey: SettingsKey.plusProviderEnabled))
    }

    /// Reads the `plusBaseURL` override, so development builds can point at another server.
    public static func baseURL(_ defaults: UserDefaults = .standard) -> String {
        let override = defaults.string(forKey: SettingsKey.plusBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return override.flatMap { $0.isEmpty ? nil : $0 } ?? defaultBaseURL
    }

    public static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(callbackPath)"
    }

    public static func authorizeURL(base: String, redirectURI: String, state: String, codeChallenge: String) throws -> URL {
        guard var components = URLComponents(url: try .endpoint(base: base, path: "/auth/authorize"), resolvingAgainstBaseURL: false) else {
            throw LLMError.invalidBaseURL
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw LLMError.invalidBaseURL }
        return url
    }

    /// The page where a signed-in user picks, changes, or cancels a plan.
    public static func accountURL(base: String) throws -> URL {
        try .endpoint(base: base, path: "/account")
    }

    /// Extracts the authorization code from a loopback request target such as
    /// `/callback?code=…&state=…`. Returns nil for other paths or a mismatched state.
    public static func authorizationCode(fromRequestTarget target: String, expectedState: String) -> String? {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              components.path == callbackPath,
              let items = components.queryItems,
              items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { return nil }
        return code
    }

    public static func tokenRequest(base: String, code: String, verifier: String, redirectURI: String) throws -> URLRequest {
        var request = URLRequest(url: try .endpoint(base: base, path: "/v1/auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
        ])
        return request
    }

    public static func accountRequest(base: String, token: String) throws -> URLRequest {
        var request = URLRequest(url: try .endpoint(base: base, path: "/v1/account"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public static func revokeRequest(base: String, token: String) throws -> URLRequest {
        var request = URLRequest(url: try .endpoint(base: base, path: "/v1/auth/revoke"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public static func decodeToken(_ data: Data) throws -> String {
        struct Response: Decodable { let token: String }
        let token = try JSONDecoder().decode(Response.self, from: data).token
        guard !token.isEmpty else { throw LLMError.api(message: "The server returned an empty token.") }
        return token
    }

    public static func decodeAccount(_ data: Data) throws -> PlusAccount {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            // JavaScript's `toISOString()` includes milliseconds, which `.iso8601` rejects.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(value)"))
        }
        return try decoder.decode(PlusAccount.self, from: data)
    }
}

/// The signed-in account as reported by `GET /v1/account`.
public struct PlusAccount: Decodable, Equatable, Sendable {
    public enum Plan: String, Decodable, Sendable {
        case starter
        case max
    }

    /// Requests used and allowed this period. The server sends one entry while a plan is active.
    public struct Usage: Decodable, Equatable, Sendable {
        public var used: Int
        public var limit: Int
    }

    public var email: String
    /// Nil when the account has no active subscription.
    public var plan: Plan?
    public var usage: [Usage]
    /// When the current quota period resets.
    public var periodEnd: Date?

    enum CodingKeys: String, CodingKey {
        case email, plan, usage
        case periodEnd = "period_end"
    }

    public init(email: String, plan: Plan?, usage: [Usage], periodEnd: Date?) {
        self.email = email
        self.plan = plan
        self.usage = usage
        self.periodEnd = periodEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        // An unknown plan id from a newer server is shown as no plan instead of failing.
        plan = (try? container.decodeIfPresent(String.self, forKey: .plan)).flatMap { $0.flatMap(Plan.init(rawValue:)) }
        usage = (try container.decodeIfPresent([LossyUsage].self, forKey: .usage) ?? []).compactMap(\.value).prefix(1).map { $0 }
        periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
    }

    /// Skips malformed usage rows instead of failing the whole account.
    private struct LossyUsage: Decodable {
        let value: Usage?

        init(from decoder: Decoder) throws {
            value = try? Usage(from: decoder)
        }
    }
}
