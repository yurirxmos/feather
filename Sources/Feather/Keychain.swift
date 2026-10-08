import Foundation
import Security
import FeatherCore

enum Keychain {
    private static let service = "com.feather.api-keys"
    private static let legacyService = "com.contextbar.api-keys"
    private static let account = "opencode-go"
    private static let chatGPTAccount = "chatgpt-oauth"
    private static let plusAccount = "feather-plus"
    private static let claudeAccount = "claude-api-key"

    static func apiKey() -> String? {
        guard let data = readOrMigrate(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteAPIKey()
            return true
        }
        return write(Data(trimmed.utf8), account: account)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func chatGPTCredentials() -> ChatGPTCredentials? {
        guard let data = readOrMigrate(account: chatGPTAccount) else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredentials.self, from: data)
    }

    @discardableResult
    static func setChatGPTCredentials(_ credentials: ChatGPTCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        return write(data, account: chatGPTAccount)
    }

    static func deleteChatGPTCredentials() {
        delete(account: chatGPTAccount)
    }

    static func plusToken() -> String? {
        read(account: plusAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func setPlusToken(_ token: String) -> Bool {
        write(Data(token.utf8), account: plusAccount)
    }

    static func deletePlusToken() {
        delete(account: plusAccount)
    }

    static func claudeAPIKey() -> String? {
        read(account: claudeAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func setClaudeAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteClaudeAPIKey()
            return true
        }
        return write(Data(trimmed.utf8), account: claudeAccount)
    }

    static func deleteClaudeAPIKey() {
        delete(account: claudeAccount)
    }

    private static func read(account: String) -> Data? {
        read(account: account, service: service)
    }

    private static func readOrMigrate(account: String) -> Data? {
        if let data = read(account: account) { return data }
        guard let data = read(account: account, service: legacyService) else { return nil }

        // Keep the original item so older installations remain usable.
        _ = write(data, account: account)
        return data
    }

    private static func read(account: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Updates an existing item so Keychain keeps its access authorization intact.
    private static func write(_ data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainCredentialStore: CredentialStore {
    static let shared = KeychainCredentialStore()

    func apiKey() -> String? { Keychain.apiKey() }
    func setAPIKey(_ key: String) -> Bool { Keychain.setAPIKey(key) }
    func deleteAPIKey() { Keychain.deleteAPIKey() }
    func chatGPTCredentials() -> ChatGPTCredentials? { Keychain.chatGPTCredentials() }
    func setChatGPTCredentials(_ credentials: ChatGPTCredentials) -> Bool { Keychain.setChatGPTCredentials(credentials) }
    func deleteChatGPTCredentials() { Keychain.deleteChatGPTCredentials() }
    func plusToken() -> String? { Keychain.plusToken() }
    func setPlusToken(_ token: String) -> Bool { Keychain.setPlusToken(token) }
    func deletePlusToken() { Keychain.deletePlusToken() }
    func claudeAPIKey() -> String? { Keychain.claudeAPIKey() }
    func setClaudeAPIKey(_ key: String) -> Bool { Keychain.setClaudeAPIKey(key) }
    func deleteClaudeAPIKey() { Keychain.deleteClaudeAPIKey() }
}
