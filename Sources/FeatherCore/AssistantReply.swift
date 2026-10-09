import Foundation

/// Splits an assistant-mode response into the answer shown to the user and the suggestion that is
/// inserted. Mirrors `Reply` in the desktop app's `core/reply.rs`.
public struct AssistantReply: Equatable, Sendable {
    public static let answerOpen = "<answer>"
    public static let answerClose = "</answer>"

    /// What Feather says to the user. Empty unless the instruction asked a question.
    public var answer: String
    /// The text to insert into the focused field.
    public var suggestion: String

    public init(answer: String = "", suggestion: String = "") {
        self.answer = answer
        self.suggestion = suggestion
    }

    /// Reads a complete or still-streaming response. Type assist has no answer, so the whole text
    /// is the suggestion.
    public init(parsing text: String, mode: PromptMode) {
        let trimmed = { (value: Substring) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard mode == .assistant else {
            self.init(suggestion: ReplyCleanup.unwrap(text))
            return
        }
        let body = text.drop(while: \.isWhitespace)
        guard body.hasPrefix(Self.answerOpen) else {
            // A half-streamed opening tag is not text yet.
            if !body.isEmpty, Self.answerOpen.hasPrefix(body) {
                self.init()
            } else {
                self.init(suggestion: ReplyCleanup.unwrap(String(body)))
            }
            return
        }
        let rest = body.dropFirst(Self.answerOpen.count)
        if let close = rest.range(of: Self.answerClose) {
            self.init(answer: trimmed(rest[..<close.lowerBound]), suggestion: ReplyCleanup.unwrap(String(rest[close.upperBound...])))
        } else {
            // Still inside the answer; hide a half-streamed closing tag.
            let partial = (1..<Self.answerClose.count).reversed().first { rest.hasSuffix(Self.answerClose.prefix($0)) } ?? 0
            self.init(answer: trimmed(rest.dropLast(partial)))
        }
    }

    /// The response as the model wrote it, so follow-ups keep the format.
    public var raw: String {
        answer.isEmpty ? suggestion : "\(Self.answerOpen)\(answer)\(Self.answerClose)\n\n\(suggestion)"
    }
}
