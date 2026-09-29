import Foundation

public struct ChatGPTCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var accountID: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, accountID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }
}

/// Credential persistence seam shared by settings, model loading, and OAuth.
public protocol CredentialStore: Sendable {
    func apiKey() -> String?
    func setAPIKey(_ key: String) -> Bool
    func deleteAPIKey()
    func chatGPTCredentials() -> ChatGPTCredentials?
    func setChatGPTCredentials(_ credentials: ChatGPTCredentials) -> Bool
    func deleteChatGPTCredentials()
}

/// In-memory adapter for tests and previews.
public final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAPIKey: String?
    private var storedChatGPTCredentials: ChatGPTCredentials?

    public init(apiKey: String? = nil, chatGPTCredentials: ChatGPTCredentials? = nil) {
        storedAPIKey = apiKey
        storedChatGPTCredentials = chatGPTCredentials
    }

    public func apiKey() -> String? {
        lock.withLock { storedAPIKey }
    }

    public func setAPIKey(_ key: String) -> Bool {
        lock.withLock {
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            storedAPIKey = value.isEmpty ? nil : value
        }
        return true
    }

    public func deleteAPIKey() {
        lock.withLock { storedAPIKey = nil }
    }

    public func chatGPTCredentials() -> ChatGPTCredentials? {
        lock.withLock { storedChatGPTCredentials }
    }

    public func setChatGPTCredentials(_ credentials: ChatGPTCredentials) -> Bool {
        lock.withLock { storedChatGPTCredentials = credentials }
        return true
    }

    public func deleteChatGPTCredentials() {
        lock.withLock { storedChatGPTCredentials = nil }
    }
}
