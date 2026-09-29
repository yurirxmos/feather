import AppKit
import FeatherCore
import Foundation
import Network

enum ChatGPTAuthError: LocalizedError {
    case callbackTimeout
    case invalidCallback
    case tokenExchangeFailed(Int)
    case refreshFailed(Int)

    var errorDescription: String? {
        switch self {
        case .callbackTimeout: String(localized: "ChatGPT login timed out.", bundle: .app)
        case .invalidCallback: String(localized: "ChatGPT returned an invalid login callback.", bundle: .app)
        case .tokenExchangeFailed(let status): String(localized: "ChatGPT token exchange failed (%lld).", bundle: .app).replacingOccurrences(of: "%lld", with: "\(status)")
        case .refreshFailed(let status): String(localized: "ChatGPT session refresh failed (%lld).", bundle: .app).replacingOccurrences(of: "%lld", with: "\(status)")
        }
    }
}

enum ChatGPTAuth {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let issuer = "https://auth.openai.com"
    private static let callbackPort: UInt16 = 1455

    private struct Callback {
        let code: String
        let connection: NWConnection
    }

    static func login(store: any CredentialStore = KeychainCredentialStore.shared) async throws -> ChatGPTCredentials {
        let verifier = ChatGPTToken.randomString(length: 64)
        let challenge = ChatGPTToken.codeChallenge(for: verifier)
        let state = ChatGPTToken.randomString(length: 32)
        let redirectURI = "http://localhost:\(callbackPort)/auth/callback"
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: callbackPort)!)
        let callbackTask = Task { try await receiveCode(listener: listener, state: state) }

        var components = URLComponents(string: "\(issuer)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "opencode"),
        ]
        guard let authorizationURL = components.url else { throw ChatGPTAuthError.invalidCallback }
        await MainActor.run { _ = NSWorkspace.shared.open(authorizationURL) }

        let callback = try await callbackTask.value
        listener.cancel()
        let tokens: TokenResponse
        do {
            tokens = try await exchange(code: callback.code, verifier: verifier, redirectURI: redirectURI)
        } catch {
            sendPage(on: callback.connection, html: errorPage(error.localizedDescription))
            throw error
        }
        let resolvedAccountID = tokens.idToken.flatMap { ChatGPTToken.accountID(from: $0) }
            ?? ChatGPTToken.accountID(from: tokens.accessToken)
        let credentials = ChatGPTCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)),
            accountID: resolvedAccountID
        )
        _ = store.setChatGPTCredentials(credentials)
        sendPage(on: callback.connection, html: successPage())
        return credentials
    }

    static func validCredentials(store: any CredentialStore = KeychainCredentialStore.shared) async throws -> ChatGPTCredentials {
        guard let credentials = store.chatGPTCredentials() else { throw ChatGPTAuthError.invalidCallback }
        guard credentials.expiresAt <= Date().addingTimeInterval(60) else { return credentials }
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ChatGPTToken.formData([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": clientID,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw ChatGPTAuthError.refreshFailed(status)
        }
        let refreshed = ChatGPTCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)),
            accountID: tokens.idToken.flatMap(ChatGPTToken.accountID(from:)) ?? credentials.accountID
        )
        _ = store.setChatGPTCredentials(refreshed)
        return refreshed
    }

    private static func receiveCode(listener: NWListener, state: String) async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { connection in
                connection.stateUpdateHandler = { stateUpdate in
                    guard case .ready = stateUpdate else { return }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                        guard let data, let request = String(data: data, encoding: .utf8),
                              let firstLine = request.components(separatedBy: "\r\n").first,
                              let path = firstLine.split(separator: " ").dropFirst().first,
                              let components = URLComponents(string: "http://localhost\(path)"),
                              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                              components.queryItems?.first(where: { $0.name == "state" })?.value == state
                        else {
                            continuation.resume(throwing: ChatGPTAuthError.invalidCallback)
                            return
                        }
                        continuation.resume(returning: Callback(code: code, connection: connection))
                    }
                }
                connection.start(queue: .main)
            }
            listener.start(queue: .main)
        }
    }

    private static func exchange(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ChatGPTToken.formData([
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI,
            "client_id": clientID, "code_verifier": verifier,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ChatGPTAuthError.tokenExchangeFailed(status) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func sendPage(on connection: NWConnection, html: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func successPage() -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
        :root{color-scheme:dark}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#050505;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
        .card{width:min(420px,calc(100% - 40px));box-sizing:border-box;padding:42px 36px;border:1px solid #2a2a2a;border-radius:22px;background:#101010;text-align:center;box-shadow:0 24px 70px #000}
        .mark{width:54px;height:54px;margin:0 auto 22px;border-radius:50%;display:grid;place-items:center;background:#173d2b;color:#62e6a0;font-size:28px}
        h1{margin:0 0 12px;font:32px Georgia,serif;letter-spacing:-.03em}p{margin:0;color:#a7a7a7;line-height:1.55;font-size:15px}
        </style></head><body><main class="card"><div class="mark">✓</div><h1>Connected to ChatGPT</h1><p>You can close this window and return to Feather.</p></main></body></html>
        """
    }

    private static func errorPage(_ message: String) -> String {
        let safeMessage = message.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
        :root{color-scheme:dark}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#050505;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}.card{width:min(420px,calc(100% - 40px));box-sizing:border-box;padding:42px 36px;border:1px solid #402323;border-radius:22px;background:#101010;text-align:center;box-shadow:0 24px 70px #000}.mark{width:54px;height:54px;margin:0 auto 22px;border-radius:50%;display:grid;place-items:center;background:#431f24;color:#ff7d8a;font-size:28px}h1{margin:0 0 12px;font:32px Georgia,serif;letter-spacing:-.03em}p{margin:0;color:#b9a7a7;line-height:1.55;font-size:15px}
        </style></head><body><main class="card"><div class="mark">!</div><h1>ChatGPT connection failed</h1><p>\(safeMessage)</p></main></body></html>
        """
    }

    private struct TokenResponse: Codable {
        var accessToken: String
        var refreshToken: String
        var idToken: String?
        var expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token", expiresIn = "expires_in"
        }
    }

}
