import Foundation

public struct PromptKeyInput: Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool
    public var characters: String?

    public init(keyCode: UInt16, command: Bool, shift: Bool = false, option: Bool = false, control: Bool = false, characters: String? = nil) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
        self.characters = characters
    }
}

public enum PromptCommand: Equatable, Sendable {
    case cancel
    case copy
    case submit
    case regenerate
    /// ↑ and ↓: move through recent conversations.
    case older
    case newer
}

public enum PromptSubmission: Equatable, Sendable {
    case generate(String)
    case insert
    /// Only an answer came back, so there is nothing to insert; Enter copies the answer.
    case copy
    case none
}

/// Pure decisions for one prompt invocation. AppKit remains in the controller adapter.
public enum PromptTurn {
    /// How long "Copied to clipboard." stays up; copying never closes the panel.
    public static let copiedNoticeDuration: Duration = .seconds(2)

    public static func mergeWindowText(_ newText: String?, with existing: String?) -> String? {
        guard let newText, !newText.isEmpty else { return existing }
        guard let existing, !existing.isEmpty else { return newText }
        let existingLines = Set(existing.split(separator: "\n").map(String.init))
        let additions = newText.split(separator: "\n").map(String.init).filter { !existingLines.contains($0) }
        return additions.isEmpty ? existing : existing + "\n" + additions.joined(separator: "\n")
    }

    public static func submission(instruction: String, result: String, answer: String = "", isGenerating: Bool) -> PromptSubmission {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return .generate(trimmed) }
        guard !isGenerating else { return .none }
        if !result.isEmpty { return .insert }
        if !answer.isEmpty { return .copy }
        return .none
    }

    /// The text ⌘↵ copies: the suggestion, or the answer when no suggestion came back.
    public static func copyableText(result: String, answer: String) -> String {
        result.isEmpty ? answer : result
    }

    private static let questionWords: Set<String> = [
        "what", "why", "how", "who", "which", "where",
        "qual", "quais", "quem", "onde", "quanto", "quanta", "quantos", "quantas", "pq",
    ]
    private static let questionPhrases = ["o que", "por que", "por quê"]

    /// Whether an instruction reads as a question. Only Feather Plus answers questions, so the
    /// other connections point to it when one is asked. Ambiguous openers such as "como" or
    /// "when" are left out so ordinary messages don't get the pointer.
    public static func looksLikeQuestion(_ instruction: String) -> Bool {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("?") || text.hasPrefix("¿") { return true }
        let words = text.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        // "what's" opens a question as much as "what".
        guard let first = words.first?.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) else { return false }
        if questionWords.contains(first) { return true }
        return words.count > 1 && questionPhrases.contains("\(first) \(words[1])")
    }

    public static func history(
        _ history: [Exchange],
        lastInstruction: String,
        result: String,
        isGenerating: Bool
    ) -> [Exchange] {
        guard !result.isEmpty, !isGenerating else { return history }
        return history + [Exchange(instruction: lastInstruction, result: result)]
    }

    public static func command(for input: PromptKeyInput) -> PromptCommand? {
        let noModifiers = !input.command && !input.shift && !input.option && !input.control
        let onlyCommand = input.command && !input.shift && !input.option && !input.control
        switch input.keyCode {
        case 53: return .cancel
        case 36, 76:
            if onlyCommand { return .copy }
            if noModifiers { return .submit }
            return nil
        case 126: return noModifiers ? .older : nil
        case 125: return noModifiers ? .newer : nil
        default:
            return onlyCommand && input.characters?.lowercased() == "r" ? .regenerate : nil
        }
    }
}
