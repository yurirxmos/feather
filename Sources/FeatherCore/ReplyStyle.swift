import Foundation

/// The tone replies are written in. `natural` follows the conversation on screen.
public enum ReplyTone: String, CaseIterable, Identifiable, Sendable {
    case natural
    case friendly
    case professional
    case casual

    public var id: String { rawValue }

    var directive: String? {
        switch self {
        case .natural: nil
        case .friendly: "Write in a warm, friendly tone."
        case .professional: "Write in a professional, polished tone."
        case .casual: "Write in a casual, relaxed tone."
        }
    }
}

/// How long replies are. `matchRequest` leaves it to the instruction.
public enum ReplyLength: String, CaseIterable, Identifiable, Sendable {
    case matchRequest
    case short
    case detailed

    public var id: String { rawValue }

    var directive: String? {
        switch self {
        case .matchRequest: nil
        case .short: "Keep replies short and to the point."
        case .detailed: "Write detailed, complete replies."
        }
    }
}

/// The language replies are written in. `conversation` matches the conversation on screen.
public enum ReplyLanguage: String, CaseIterable, Identifiable, Sendable {
    case conversation
    case english
    case portuguese

    public var id: String { rawValue }

    var directive: String? {
        switch self {
        case .conversation: nil
        case .english: "Write in English, whatever language the conversation is in."
        case .portuguese: "Write in Brazilian Portuguese, whatever language the conversation is in."
        }
    }
}

/// The Style choices in Settings > Replies. They reach the model as writing preferences, ahead of
/// the user's own instructions, so those can refine them.
public struct ReplyStyle: Equatable, Sendable {
    public var tone: ReplyTone
    public var length: ReplyLength
    public var language: ReplyLanguage

    public static let standard = ReplyStyle(tone: .natural, length: .matchRequest, language: .conversation)

    public init(tone: ReplyTone, length: ReplyLength, language: ReplyLanguage) {
        self.tone = tone
        self.length = length
        self.language = language
    }

    /// The writing preferences for the system prompt: one line per choice that isn't the default,
    /// then the custom instructions.
    public func writingPreferences(customInstructions: String) -> String {
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = [tone.directive, length.directive, language.directive].compactMap { $0 } + (custom.isEmpty ? [] : [custom])
        return lines.joined(separator: "\n")
    }
}
