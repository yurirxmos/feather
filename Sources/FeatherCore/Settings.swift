import Foundation

public enum SettingsKey {
    public static let connection = "connection"
    public static let model = "model"
    public static let hotkey = "hotkey"
    public static let includeScreenshot = "includeScreenshot"
    public static let customInstructions = "customInstructions"
    /// The Style choices in Settings > Replies; see `ReplyStyle`.
    public static let replyTone = "replyTone"
    public static let replyLength = "replyLength"
    public static let replyLanguage = "replyLanguage"
    /// Whether the first-run welcome guide has been finished or dismissed. Absent until the guide has
    /// run once; `Settings.onboardingCompleted(stored:)` treats an absent value as not done.
    public static let onboardingCompleted = "onboardingCompleted"
    /// Whether Feather has turned on opening at login, which it does once per install so that
    /// turning it off later sticks. Not shown in Settings.
    public static let launchAtLoginDefaultApplied = "launchAtLoginDefaultApplied"
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
    public var replyStyle: ReplyStyle
    public var plusBaseURL: String

    public init(
        connection: ConnectionKind,
        model: String,
        hotkey: HotkeyPreset,
        includeScreenshot: Bool,
        customInstructions: String = "",
        replyStyle: ReplyStyle = .standard,
        plusBaseURL: String = FeatherPlus.defaultBaseURL
    ) {
        self.connection = connection
        self.model = model
        self.hotkey = hotkey
        self.includeScreenshot = includeScreenshot
        self.customInstructions = customInstructions
        self.replyStyle = replyStyle
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
            replyStyle: ReplyStyle(
                tone: defaults.string(forKey: SettingsKey.replyTone).flatMap(ReplyTone.init(rawValue:)) ?? .natural,
                length: defaults.string(forKey: SettingsKey.replyLength).flatMap(ReplyLength.init(rawValue:)) ?? .matchRequest,
                language: defaults.string(forKey: SettingsKey.replyLanguage).flatMap(ReplyLanguage.init(rawValue:)) ?? .conversation
            ),
            plusBaseURL: FeatherPlus.baseURL(defaults)
        )
    }

    /// The stored choice "chatGPT" was the ChatGPT account sign-in, which an OpenAI API key replaced;
    /// it now means OpenAI, which asks for a key until one is added. Run once at launch.
    public static func migrateLegacyConnection(_ defaults: UserDefaults = .standard) {
        if defaults.string(forKey: SettingsKey.connection) == "chatGPT" {
            defaults.set(ConnectionKind.openAI.rawValue, forKey: SettingsKey.connection)
        }
    }

    /// Whether the welcome guide counts as done. An unset value is not done, so every install sees
    /// the guide once, including ones that already have credentials.
    public static func onboardingCompleted(stored: Bool?) -> Bool {
        stored ?? false
    }

    public func hasCredentials(using store: any CredentialStore) -> Bool {
        switch connection {
        case .openCodeGo: !(store.apiKey() ?? "").isEmpty
        case .openAI: !(store.openAIAPIKey() ?? "").isEmpty
        case .claude: !(store.claudeAPIKey() ?? "").isEmpty
        case .featherPlus: !(store.plusToken() ?? "").isEmpty
        }
    }

    public func makeProvider(
        apiKey: String = "",
        openAIAPIKey: String = "",
        plusToken: String? = nil,
        claudeAPIKey: String = ""
    ) -> any LLMProvider {
        switch connection {
        case .openCodeGo: OpenCodeGoProvider(apiKey: apiKey)
        case .openAI: OpenAIProvider(apiKey: openAIAPIKey)
        case .claude: ClaudeProvider(apiKey: claudeAPIKey)
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
    public static let providerOrder: [ConnectionKind] = [.featherPlus, .openAI, .claude, .openCodeGo]

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
        if !(store.openAIAPIKey() ?? "").isEmpty { setUp.insert(.openAI) }
        if !(store.claudeAPIKey() ?? "").isEmpty { setUp.insert(.claude) }
        if plusAvailable, store.plusToken() != nil { setUp.insert(.featherPlus) }
        return setUp
    }
}

