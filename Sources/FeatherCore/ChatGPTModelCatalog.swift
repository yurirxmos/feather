import Foundation

public struct ChatGPTModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum ChatGPTModelCatalog {
    /// Models exposed by OpenCode's ChatGPT/Codex OAuth integration. Used until, or unless, the
    /// signed-in account's own list loads.
    public static let models: [ChatGPTModel] = [
        ChatGPTModel(id: "gpt-6-luna", name: "GPT-6 Luna"),
        ChatGPTModel(id: "gpt-6-sol", name: "GPT-6 Sol"),
        ChatGPTModel(id: "gpt-5.5", name: "GPT-5.5"),
        ChatGPTModel(id: "gpt-5.4", name: "GPT-5.4"),
        ChatGPTModel(id: "gpt-5.4-mini", name: "GPT-5.4 Mini · Fast"),
        ChatGPTModel(id: "gpt-5.3-codex-spark", name: "GPT-5.3 Codex Spark"),
    ]

    public static let defaultModel = models.first(where: { $0.name.localizedCaseInsensitiveContains("fast") })?.id ?? models[0].id

    /// The Codex backend lists only the models the signed-in account can use, and hides the ones
    /// newer than the client version it is told about.
    static let modelsURL = "https://chatgpt.com/backend-api/codex/models"
    static let clientVersion = "0.159.0"

    /// Fetches the models the signed-in ChatGPT account can use.
    public static func fetchModels(accessToken: String, accountID: String?) async throws -> [ChatGPTModel] {
        var components = URLComponents(string: modelsURL)!
        components.queryItems = [URLQueryItem(name: "client_version", value: clientVersion)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ChatGPTProvider.userAgent, forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.api(message: "The models request did not return an HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw LLMError.http(status: http.statusCode, message: ProviderTransport.errorMessage(from: data))
        }
        let models = decodeModels(data)
        guard !models.isEmpty else { throw LLMError.api(message: "ChatGPT returned no models for this account.") }
        return models
    }

    /// Reads the model list, keeping the server's order. Accepts `{"models": [...]}` or a bare array,
    /// with each entry naming itself by `slug`, `id`, or `model`, and skips hidden ones.
    static func decodeModels(_ data: Data) -> [ChatGPTModel] {
        let json = try? JSONSerialization.jsonObject(with: data)
        let entries = (json as? [String: Any])?["models"] as? [[String: Any]] ?? json as? [[String: Any]] ?? []
        var models: [ChatGPTModel] = []
        for entry in entries {
            func text(_ key: String) -> String? { (entry[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            guard let id = text("slug") ?? text("id") ?? text("model") else { continue }
            if ["hide", "hidden", "none"].contains(text("visibility") ?? "") || models.contains(where: { $0.id == id }) { continue }
            models.append(ChatGPTModel(id: id, name: text("display_name") ?? text("name") ?? id))
        }
        return models
    }

    /// Keeps `current` when the account can use it; otherwise the fast default, else the first model.
    public static func model(for accountModels: [ChatGPTModel], current: String) -> String? {
        if accountModels.contains(where: { $0.id == current }) { return current }
        return (accountModels.first(where: { $0.id == defaultModel }) ?? accountModels.first)?.id
    }
}
