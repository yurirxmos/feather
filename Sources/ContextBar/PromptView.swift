import AppKit
import ContextBarCore
import SwiftUI

struct PromptView: View {
    @ObservedObject var session: PromptSession
    let copyResult: () -> Void
    let retryResult: () -> Void
    @AppStorage(SettingsKey.connection) private var connection: ConnectionKind = .openCodeGo
    @AppStorage(SettingsKey.model) private var model = OpenCodeGoProvider.defaultModel
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var insertPulse = false
    @State private var isTyping = false
    @State private var typingStopTask: Task<Void, Never>?
    @State private var isShowingModelPicker = false
    @State private var openCodeModels: [String] = []
    @State private var isLoadingModels = false

    private var hasResult: Bool { !session.result.isEmpty || session.isGenerating }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            contextToolbar

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
            }

            if session.isGenerating {
                Divider()
                if session.streamingResult.isEmpty {
                    GeneratingIndicator()
                } else {
                    responseBlock(session.streamingResult, muted: true)
                }
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.95))
            }
            if let notice = session.notice {
                Label(notice, systemImage: "doc.on.clipboard")
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

            HStack {
                if canInsert {
                    secondaryKeyHints
                }
                Spacer()
                primaryKeyHint
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
            updateInsertPulse(canInsert)
        }
        .onChange(of: session.focusToken) { isFieldFocused = true }
        .onChange(of: canInsert) { _, value in updateInsertPulse(value) }
        .onChange(of: session.instruction) { _, value in
            updateTypingState(for: value)
        }
        .onChange(of: isShowingModelPicker) { _, isPresented in
            guard isPresented, connection == .openCodeGo else { return }
            loadOpenCodeModels()
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

    private var contextToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        contextChips
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { isShowingModelPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(model)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Change model", bundle: .app))
                .popover(isPresented: $isShowingModelPicker, arrowEdge: .top) {
                    modelPicker
                }
            }
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
            KeyHint(key: "⌘ \(enterKey)", label: String(localized: "Copy", bundle: .app), action: copyResult)
            KeyHint(key: "⌘ \(retryKey)", label: String(localized: "Retry", bundle: .app), action: retryResult)
        }
    }

    @ViewBuilder
    private var primaryKeyHint: some View {
        if canInsert {
            KeyHint(
                key: enterKey,
                label: String(localized: "Insert", bundle: .app),
                isHighlighted: true,
                pulse: insertPulse,
                allowsAnimation: !reduceMotion
            )
        } else {
            KeyHint(key: enterKey, label: String(localized: "Generate", bundle: .app))
        }
    }

    private var enterKey: String { "↩" }
    private var retryKey: String { String(localized: "R", bundle: .app) }

    @ViewBuilder
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model", bundle: .app)
                .font(.headline)
            if connection == .chatGPT {
                Picker(String(localized: "Model", bundle: .app), selection: $model) {
                    ForEach(ChatGPTModelCatalog.models) { availableModel in
                        Text(availableModel.name).tag(availableModel.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } else {
                if isLoadingModels && openCodeModels.isEmpty {
                    ProgressView(String(localized: "Loading models…", bundle: .app))
                        .controlSize(.small)
                } else {
                    Picker(String(localized: "Model", bundle: .app), selection: $model) {
                        ForEach(modelsForPicker, id: \.self) { availableModel in
                            Text(availableModel).tag(availableModel)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var modelsForPicker: [String] {
        Array(Set(openCodeModels + [model])).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func loadOpenCodeModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        Task {
            defer { isLoadingModels = false }
            guard let apiKey = Keychain.apiKey(), !apiKey.isEmpty,
                  let fetchedModels = try? await OpenCodeGoModelCatalog.fetchModels(apiKey: apiKey)
            else { return }
            openCodeModels = fetchedModels
        }
    }

    private var canInsert: Bool {
        !session.result.isEmpty && !session.isGenerating
    }

    private func updateInsertPulse(_ active: Bool) {
        insertPulse = active
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

private struct FeatherIcon: View {
    let isAnimating: Bool
    let reduceMotion: Bool
    @State private var phase = false

    var body: some View {
        FeatherShape()
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(isAnimating && phase ? -8 : 0))
            .offset(
                x: isAnimating && phase ? 2 : 0,
                y: isAnimating && phase ? -4 : 0
            )
            .foregroundStyle(isAnimating ? Color.accentColor : .white)
            .onAppear { updateAnimation(isActive: isAnimating) }
            .onChange(of: isAnimating) { _, value in updateAnimation(isActive: value) }
            .animation(.easeOut(duration: 0.28), value: isAnimating)
    }

    private func updateAnimation(isActive: Bool) {
        guard isActive, !reduceMotion else {
            phase = false
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            phase = true
        }
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

private struct GeneratingIndicator: View {
    @State private var isDimmed = true

    var body: some View {
        Text("Generating…", bundle: .app)
            .font(.system(size: 14, design: .serif))
            .foregroundStyle(.white.opacity(isDimmed ? 0.32 : 0.68))
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isDimmed = false
                }
            }
    }
}

private struct KeyHint: View {
    let key: String
    let label: String
    var isHighlighted = false
    var pulse = false
    var allowsAnimation = true
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
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 5)
                .frame(minWidth: 22, minHeight: 20)
                .background(
                    isHighlighted ? Color.blue.opacity(pulse ? 0.95 : 0.58) : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(
                    isHighlighted ? Color.blue.opacity(pulse ? 0.95 : 0.58) : Color.white.opacity(0.75)
                )
        }
        .foregroundStyle(.white.opacity(0.58))
        .animation(
            allowsAnimation ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : nil,
            value: pulse
        )
    }

}
