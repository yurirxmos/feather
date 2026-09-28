import AppKit
import ContextBarCore
import SwiftUI

struct PromptView: View {
    @ObservedObject var session: PromptSession
    @FocusState private var isFieldFocused: Bool

    private var hasResult: Bool { !session.result.isEmpty || session.isGenerating }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.tint)
                TextField(placeholder, text: $session.instruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .lineLimit(1...5)
                    .focused($isFieldFocused)
            }

            if hasResult {
                Divider()
                ScrollView {
                    Text(session.result.isEmpty ? String(localized: "Generating…", bundle: .app) : session.result)
                        .font(.system(size: 14))
                        .foregroundStyle(session.result.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let notice = session.notice {
                Label(notice, systemImage: "doc.on.clipboard")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if session.showScreenshot, session.options.includeWindow,
               let data = session.context.screenshotJPEG, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 6) {
                contextChips
                Spacer(minLength: 12)
                keyHints
            }
        }
        .padding(16)
        .frame(width: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .onAppear { isFieldFocused = true }
        .onChange(of: session.focusToken) { isFieldFocused = true }
    }

    private var placeholder: String {
        hasResult
            ? String(localized: "Refine: shorter, more formal…", bundle: .app)
            : String(localized: "What do you want to write?", bundle: .app)
    }

    @ViewBuilder
    private var contextChips: some View {
        if let app = session.context.appName {
            ContextChip(
                title: [session.context.windowTitle.map(shortTitle), app].compactMap { $0 }.joined(separator: " · "),
                systemImage: "app.dashed",
                isOn: session.options.includeApp
            ) { session.options.includeApp.toggle() }

            if session.context.focusedText != nil || session.context.selectedText != nil {
                ContextChip(
                    title: session.context.selectedText != nil
                        ? String(localized: "Selection", bundle: .app)
                        : String(localized: "Focused text", bundle: .app),
                    systemImage: "text.cursor",
                    isOn: session.options.includeFocusedText
                ) { session.options.includeFocusedText.toggle() }
            }

            if session.context.screenshotJPEG != nil {
                ContextChip(
                    title: String(localized: "Window", bundle: .app),
                    systemImage: session.showScreenshot ? "eye.fill" : "macwindow",
                    isOn: session.options.includeWindow
                ) {
                    // First click previews what will be sent; the next click excludes it.
                    if session.options.includeWindow && !session.showScreenshot {
                        session.showScreenshot = true
                    } else if session.options.includeWindow {
                        session.options.includeWindow = false
                        session.showScreenshot = false
                    } else {
                        session.options.includeWindow = true
                    }
                }
            }
            if session.isCapturing {
                ProgressView().controlSize(.small)
            }
        } else {
            Text("No app context", bundle: .app)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var keyHints: some View {
        HStack(spacing: 10) {
            if session.result.isEmpty || session.isGenerating {
                KeyHint(key: "↩", label: String(localized: "Generate", bundle: .app))
            } else {
                KeyHint(key: "↩", label: String(localized: "Insert", bundle: .app))
                KeyHint(key: "⌘↩", label: String(localized: "Copy", bundle: .app))
                KeyHint(key: "⌘R", label: String(localized: "Retry", bundle: .app))
            }
            KeyHint(key: "esc", label: String(localized: "Close", bundle: .app))
        }
    }

    private func shortTitle(_ title: String) -> String {
        title.count > 32 ? String(title.prefix(31)) + "…" : title
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
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .strikethrough(!isOn)
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 4)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}
