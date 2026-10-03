import AppKit
import FeatherCore
import SwiftUI

struct PromptView: View {
    @ObservedObject var session: PromptSession
    let copyResult: () -> Void
    let retryResult: () -> Void
    let cancelGeneration: () -> Void
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTyping = false
    @State private var typingStopTask: Task<Void, Never>?

    private var hasResult: Bool { !session.result.isEmpty || !session.answer.isEmpty || session.isGenerating }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasContextPreview {
                contextPreview
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
                FeatherIcon(isAnimating: isTyping, reduceMotion: reduceMotion)
                    .frame(width: 20, height: 20)
                TextField(placeholder, text: $session.instruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .focused($isFieldFocused)
                    .disabled(session.isGenerating)
                    .opacity(session.isGenerating ? 0.45 : 1)
                    .animation(.easeOut(duration: 0.15), value: session.isGenerating)
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
                    primaryKeyHint
                    if canInsert {
                        secondaryKeyHints
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
        .onChange(of: session.isGenerating) { _, value in
            if !value { isFieldFocused = true }
        }
        .onChange(of: session.instruction) { _, value in
            updateTypingState(for: value)
        }
        .onDisappear {
            typingStopTask?.cancel()
        }
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
        !(session.context.selectedText ?? "").isEmpty || session.context.windowTextWasTruncated
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
            if session.context.windowTextWasTruncated {
                Label(String(localized: "Partial context", bundle: .app), systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var contextChips: some View {
        if let app = session.context.appName {
            ContextChip(
                title: app,
                systemImage: "app.dashed",
                isOn: session.options.includeApp
            ) { session.options.includeApp.toggle() }

        }

        if session.context.selectedText != nil {
            ContextChip(
                title: String(localized: "Text selected", bundle: .app),
                systemImage: "text.quote",
                isOn: session.options.includeSelection
            ) { session.options.includeSelection.toggle() }
        }

        if session.context.focusedText != nil {
            ContextChip(
                title: String(localized: "Focused text", bundle: .app),
                systemImage: "text.cursor",
                isOn: session.options.includeFocusedText
            ) { session.options.includeFocusedText.toggle() }
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
            KeyHint(key: "⌘ \(retryKey)", label: String(localized: "Retry", bundle: .app), action: retryResult)
        }
    }

    @ViewBuilder
    private var primaryKeyHint: some View {
        if canInsert {
            KeyHint(
                showsReturn: true,
                label: String(localized: "Insert", bundle: .app),
                isHighlighted: true
            )
        } else {
            KeyHint(showsReturn: true, label: String(localized: "Generate", bundle: .app))
        }
    }

    private var retryKey: String { String(localized: "R", bundle: .app) }

    private var canInsert: Bool {
        !session.result.isEmpty && !session.isGenerating
    }

    private func updateTypingState(for instruction: String) {
        typingStopTask?.cancel()
        guard !instruction.isEmpty else {
            withAnimation(.easeOut(duration: 0.22)) { isTyping = false }
            return
        }

        withAnimation(.easeIn(duration: 0.12)) { isTyping = true }
        typingStopTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { isTyping = false }
        }
    }

}

/// Tilts once while the user types. Nothing in the panel may animate forever: Feather is never
/// the active app, so every frame's commit blocks the main thread on the window server and
/// delays streaming, Insert, and key handling by seconds.
private struct FeatherIcon: View {
    let isAnimating: Bool
    let reduceMotion: Bool

    private var isTilted: Bool { isAnimating && !reduceMotion }

    var body: some View {
        FeatherShape()
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(isTilted ? -8 : 0))
            .offset(x: isTilted ? 2 : 0, y: isTilted ? -4 : 0)
            .foregroundStyle(isAnimating ? Color.accentColor : .white)
            .animation(.easeOut(duration: 0.28), value: isAnimating)
    }
}

private struct ContextChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
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
            .onTapGesture(perform: action)
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
        default: "Reading screen…"
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
