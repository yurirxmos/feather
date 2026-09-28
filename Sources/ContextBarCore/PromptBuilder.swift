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
        You write text that the user will insert into the text field they are focused on. \
        Output only the final text to insert: no preamble, no explanations, no surrounding quotes, \
        no Markdown unless the field clearly supports it. Match the language, tone, and conventions \
        of the conversation on screen unless the instruction says otherwise. Use the screenshot, \
        the window title, and the focused field's text as context. If the focused field already \
        contains a draft, rewrite or continue it as instructed rather than repeating it verbatim. \
        When the user asks a question about what is on screen instead of asking you to write \
        something, answer it concisely.
        """

    /// Long fields keep their tail, which is where the cursor usually is.
    public static let maxFieldCharacters = 8_000

    public static func request(
        instruction: String,
        context: ScreenContext,
        options: ContextOptions,
        history: [Exchange] = [],
        model: String,
        maxTokens: Int = 16_000
    ) -> GenerationRequest {
        let instructions = history.map(\.instruction) + [instruction]
        var turns = [Turn(role: .user, text: firstTurn(instruction: instructions[0], context: context, options: options))]
        for (index, exchange) in history.enumerated() {
            turns.append(Turn(role: .assistant, text: exchange.result))
            turns.append(Turn(role: .user, text: instructions[index + 1]))
        }
        return GenerationRequest(
            system: systemPrompt,
            turns: turns,
            imageJPEG: options.includeWindow ? context.screenshotJPEG : nil,
            model: model,
            maxTokens: maxTokens
        )
    }

    public static func firstTurn(instruction: String, context: ScreenContext, options: ContextOptions) -> String {
        var lines: [String] = []
        if options.includeApp {
            if let app = nonEmpty(context.appName) {
                lines.append("App: \(app)" + (nonEmpty(context.bundleID).map { " (\($0))" } ?? ""))
            }
            if let title = nonEmpty(context.windowTitle) {
                lines.append("Window: \(title)")
            }
        }
        if options.includeFocusedText {
            if let selected = nonEmpty(context.selectedText) {
                lines.append("Selected text:\n\"\"\"\n\(truncated(selected))\n\"\"\"")
            }
            if let focused = nonEmpty(context.focusedText), focused != context.selectedText {
                lines.append("Focused field text:\n\"\"\"\n\(truncated(focused))\n\"\"\"")
            }
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
