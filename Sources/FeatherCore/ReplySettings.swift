import Foundation

/// Everything in Settings > Replies. Signed in to a Feather account, they are saved to it, plan or
/// not, so every computer signed in to the same account replies the same way
/// (`/v1/reply-settings` on feather-api).
///
/// The choices keep their stored ids as strings, so one a newer app added survives a round trip
/// through this one; `Settings.current` falls back to the default for ids it doesn't know.
public struct ReplySettings: Codable, Equatable, Sendable {
    public var customInstructions: String
    public var includeScreenshot: Bool
    public var tone: String
    public var length: String
    public var language: String

    enum CodingKeys: String, CodingKey {
        case customInstructions = "custom_instructions"
        case includeScreenshot = "include_screenshot"
        case tone = "reply_tone"
        case length = "reply_length"
        case language = "reply_language"
    }

    public init(customInstructions: String, includeScreenshot: Bool, tone: String, length: String, language: String) {
        self.customInstructions = customInstructions
        self.includeScreenshot = includeScreenshot
        self.tone = tone
        self.length = length
        self.language = language
    }

    /// The settings as stored on this computer, with the same defaults as `Settings.current`.
    public static func stored(in defaults: UserDefaults = .standard) -> ReplySettings {
        ReplySettings(
            customInstructions: defaults.string(forKey: SettingsKey.customInstructions) ?? "",
            includeScreenshot: defaults.object(forKey: SettingsKey.includeScreenshot) as? Bool ?? true,
            tone: defaults.string(forKey: SettingsKey.replyTone) ?? ReplyTone.natural.rawValue,
            length: defaults.string(forKey: SettingsKey.replyLength) ?? ReplyLength.matchRequest.rawValue,
            language: defaults.string(forKey: SettingsKey.replyLanguage) ?? ReplyLanguage.conversation.rawValue
        )
    }

    /// Stores these settings on this computer, where Settings and the next reply read them.
    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(customInstructions, forKey: SettingsKey.customInstructions)
        defaults.set(includeScreenshot, forKey: SettingsKey.includeScreenshot)
        defaults.set(tone, forKey: SettingsKey.replyTone)
        defaults.set(length, forKey: SettingsKey.replyLength)
        defaults.set(language, forKey: SettingsKey.replyLanguage)
    }

    /// What to do once the account's settings arrive.
    public enum SyncAction: Equatable, Sendable {
        /// Both already match.
        case none
        /// Take the account's settings.
        case apply(ReplySettings)
        /// Save this computer's settings to the account.
        case upload(ReplySettings)
    }

    /// The account's settings win, except when this computer has a change it hasn't saved yet
    /// (made offline, say) or the account has none: then this computer's are saved.
    public static func syncAction(local: ReplySettings, remote: ReplySettings?, localChangePending: Bool) -> SyncAction {
        guard let remote, !localChangePending else { return .upload(local) }
        return remote == local ? .none : .apply(remote)
    }
}
