import Foundation

/// Credential persistence seam shared by settings, model loading, and sign-in.
public protocol CredentialStore: Sendable {
    func apiKey() -> String?
    func setAPIKey(_ key: String) -> Bool
    func deleteAPIKey()
    func openAIAPIKey() -> String?
    func setOpenAIAPIKey(_ key: String) -> Bool
    func deleteOpenAIAPIKey()
    func plusToken() -> String?
    func setPlusToken(_ token: String) -> Bool
    func deletePlusToken()
    func claudeAPIKey() -> String?
    func setClaudeAPIKey(_ key: String) -> Bool
    func deleteClaudeAPIKey()
}

/// In-memory adapter for tests and previews.
public final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAPIKey: String?
    private var storedOpenAIAPIKey: String?
    private var storedPlusToken: String?
    private var storedClaudeAPIKey: String?

    public init(apiKey: String? = nil, openAIAPIKey: String? = nil, plusToken: String? = nil, claudeAPIKey: String? = nil) {
        storedAPIKey = apiKey
        storedOpenAIAPIKey = openAIAPIKey
        storedPlusToken = plusToken
        storedClaudeAPIKey = claudeAPIKey
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

    public func openAIAPIKey() -> String? {
        lock.withLock { storedOpenAIAPIKey }
    }

    public func setOpenAIAPIKey(_ key: String) -> Bool {
        lock.withLock {
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            storedOpenAIAPIKey = value.isEmpty ? nil : value
        }
        return true
    }

    public func deleteOpenAIAPIKey() {
        lock.withLock { storedOpenAIAPIKey = nil }
    }

    public func plusToken() -> String? {
        lock.withLock { storedPlusToken }
    }

    public func setPlusToken(_ token: String) -> Bool {
        lock.withLock { storedPlusToken = token }
        return true
    }

    public func deletePlusToken() {
        lock.withLock { storedPlusToken = nil }
    }

    public func claudeAPIKey() -> String? {
        lock.withLock { storedClaudeAPIKey }
    }

    public func setClaudeAPIKey(_ key: String) -> Bool {
        lock.withLock {
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            storedClaudeAPIKey = value.isEmpty ? nil : value
        }
        return true
    }

    public func deleteClaudeAPIKey() {
        lock.withLock { storedClaudeAPIKey = nil }
    }
}
