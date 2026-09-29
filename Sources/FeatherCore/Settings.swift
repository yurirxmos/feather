import Foundation

public enum SettingsKey {
    public static let connection = "connection"
    public static let model = "model"
    public static let hotkey = "hotkey"
    public static let includeScreenshot = "includeScreenshot"
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

    public init(connection: ConnectionKind, model: String, hotkey: HotkeyPreset, includeScreenshot: Bool) {
        self.connection = connection
        self.model = model
        self.hotkey = hotkey
        self.includeScreenshot = includeScreenshot
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
            includeScreenshot: defaults.object(forKey: SettingsKey.includeScreenshot) as? Bool ?? true
        )
    }

    public func hasCredentials(using store: any CredentialStore) -> Bool {
        switch connection {
        case .openCodeGo: !(store.apiKey() ?? "").isEmpty
        case .chatGPT: store.chatGPTCredentials() != nil
        }
    }

    public func makeProvider(
        apiKey: String = "",
        accessToken: String? = nil,
        accountID: String? = nil
    ) -> any LLMProvider {
        switch connection {
        case .openCodeGo: OpenCodeGoProvider(apiKey: apiKey)
        case .chatGPT: ChatGPTProvider(accessToken: accessToken ?? "", accountID: accountID)
        }
    }

    public static func model(afterChangingTo connection: ConnectionKind, preserving model: String) -> String {
        if model == ConnectionKind.openCodeGo.defaultModel || model == ConnectionKind.chatGPT.defaultModel {
            return connection.defaultModel
        }
        return model
    }
}
