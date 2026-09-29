import ContextBarCore
import Foundation

/// `UserDefaults` keys. Preserve these when changing settings behavior.
enum SettingsKey {
    static let connection = "connection"
    static let model = "model"
    static let hotkey = "hotkey"
    static let includeScreenshot = "includeScreenshot"
}

/// A read of the persisted settings, taken when needed rather than observed.
struct Settings {
    var connection: ConnectionKind
    var model: String
    var hotkey: HotkeyPreset
    var includeScreenshot: Bool

    static func current(_ defaults: UserDefaults = .standard) -> Settings {
        return Settings(
            connection: defaults.string(forKey: SettingsKey.connection).flatMap(ConnectionKind.init(rawValue:)) ?? .openCodeGo,
            model: nonEmpty(defaults.string(forKey: SettingsKey.model)) ?? OpenCodeGoProvider.defaultModel,
            hotkey: defaults.string(forKey: SettingsKey.hotkey).flatMap(HotkeyPreset.init(rawValue:)) ?? .optionSpace,
            includeScreenshot: defaults.object(forKey: SettingsKey.includeScreenshot) as? Bool ?? true
        )
    }

    var hasCredentials: Bool {
        switch connection {
        case .openCodeGo: return !(Keychain.apiKey() ?? "").isEmpty
        case .chatGPT: return Keychain.chatGPTCredentials() != nil
        }
    }

    func makeProvider(accessToken: String? = nil, accountID: String? = nil) -> LLMProvider {
        switch connection {
        case .openCodeGo: return OpenCodeGoProvider(apiKey: Keychain.apiKey() ?? "")
        case .chatGPT: return ChatGPTProvider(accessToken: accessToken ?? "", accountID: accountID)
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
