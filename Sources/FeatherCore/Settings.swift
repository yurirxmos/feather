import Foundation

public enum SettingsKey {
    public static let connection = "connection"
    public static let model = "model"
    public static let hotkey = "hotkey"
    public static let includeScreenshot = "includeScreenshot"
    public static let customInstructions = "customInstructions"
    /// Development override for the Feather Plus server. Not shown in Settings.
    public static let plusBaseURL = "plusBaseURL"
}

public enum HotkeyPreset: String, CaseIterable, Identifiable, Sendable {
    case optionSpace
    case controlOptionSpace
    case shiftCommandSpace
    case controlOptionReturn

    public var id: String { rawValue }
}

/// A persisted settings snapshot. Defaults and parsing live in the testable core module.
public struct Settings: Equatable, Sendable {
    public var connection: ConnectionKind
    public var model: String
    public var hotkey: HotkeyPreset
    public var includeScreenshot: Bool
    public var customInstructions: String
    public var plusBaseURL: String

    public init(
        connection: ConnectionKind,
        model: String,
        hotkey: HotkeyPreset,
        includeScreenshot: Bool,
        customInstructions: String = "",
        plusBaseURL: String = FeatherPlus.defaultBaseURL
    ) {
        self.connection = connection
        self.model = model
        self.hotkey = hotkey
        self.includeScreenshot = includeScreenshot
        self.customInstructions = customInstructions
        self.plusBaseURL = plusBaseURL
    }

    public static func current(_ defaults: UserDefaults = .standard) -> Settings {
        let connection = defaults.string(forKey: SettingsKey.connection)
            .flatMap(ConnectionKind.init(rawValue:)) ?? .openCodeGo
        let model = defaults.string(forKey: SettingsKey.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Settings(
            connection: connection,
            model: model.flatMap { $0.isEmpty ? nil : $0 } ?? connection.defaultModel,
            hotkey: defaults.string(forKey: SettingsKey.hotkey).flatMap(HotkeyPreset.init(rawValue:)) ?? .optionSpace,
            includeScreenshot: defaults.object(forKey: SettingsKey.includeScreenshot) as? Bool ?? true,
            customInstructions: defaults.string(forKey: SettingsKey.customInstructions)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            plusBaseURL: FeatherPlus.baseURL(defaults)
        )
    }

    public func hasCredentials(using store: any CredentialStore) -> Bool {
        switch connection {
        case .openCodeGo: !(store.apiKey() ?? "").isEmpty
        case .chatGPT: store.chatGPTCredentials() != nil
        case .featherPlus: !(store.plusToken() ?? "").isEmpty
        }
    }

    public func makeProvider(
        apiKey: String = "",
        accessToken: String? = nil,
        accountID: String? = nil,
        plusToken: String? = nil
    ) -> any LLMProvider {
        switch connection {
        case .openCodeGo: OpenCodeGoProvider(apiKey: apiKey)
        case .chatGPT: ChatGPTProvider(accessToken: accessToken ?? "", accountID: accountID)
        case .featherPlus: FeatherPlusProvider(token: plusToken ?? "", baseURL: plusBaseURL)
        }
    }

    /// Feather Plus only accepts its tier names, and they mean nothing to other providers, so a
    /// tier never survives a switch in either direction. Other custom models are kept.
    public static func model(afterChangingTo connection: ConnectionKind, preserving model: String) -> String {
        if connection == .featherPlus {
            return FeatherPlusProvider.isTier(model) ? model : connection.defaultModel
        }
        if FeatherPlusProvider.isTier(model) || ConnectionKind.allCases.contains(where: { $0.defaultModel == model }) {
            return connection.defaultModel
        }
        return model
    }
}
