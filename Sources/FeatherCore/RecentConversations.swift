import Foundation

/// A finished panel conversation, kept on this computer so ↑ can bring it back. It holds only what
/// the user typed and what Feather replied; screen context is never saved.
public struct SavedConversation: Codable, Equatable, Sendable {
    /// Earlier turns, as sent back to the model when the conversation is refined.
    public var history: [Exchange]
    public var lastInstruction: String
    public var answer: String
    public var result: String

    public init(history: [Exchange], lastInstruction: String, answer: String, result: String) {
        self.history = history
        self.lastInstruction = lastInstruction
        self.answer = answer
        self.result = result
    }
}

/// The last few conversations, newest first, and how ↑ and ↓ move through them.
public enum RecentConversations {
    public static let limit = 5

    public enum Direction: Sendable {
        /// ↑: one conversation further back.
        case older
        /// ↓: one conversation closer to the current one.
        case newer
    }

    /// The conversation worth saving from a panel, or nil when it produced nothing.
    public static func conversation(history: [Exchange], lastInstruction: String, answer: String, result: String) -> SavedConversation? {
        guard !result.isEmpty || !answer.isEmpty else { return nil }
        return SavedConversation(history: history, lastInstruction: lastInstruction, answer: answer, result: result)
    }

    /// Puts `conversation` first. A conversation brought back with ↑ and then changed replaces
    /// the one it came from, and one that was only viewed keeps its place.
    public static func saving(_ conversation: SavedConversation, restoredFrom original: SavedConversation?, in list: [SavedConversation]) -> [SavedConversation] {
        if conversation == original { return list }
        var list = list
        if let original, let index = list.firstIndex(of: original) { list.remove(at: index) }
        list.removeAll { $0 == conversation }
        return Array(([conversation] + list).prefix(limit))
    }

    /// The index shown after a key press: nil is the current conversation, 0 the newest saved one.
    public static func browse(from index: Int?, _ direction: Direction, count: Int) -> Int? {
        switch direction {
        case .older:
            guard count > 0 else { return index }
            return min((index ?? -1) + 1, count - 1)
        case .newer:
            guard let index else { return nil }
            return index == 0 ? nil : index - 1
        }
    }

    /// Reads the saved list, ignoring a missing or unreadable file.
    public static func decode(_ data: Data?) -> [SavedConversation] {
        guard let data, let list = try? JSONDecoder().decode([SavedConversation].self, from: data) else { return [] }
        return Array(list.prefix(limit))
    }

    public static func encode(_ list: [SavedConversation]) -> Data? {
        try? JSONEncoder().encode(Array(list.prefix(limit)))
    }
}
