import AppKit
import FeatherCore
import SwiftUI

struct PromptView: View {
    @ObservedObject var session: PromptSession
    let insertResult: () -> Void
    let copyResult: () -> Void
    let retryResult: () -> Void
    let newConversation: () -> Void
    let cancelGeneration: () -> Void
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTyping = false
    @State private var strokes = 0
    @State private var typingStopTask: Task<Void, Never>?

    private var hasResult: Bool { !session.result.isEmpty || !session.answer.isEmpty || session.isGenerating }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasContextPreview {
                contextPreview
            }

            if let index = session.browsingIndex {
                browsingCaption(index: index)
            }

            // Paid plans answer questions; the answer is for reading and only the suggestion is inserted.
            if !session.answer.isEmpty {
                blockLabel(String(localized: "Answer", bundle: .app))
                answerBlock(session.answer, muted: false)
            }
            if !session.answer.isEmpty, !session.result.isEmpty {
                blockLabel(String(localized: "Suggested text", bundle: .app))
            }
            if !session.result.isEmpty {
                responseBlock(session.result, muted: session.isGenerating)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                FeatherIcon(isAnimating: isTyping, strokes: strokes, reduceMotion: reduceMotion)
                    .frame(width: 20, height: 20)
                TextField(placeholder, text: $session.instruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .focused($isFieldFocused)
                    .disabled(isFieldDisabled)
                    .opacity(isFieldDisabled ? 0.45 : 1)
                    .animation(.easeOut(duration: 0.15), value: isFieldDisabled)
            }

            if session.isGenerating {
                Divider()
                GeneratingIndicator(startedAt: session.generationStartedAt ?? .now, cancel: cancelGeneration)
                if !session.streamingAnswer.isEmpty {
                    answerBlock(session.streamingAnswer, muted: true)
                }
                if !session.streamingResult.isEmpty {
                    responseBlock(session.streamingResult, muted: true)
                }
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.95))
            }
            if let notice = session.notice {
                Label(notice, systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
            }
            if session.suggestsPlus, !session.isGenerating, !session.result.isEmpty {
                Text("To get answers to your questions while Feather writes, subscribe to Feather Plus.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if session.showScreenshot, session.options.includeWindow,
               let data = session.context.screenshotJPEG, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        contextChips
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if canStartNewConversation {
                        KeyHint(key: "⌘ \(newKey)", label: String(localized: "New", bundle: .app), action: newConversation)
                    }
                    primaryKeyHint
                    if canInsert {
                        secondaryKeyHints
                    } else if canCopyAnswer {
                        retryKeyHint
                    }
                }
                .fixedSize()
            }
        }
        .padding(16)
        .frame(width: 600)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: session.focusToken) {
            isFieldFocused = true
        }
        .onChange(of: isFieldDisabled) { _, value in
            if !value { isFieldFocused = true }
        }
        .onChange(of: session.instruction) { _, value in
            updateTypingState(for: value)
        }
        .onDisappear {
            typingStopTask?.cancel()
        }
    }

    /// The panel opens before the window text is read; typing waits for it.
    private var isFieldDisabled: Bool {
        session.isGenerating || session.captureStatus == .readingScreen
    }

    private var placeholder: String {
        hasResult
            ? String(localized: "Refine: shorter, more formal…", bundle: .app)
            : String(localized: "What do you want to write?", bundle: .app)
    }

    private func responseBlock(_ text: String, muted: Bool) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(muted ? Color.white.opacity(0.52) : Color.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Shown while ↑ and ↓ move through recent conversations.
    private func browsingCaption(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text(String(format: String(localized: "Previous conversation %1$d of %2$d", bundle: .app), locale: .current, index + 1, session.browsingCount))
                Spacer(minLength: 8)
                Text("↑ ↓")
                    .font(.system(size: 11, design: .monospaced))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            if !session.lastInstruction.isEmpty {
                Text(session.lastInstruction)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }

    private func blockLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.white.opacity(0.55))
    }

    private func answerBlock(_ text: String, muted: Bool) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(muted ? Color.white.opacity(0.52) : Color.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var hasContextPreview: Bool {
        !(session.context.selectedText ?? "").isEmpty
    }

    private var contextPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected = session.context.selectedText, !selected.isEmpty {
                Text(selected.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var contextChips: some View {
        if session.context.focusIsInTextField {
            TextFieldBadge()
        }

        if let app = session.context.appName {
            ContextChip(
                title: app,
                systemImage: "app.dashed",
                isOn: session.options.includeApp,
                help: String(localized: "Feather knows which app you are in", bundle: .app)
            ) { session.options.includeApp.toggle() }

        }

        if session.context.selectedText != nil {
            ContextChip(
                title: String(localized: "Text selected", bundle: .app),
                systemImage: "text.quote",
                isOn: session.options.includeSelection,
                help: String(localized: "Feather sees the text you selected", bundle: .app)
            ) { session.options.includeSelection.toggle() }
        }

        if session.context.windowText != nil {
            // A window too large to read whole within the capture limits is read in part.
            let isPartial = session.context.windowTextWasTruncated
            ContextChip(
                title: isPartial ? String(localized: "Partial window", bundle: .app) : String(localized: "Window", bundle: .app),
                systemImage: "macwindow",
                isOn: session.options.includeWindowText,
                help: isPartial
                    ? String(localized: "This window is too large to read whole, so Feather read only part of it", bundle: .app)
                    : String(localized: "Feather is reading the window you are in", bundle: .app)
            ) { session.options.includeWindowText.toggle() }
        }

        if session.isCapturing {
            CaptureIndicator(status: session.captureStatus)
        }
        if session.context.appName == nil && session.context.selectedText == nil && session.context.windowText == nil {
            Text("No app context", bundle: .app)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var secondaryKeyHints: some View {
        HStack(spacing: 10) {
            KeyHint(key: "⌘", showsReturn: true, label: String(localized: "Copy", bundle: .app), action: copyResult)
            retryKeyHint
        }
    }

    private var retryKeyHint: some View {
        KeyHint(key: "⌘ \(retryKey)", label: String(localized: "Retry", bundle: .app), action: retryResult)
    }

    @ViewBuilder
    private var primaryKeyHint: some View {
        if canInsert {
            KeyHint(
                showsReturn: true,
                label: String(localized: "Insert", bundle: .app),
                isHighlighted: true,
                action: insertResult
            )
        } else if canCopyAnswer {
            // Only an answer came back, so there is nothing to insert.
            KeyHint(
                showsReturn: true,
                label: String(localized: "Copy", bundle: .app),
                isHighlighted: true,
                action: copyResult
            )
        } else {
            KeyHint(showsReturn: true, label: String(localized: "Generate", bundle: .app))
        }
    }

    private var retryKey: String { String(localized: "R", bundle: .app) }
    private var newKey: String { String(localized: "N", bundle: .app) }

    /// ⌘N works at any time; the hint shows once there is a conversation to leave.
    private var canStartNewConversation: Bool {
        !session.result.isEmpty || !session.answer.isEmpty || session.isGenerating
    }

    private var canInsert: Bool {
        !session.result.isEmpty && !session.isGenerating
    }

    private var canCopyAnswer: Bool {
        session.result.isEmpty && !session.answer.isEmpty && !session.isGenerating
    }

    private func updateTypingState(for instruction: String) {
        typingStopTask?.cancel()
        guard !instruction.isEmpty else {
            withAnimation(.easeOut(duration: 0.22)) { isTyping = false }
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            isTyping = true
            strokes += 1
        }
        typingStopTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { isTyping = false }
        }
    }

}

/// Writes while the user types: each keystroke swings the feather the other way around its nib,
/// and it settles once typing stops. Nothing in the panel may animate forever: Feather is never
/// the active app, so every frame's commit blocks the main thread on the window server and
/// delays streaming, Insert, and key handling by seconds.
private struct FeatherIcon: View {
    let isAnimating: Bool
    let strokes: Int
    let reduceMotion: Bool

    /// The nib, at the bottom left of `FeatherShape`.
    private static let nib = UnitPoint(x: 0.15, y: 0.95)

    private var isWriting: Bool { isAnimating && !reduceMotion }
    private var isUpstroke: Bool { strokes.isMultiple(of: 2) }

    var body: some View {
        FeatherShape()
            .rotationEffect(.degrees(isWriting ? (isUpstroke ? -14 : 6) : 0), anchor: Self.nib)
            .offset(x: isWriting ? (isUpstroke ? 1 : -0.5) : 0, y: isWriting ? (isUpstroke ? -1 : 0.5) : 0)
            .foregroundStyle(isAnimating ? Color.accentColor : .white)
            .animation(.easeOut(duration: 0.28), value: isAnimating)
    }
}

private struct ContextChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOn ? Color.white.opacity(0.18) : Color.white.opacity(0.07), in: Capsule())
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.55))
            .strikethrough(!isOn)
            .contentShape(Capsule())
            .help(help)
            .onTapGesture(perform: action)
            .pointingHandCursor()
    }
}

/// Shows that the shortcut was pressed while typing in a field, so Insert writes the reply there.
private struct TextFieldBadge: View {
    var body: some View {
        Label(String(localized: "Typing in a field", bundle: .app), systemImage: "character.cursor.ibeam")
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.55)))
            .foregroundStyle(.white)
            .help(String(localized: "Feather opened while you were typing; Insert writes the reply in that field", bundle: .app))
    }
}

private struct CaptureIndicator: View {
    let status: PromptSession.CaptureStatus?

    var body: some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini).tint(.white.opacity(0.75))
            Text(label, bundle: .app)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .transition(.opacity)
    }

    private var label: LocalizedStringKey {
        switch status {
        case .capturingWindow: "Capturing window…"
        default: "Reading window…"
        }
    }
}

/// Static on purpose; see `FeatherIcon`. The elapsed time already shows progress.
private struct GeneratingIndicator: View {
    let startedAt: Date
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Generating…", bundle: .app)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                Text(ElapsedTime.string(timeline.date.timeIntervalSince(startedAt)))
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.4))
                    .contentTransition(.identity)
            }
            Button(action: cancel) {
                Text("Cancel", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 20)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KeyHint: View {
    var key = ""
    var showsReturn = false
    let label: String
    var isHighlighted = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .pointingHandCursor()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                if !key.isEmpty {
                    Text(key)
                }
                if showsReturn {
                    ReturnKeyShape()
                        .frame(width: 11, height: 11)
                }
            }
            .font(.caption.monospaced())
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 20)
            .background(
                isHighlighted ? Color.blue.opacity(0.9) : Color.white.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            Text(label)
                .font(.caption)
                .foregroundStyle(
                    isHighlighted ? Color.blue.opacity(0.9) : Color.white.opacity(0.75)
                )
        }
        .foregroundStyle(.white.opacity(0.58))
    }

}
