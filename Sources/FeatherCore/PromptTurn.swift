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
    case none
}

/// Pure decisions for one prompt invocation. AppKit remains in the controller adapter.
public enum PromptTurn {
    public static let closingCountdownSeconds = [3, 2, 1]

    public static func mergeWindowText(_ newText: String?, with existing: String?) -> String? {
        guard let newText, !newText.isEmpty else { return existing }
        guard let existing, !existing.isEmpty else { return newText }
        let existingLines = Set(existing.split(separator: "\n").map(String.init))
        let additions = newText.split(separator: "\n").map(String.init).filter { !existingLines.contains($0) }
        return additions.isEmpty ? existing : existing + "\n" + additions.joined(separator: "\n")
    }

    public static func submission(instruction: String, result: String, isGenerating: Bool) -> PromptSubmission {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return .generate(trimmed) }
        if !result.isEmpty && !isGenerating { return .insert }
        return .none
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
