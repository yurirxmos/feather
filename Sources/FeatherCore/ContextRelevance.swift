import Foundation

/// Decides whether an instruction is likely to benefit from the captured screen context.
public enum ContextRelevance {
    private static let contextTerms = [
        "this", "that", "it", "here", "selected", "selection", "the text", "the message", "the field",
        "reply", "respond", "summarize", "summary", "translate", "rewrite", "rephrase", "fix", "correct",
        "improve", "continue", "complete", "isto", "isso", "este", "esta", "esse", "essa", "aqui",
        "selecionado", "selecionada", "seleção", "o texto", "a mensagem", "o campo", "responda", "responder",
        "resuma", "resumir", "traduza", "traduzir", "reescreva", "reescrever", "corrija", "corrigir",
        "melhore", "melhorar", "continue", "continuar", "complete", "completar",
    ]

    /// Returns false only for instructions that are clearly independent of the active screen.
    public static func needsContext(_ instruction: String) -> Bool {
        let normalized = instruction
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        return contextTerms.contains { term in
            normalized == term || normalized.contains(" \(term) ") || normalized.hasPrefix("\(term) ")
                || normalized.hasSuffix(" \(term)")
        }
    }
}
