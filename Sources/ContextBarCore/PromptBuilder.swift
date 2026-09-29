import Foundation

public struct Exchange: Equatable, Sendable {
    public var instruction: String
    public var result: String

    public init(instruction: String, result: String) {
        self.instruction = instruction
        self.result = result
    }
}

public enum PromptBuilder {
    public static let systemPrompt = """
        You generate text the user can insert into a field or copy elsewhere. Only write, rewrite, \
        continue, translate, summarize, or adapt text. Do not act as a general-purpose assistant, \
        answer factual questions, explain content, or hold a conversation. If an instruction does \
        not request text generation, reply briefly that the user should describe the text they want \
        to write. Output only the final text: no preamble, explanations, surrounding quotes, or \
        Markdown unless the destination clearly supports it. Match the language, tone, and \
        conventions of the conversation on screen unless the instruction says otherwise. Use the \
        available window text, screenshot, window title, and focused field text as context. Context \
        may be partial; never invent missing content or claim to have seen content that was not \
        provided. If the focused field already contains a draft, rewrite or continue it as \
        instructed rather than repeating it verbatim.
        """

    /// Long fields keep their tail, which is where the cursor usually is.
    public static let maxFieldCharacters = 8_000

    public static func request(
        instruction: String,
        context: ScreenContext,
        options: ContextOptions,
        history: [Exchange] = [],
        model: String,
        maxTokens: Int = 16_000,
        sessionID: String = "",
        includeContext: Bool = true
    ) -> GenerationRequest {
        let instructions = history.map(\.instruction) + [instruction]
        var turns = [Turn(role: .user, text: firstTurn(instruction: instructions[0], context: context, options: options, includeContext: includeContext))]
        for (index, exchange) in history.enumerated() {
            turns.append(Turn(role: .assistant, text: exchange.result))
            turns.append(Turn(role: .user, text: instructions[index + 1]))
        }
        return GenerationRequest(
            system: systemPrompt,
            turns: turns,
            imageJPEG: includeContext && options.includeWindow ? context.screenshotJPEG : nil,
            model: model,
            maxTokens: maxTokens,
            sessionID: sessionID
        )
    }

    public static func firstTurn(
        instruction: String,
        context: ScreenContext,
        options: ContextOptions,
        includeContext: Bool = true
    ) -> String {
        guard includeContext else { return "Instruction: \(instruction)" }
        var lines: [String] = []
        if options.includeApp {
            if let app = nonEmpty(context.appName) {
                lines.append("App: \(app)" + (nonEmpty(context.bundleID).map { " (\($0))" } ?? ""))
            }
            if let title = nonEmpty(context.windowTitle) {
                lines.append("Window: \(title)")
            }
        }
        if options.includeSelection, let selected = nonEmpty(context.selectedText) {
                lines.append("Selected text:\n\"\"\"\n\(truncated(selected))\n\"\"\"")
        }
        if options.includeFocusedText {
            if let focused = nonEmpty(context.focusedText), focused != context.selectedText {
                lines.append("Focused field text:\n\"\"\"\n\(truncated(focused))\n\"\"\"")
            }
        }
        if options.includeWindowText, let windowText = nonEmpty(context.windowText) {
            let label = context.windowTextWasTruncated ? "Window text (partial)" : "Window text"
            lines.append("\(label):\n\"\"\"\n\(truncated(windowText))\n\"\"\"")
        }
        if options.includeWindow, context.screenshotJPEG != nil {
            lines.append("A screenshot of the active window is attached.")
        }
        let contextBlock = lines.isEmpty ? "No screen context was provided." : lines.joined(separator: "\n")
        return "<context>\n\(contextBlock)\n</context>\n\nInstruction: \(instruction)"
    }

    static func truncated(_ text: String) -> String {
        guard text.count > maxFieldCharacters else { return text }
        return "[…earlier text omitted]\n" + text.suffix(maxFieldCharacters)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
