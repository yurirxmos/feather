import Foundation

/// Strips the wrapping a chat model sometimes puts around the text despite the prompt, such as
/// "Here is a comment:" and `---` before it and "Hope this helps!" after it, so only the text is
/// inserted. It only removes what is clearly wrapping: a closing remark goes only when the text
/// was also introduced or set off by separators, because a real message can end with
/// "Let me know". Mirrors `core/cleanup.rs` in the desktop app.
public enum ReplyCleanup {
    /// How an introduction opens, lowercased; it must end there or before a non-letter.
    static let introductions = [
        "here's", "here is", "here are", "sure", "of course", "certainly", "absolutely", "below", "this is", "aqui está",
        "aqui estão", "aqui vai", "aqui vão", "segue", "seguem", "claro", "com certeza", "certo", "perfeito", "abaixo",
        "este é", "esta é", "eis",
    ]

    /// How a closing remark opens, lowercased.
    static let closings = [
        "espero que", "hope this", "hope that", "hope it", "let me know", "feel free", "se quiser", "se precisar",
        "caso queira", "caso precise", "quer que eu", "posso ajustar", "posso mudar", "posso fazer", "if you like",
        "if you want", "if you need", "if you'd like", "i can adjust", "i can also adjust", "i can make", "i can change",
        "would you like", "fique à vontade",
    ]

    public static func unwrap(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: "\n")

        if let first = lines.firstIndex(where: isSeparator) {
            let last = lines.lastIndex(where: isSeparator) ?? first
            let before = joined(lines[..<first])
            let body = last > first ? lines[(first + 1)..<last] : lines[(first + 1)...]
            let after = last > first ? joined(lines[(last + 1)...]) : ""
            if before.isEmpty || isIntroduction(before, allowsAnyColonLine: true), isShortRemark(after), !joined(body).isEmpty {
                return unquoted(joined(body))
            }
            return unquoted(trimmed)
        }

        guard let firstLine = lines.first, isIntroduction(firstLine, allowsAnyColonLine: false) else {
            return unquoted(trimmed)
        }
        lines.removeFirst()
        // The text itself has not arrived yet.
        guard !joined(lines[...]).isEmpty else { return "" }
        if let index = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           isClosingRemark(lines[index]), !joined(lines[..<index]).isEmpty {
            lines.removeSubrange(index...)
        }
        return unquoted(joined(lines[...]))
    }

    private static func joined(_ lines: ArraySlice<String>) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `---`, `***`, `___`, or a code fence such as ```` ```text ````.
    private static func isSeparator(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") {
            return line.dropFirst(3).allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }
        let marks: [Character] = ["-", "*", "_"]
        return line.count >= 3 && marks.contains { mark in line.allSatisfy { $0 == mark } }
    }

    private static func opens(_ line: String, with prefixes: [String], wholeWord: Bool) -> Bool {
        let lower = line.lowercased()
        return prefixes.contains { prefix in
            guard lower.hasPrefix(prefix) else { return false }
            return !wholeWord || !(lower.dropFirst(prefix.count).first?.isLetter ?? false)
        }
    }

    /// A short line that announces the text. Before a separator, any short line ending in a colon
    /// counts; otherwise it must also open like an introduction, so "Dear team:" stays.
    private static func isIntroduction(_ text: String, allowsAnyColonLine: Bool) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.count <= 200, !line.contains("\n\n") else { return false }
        let introduces = opens(line, with: introductions, wholeWord: true)
        return allowsAnyColonLine ? (line.hasSuffix(":") || introduces) : (introduces && line.hasSuffix(":"))
    }

    private static func isClosingRemark(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespaces)
        return line.count <= 160 && opens(line, with: closings, wholeWord: false)
    }

    private static func isShortRemark(_ text: String) -> Bool {
        text.count <= 200 && !text.contains("\n\n")
    }

    /// Removes quotes around the whole text when they are not also used inside it.
    private static func unquoted(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»")]
        for (open, close) in pairs where text.count > 2 && text.first == open && text.last == close {
            let inner = text.dropFirst().dropLast()
            if !inner.contains(open), !inner.contains(close) {
                return inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}
