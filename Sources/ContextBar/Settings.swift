import ContextBarCore
import Foundation

/// `UserDefaults` keys. Preserve these when changing settings behavior.
enum SettingsKey {
    static let provider = "provider"
    static let anthropicModel = "anthropicModel"
    static let anthropicBaseURL = "anthropicBaseURL"
    static let openAIModel = "openAIModel"
    static let openAIBaseURL = "openAIBaseURL"
    static let hotkey = "hotkey"
    static let includeScreenshot = "includeScreenshot"
}

/// A read of the persisted settings, taken when needed rather than observed.
struct Settings {
    var provider: ProviderKind
    var model: String
    var baseURL: String
    var hotkey: HotkeyPreset
    var includeScreenshot: Bool

    static func current(_ defaults: UserDefaults = .standard) -> Settings {
        let provider = defaults.string(forKey: SettingsKey.provider).flatMap(ProviderKind.init(rawValue:)) ?? .anthropic
        let modelKey = provider == .anthropic ? SettingsKey.anthropicModel : SettingsKey.openAIModel
        let baseURLKey = provider == .anthropic ? SettingsKey.anthropicBaseURL : SettingsKey.openAIBaseURL
        return Settings(
            provider: provider,
            model: nonEmpty(defaults.string(forKey: modelKey)) ?? provider.defaultModel,
            baseURL: nonEmpty(defaults.string(forKey: baseURLKey)) ?? provider.defaultBaseURL,
            hotkey: defaults.string(forKey: SettingsKey.hotkey).flatMap(HotkeyPreset.init(rawValue:)) ?? .optionSpace,
            includeScreenshot: defaults.object(forKey: SettingsKey.includeScreenshot) as? Bool ?? true
        )
    }

    var hasCredentials: Bool {
        !provider.requiresAPIKey || !(Keychain.apiKey(for: provider) ?? "").isEmpty
    }

    func makeProvider() -> LLMProvider {
        let key = Keychain.apiKey(for: provider) ?? ""
        switch provider {
        case .anthropic: return AnthropicProvider(apiKey: key, baseURL: baseURL)
        case .openAICompatible: return OpenAICompatibleProvider(apiKey: key, baseURL: baseURL)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension LLMError {
    var localizedMessage: String {
        switch self {
        case .missingAPIKey:
            String(localized: "Add an API key in Settings.", bundle: .app)
        case .missingModel:
            String(localized: "Set a model in Settings.", bundle: .app)
        case .invalidBaseURL:
            String(localized: "The base URL in Settings is not valid.", bundle: .app)
        case .http(let status, let message):
            message.map { "\(status): \($0)" } ?? String(localized: "Request failed with status \(status).", bundle: .app)
        case .api(let message):
            message
        case .refused:
            String(localized: "The model declined this request.", bundle: .app)
        }
    }
}
