import Foundation

public enum SettingsKey {
    public static let connection = "connection"
    public static let model = "model"
    public static let hotkey = "hotkey"
    public static let includeScreenshot = "includeScreenshot"
    public static let customInstructions = "customInstructions"
    /// Whether the first-run welcome guide has been finished or dismissed. Absent until the guide has
    /// run once; `Settings.onboardingCompleted(stored:)` treats an absent value as not done.
    public static let onboardingCompleted = "onboardingCompleted"
    /// Development override for the Feather Plus server. Not shown in Settings.
    public static let plusBaseURL = "plusBaseURL"
    /// Shows Feather Plus in release builds before launch. Not shown in Settings.
    public static let plusEnabled = "plusEnabled"
    /// Lets Feather Plus generate replies before that stage launches. Not shown in Settings.
    public static let plusProviderEnabled = "plusProviderEnabled"
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
        var connection = defaults.string(forKey: SettingsKey.connection)
            .flatMap(ConnectionKind.init(rawValue:)) ?? .openCodeGo
        // A stored Feather Plus choice is ignored while that stage is off.
        if connection == .featherPlus, !FeatherPlus.isProviderEnabled(defaults) { connection = .openCodeGo }
        var model = defaults.string(forKey: SettingsKey.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Feather Plus picks its own model, and its placeholder names mean nothing elsewhere.
        if connection == .featherPlus || model.map(FeatherPlusProvider.isPlusModel) == true { model = nil }
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

    /// Whether the welcome guide counts as done. An unset value is not done, so every install sees
    /// the guide once, including ones that already have credentials.
    public static func onboardingCompleted(stored: Bool?) -> Bool {
        stored ?? false
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

    /// Feather Plus always uses its own model, and its placeholder names mean nothing to other
    /// providers, so no model survives a switch to or from it. Other custom models are kept.
    public static func model(afterChangingTo connection: ConnectionKind, preserving model: String) -> String {
        if connection == .featherPlus { return connection.defaultModel }
        if FeatherPlusProvider.isPlusModel(model) || ConnectionKind.allCases.contains(where: { $0.defaultModel == model }) {
            return connection.defaultModel
        }
        return model
    }

    /// The order Settings lists providers in, and the order Feather falls back through.
    public static let providerOrder: [ConnectionKind] = [.featherPlus, .chatGPT, .openCodeGo]

    /// The provider to use after the set of providers that are set up changes. The one in use stays
    /// while it is still set up; otherwise the one just set up (`preferring`), else the first one
    /// set up. With none set up, nothing changes and Settings asks for attention.
    public static func connection(
        current: ConnectionKind,
        setUp: Set<ConnectionKind>,
        preferring preferred: ConnectionKind? = nil
    ) -> ConnectionKind {
        if setUp.contains(current) { return current }
        if let preferred, setUp.contains(preferred) { return preferred }
        return providerOrder.first(where: setUp.contains) ?? current
    }

    /// The providers that have credentials. Feather Plus counts once signed in, plan or not; its
    /// row in Settings asks for a plan when there is none.
    public static func providersSetUp(in store: any CredentialStore, plusAvailable: Bool) -> Set<ConnectionKind> {
        var setUp: Set<ConnectionKind> = []
        if !(store.apiKey() ?? "").isEmpty { setUp.insert(.openCodeGo) }
        if store.chatGPTCredentials() != nil { setUp.insert(.chatGPT) }
        if plusAvailable, store.plusToken() != nil { setUp.insert(.featherPlus) }
        return setUp
    }
}

