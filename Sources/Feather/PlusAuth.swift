import AppKit
import FeatherCore
import Foundation
import Network

enum PlusAuthError: LocalizedError {
    case timedOut
    case unauthorized
    case server(Int)
    case keychain

    var errorDescription: String? {
        switch self {
        case .timedOut: String(localized: "Sign-in timed out. Try again.", bundle: .app)
        case .unauthorized: String(localized: "Your session expired. Sign in again.", bundle: .app)
        case .server(let status): String(localized: "Feather Plus returned an error (\(status)).", bundle: .app)
        case .keychain: String(localized: "Couldn't save your session in the Keychain.", bundle: .app)
        }
    }

    /// A readable message for any error raised while talking to Feather Plus.
    static func message(for error: Error) -> String {
        if error is URLError {
            return String(localized: "Couldn't reach Feather Plus. Check your connection.", bundle: .app)
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

enum PlusAuth {
    private static let signInTimeout: TimeInterval = 300

    /// Runs the browser sign-in and stores the resulting account token. Cancel the calling task
    /// to abandon it; the loopback port is released either way.
    static func signIn(store: any CredentialStore = KeychainCredentialStore.shared, base: String = FeatherPlus.baseURL()) async throws -> String {
        let verifier = ChatGPTToken.randomString(length: 64)
        let state = ChatGPTToken.randomString(length: 32)
        let redirect = try LoopbackRedirect(expectedState: state)
        let redirectURI = LockedValue<String?>(nil)

        let callback = try await redirect.receive(timeout: signInTimeout) { port in
            let uri = FeatherPlus.redirectURI(port: port)
            redirectURI.value = uri
            guard let url = try? FeatherPlus.authorizeURL(
                base: base,
                redirectURI: uri,
                state: state,
                codeChallenge: ChatGPTToken.codeChallenge(for: verifier)
            ) else { return false }
            DispatchQueue.main.async { _ = NSWorkspace.shared.open(url) }
            return true
        }

        do {
            guard let uri = redirectURI.value else { throw LLMError.invalidBaseURL }
            let token = try await exchange(base: base, code: callback.code, verifier: verifier, redirectURI: uri)
            guard store.setPlusToken(token) else { throw PlusAuthError.keychain }
            callback.respond(html: page(
                title: String(localized: "Signed in to Feather Plus", bundle: .app),
                message: String(localized: "You can close this window and return to Feather.", bundle: .app),
                succeeded: true
            ))
            return token
        } catch {
            callback.respond(html: page(
                title: String(localized: "Sign-in failed", bundle: .app),
                message: PlusAuthError.message(for: error),
                succeeded: false
            ))
            throw error
        }
    }

    static func account(token: String, base: String = FeatherPlus.baseURL()) async throws -> PlusAccount {
        let (data, response) = try await URLSession.shared.data(for: FeatherPlus.accountRequest(base: base, token: token))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw PlusAuthError.unauthorized }
        guard (200..<300).contains(status) else { throw PlusAuthError.server(status) }
        return try FeatherPlus.decodeAccount(data)
    }

    /// Opens `path` on the website, signed in to the app's account when there is one. Without a
    /// token, or when the code can't be had, it still opens the page, just signed out.
    static func openWebsite(path: String, store: any CredentialStore = KeychainCredentialStore.shared, base: String = FeatherPlus.baseURL()) async {
        var code: String?
        if let token = store.plusToken(), var request = try? FeatherPlus.webCodeRequest(base: base, token: token) {
            request.timeoutInterval = 10
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
                code = try? FeatherPlus.decodeWebCode(data)
            }
        }
        guard let url = try? FeatherPlus.websiteURL(base: base, path: path, code: code) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Forgets the token locally right away, then asks the server to revoke it. Revocation is
    /// best effort: a token that is no longer stored anywhere is useless even if it survives.
    static func signOut(store: any CredentialStore = KeychainCredentialStore.shared, base: String = FeatherPlus.baseURL()) {
        guard let token = store.plusToken() else { return }
        store.deletePlusToken()
        guard var request = try? FeatherPlus.revokeRequest(base: base, token: token) else { return }
        request.timeoutInterval = 10
        Task.detached { [request] in _ = try? await URLSession.shared.data(for: request) }
    }

    private static func exchange(base: String, code: String, verifier: String, redirectURI: String) async throws -> String {
        let request = try FeatherPlus.tokenRequest(base: base, code: code, verifier: verifier, redirectURI: redirectURI)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PlusAuthError.server(status) }
        return try FeatherPlus.decodeToken(data)
    }

    private static func page(title: String, message: String, succeeded: Bool) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let (mark, markColor, markBackground) = succeeded ? ("✓", "#62e6a0", "#173d2b") : ("!", "#ff7d8a", "#431f24")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
        :root{color-scheme:dark}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#050505;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
        .card{width:min(420px,calc(100% - 40px));box-sizing:border-box;padding:42px 36px;border:1px solid #2a2a2a;border-radius:22px;background:#101010;text-align:center;box-shadow:0 24px 70px #000}
        .mark{width:54px;height:54px;margin:0 auto 22px;border-radius:50%;display:grid;place-items:center;background:\(markBackground);color:\(markColor);font-size:28px}
        h1{margin:0 0 12px;font:32px Georgia,serif;letter-spacing:-.03em}p{margin:0;color:#a7a7a7;line-height:1.55;font-size:15px}
        </style></head><body><main class="card"><div class="mark">\(mark)</div><h1>\(escape(title))</h1><p>\(escape(message))</p></main></body></html>
        """
    }
}

/// Receives one OAuth redirect on an ephemeral port bound to 127.0.0.1 (RFC 8252), so the
/// listener is never reachable from the network.
private final class LoopbackRedirect: @unchecked Sendable {
    struct Callback {
        let code: String
        let connection: NWConnection

        func respond(html: String) {
            LoopbackRedirect.send(status: "200 OK", html: html, on: connection)
        }
    }

    // All mutable state is confined to `queue`.
    private let queue = DispatchQueue(label: "com.feather.plus-redirect")
    private let listener: NWListener
    private let expectedState: String
    private var continuation: CheckedContinuation<Callback, Error>?
    private var finished = false

    init(expectedState: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        self.expectedState = expectedState
    }

    /// Starts listening and calls `onReady` with the bound port; `onReady` returns false to abort.
    /// Returns the first request that carries a code for the expected state.
    func receive(timeout: TimeInterval, onReady: @escaping @Sendable (UInt16) -> Bool) async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !finished else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.continuation = continuation
                    listener.stateUpdateHandler = { [self] state in
                        switch state {
                        case .ready:
                            guard let port = listener.port?.rawValue, onReady(port) else {
                                finish(.failure(LLMError.invalidBaseURL))
                                return
                            }
                        case .failed(let error):
                            finish(.failure(error))
                        default:
                            break
                        }
                    }
                    listener.newConnectionHandler = { [self] connection in handle(connection) }
                    listener.start(queue: queue)
                    queue.asyncAfter(deadline: .now() + timeout) { [self] in
                        finish(.failure(PlusAuthError.timedOut))
                    }
                }
            }
        } onCancel: {
            queue.async { [self] in finish(.failure(CancellationError())) }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, _, _ in
            guard !finished,
                  let data, let request = String(data: data, encoding: .utf8),
                  let requestLine = request.components(separatedBy: "\r\n").first,
                  let target = requestLine.split(separator: " ").dropFirst().first,
                  let code = FeatherPlus.authorizationCode(fromRequestTarget: String(target), expectedState: expectedState)
            else {
                // Favicon requests and stray connections must not end the sign-in.
                Self.send(status: "404 Not Found", html: "", on: connection)
                return
            }
            finish(.success(Callback(code: code, connection: connection)))
        }
    }

    private func finish(_ result: Result<Callback, Error>) {
        guard !finished else { return }
        finished = true
        listener.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }

    fileprivate static func send(status: String, html: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// A value shared between the listener callback and the sign-in task.
private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
