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
    /// Models exposed by OpenCode's ChatGPT/Codex OAuth integration.
    public static let models: [ChatGPTModel] = [
        ChatGPTModel(id: "gpt-6-luna", name: "GPT-6 Luna"),
        ChatGPTModel(id: "gpt-6-sol", name: "GPT-6 Sol"),
        ChatGPTModel(id: "gpt-5.5", name: "GPT-5.5"),
        ChatGPTModel(id: "gpt-5.4", name: "GPT-5.4"),
        ChatGPTModel(id: "gpt-5.4-mini", name: "GPT-5.4 Mini · Fast"),
        ChatGPTModel(id: "gpt-5.3-codex-spark", name: "GPT-5.3 Codex Spark"),
    ]

    public static let defaultModel = models.first(where: { $0.name.localizedCaseInsensitiveContains("fast") })?.id ?? models[0].id
}
