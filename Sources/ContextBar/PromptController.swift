import AppKit
import ContextBarCore
import SwiftUI

/// State shown by `PromptView` for one hotkey invocation.
@MainActor
final class PromptSession: ObservableObject {
    @Published var instruction = ""
    @Published var result = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var context = ScreenContext()
    @Published var isCapturing = false
    @Published var options = ContextOptions()
    @Published var showScreenshot = false
    /// Bumped on every show so the view re-focuses its text field.
    @Published var focusToken = 0

    var history: [Exchange] = []
    var lastInstruction = ""

    func reset(includeWindow: Bool) {
        instruction = ""
        result = ""
        isGenerating = false
        errorMessage = nil
        notice = nil
        context = ScreenContext()
        isCapturing = false
        options = ContextOptions(includeApp: true, includeFocusedText: true, includeWindow: includeWindow)
        showScreenshot = false
        history = []
        lastInstruction = ""
    }
}

@MainActor
final class PromptController: NSObject, NSWindowDelegate {
    private let session = PromptSession()
    private lazy var panel: PromptPanel = makePanel()
    private var targetApp: NSRunningApplication?
    private var captureTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var keyMonitor: Any?

    func toggle() {
        panel.isVisible ? close() : show()
    }

    // MARK: Showing

    private func show() {
        // Remember the target before the panel takes keyboard focus.
        let front = NSWorkspace.shared.frontmostApplication
        targetApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let settings = Settings.current()
        session.reset(includeWindow: settings.includeScreenshot)
        startCapture(includeScreenshot: settings.includeScreenshot)

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            panel.position(on: screen)
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        session.focusToken += 1
    }

    /// Closes the panel and discards everything captured for this invocation.
    func close() {
        generationTask?.cancel()
        captureTask?.cancel()
        generationTask = nil
        captureTask = nil
        removeKeyMonitor()
        panel.orderOut(nil)
        session.reset(includeWindow: false)
    }

    private func makePanel() -> PromptPanel {
        let panel = PromptPanel.make()
        let hosting = NSHostingController(rootView: PromptView(session: session))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        return panel
    }

    private func startCapture(includeScreenshot: Bool) {
        guard let app = targetApp else { return }
        session.context.appName = app.localizedName
        session.context.bundleID = app.bundleIdentifier
        session.isCapturing = true
        let pid = app.processIdentifier
        captureTask = Task { [weak self] in
            let snapshot = await Task.detached { AccessibilityContext.capture(pid: pid) }.value
            guard let self, !Task.isCancelled else { return }
            session.context.windowTitle = snapshot.windowTitle
            session.context.focusedText = snapshot.focusedText
            session.context.selectedText = snapshot.selectedText
            if includeScreenshot {
                let jpeg = await WindowCapture.captureJPEG(pid: pid, title: snapshot.windowTitle, frame: snapshot.windowFrame)
                guard !Task.isCancelled else { return }
                session.context.screenshotJPEG = jpeg
            }
            session.isCapturing = false
        }
    }

    // MARK: Actions

    private func submit() {
        let text = session.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            generate(text)
        } else if !session.result.isEmpty, !session.isGenerating {
            insert()
        }
    }

    /// A new instruction after a result refines that result.
    private func generate(_ instruction: String) {
        if !session.result.isEmpty, !session.isGenerating {
            session.history.append(Exchange(instruction: session.lastInstruction, result: session.result))
        }
        session.lastInstruction = instruction
        session.instruction = ""
        run()
    }

    private func regenerate() {
        guard !session.lastInstruction.isEmpty else { return }
        run()
    }

    private func run() {
        generationTask?.cancel()
        session.result = ""
        session.errorMessage = nil
        session.notice = nil
        session.isGenerating = true
        let settings = Settings.current()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await captureTask?.value
            guard !Task.isCancelled else { return }
            let request = PromptBuilder.request(
                instruction: session.lastInstruction,
                context: session.context,
                options: session.options,
                history: session.history,
                model: settings.model
            )
            do {
                for try await text in settings.makeProvider().stream(request) {
                    session.result += text
                }
                session.result = session.result.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                guard !Task.isCancelled else { return }
                session.errorMessage = (error as? LLMError)?.localizedMessage ?? error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            session.isGenerating = false
        }
    }

    private func insert() {
        let text = session.result
        guard !text.isEmpty else { return }
        guard TextInserter.canPaste else {
            TextInserter.copy(text)
            session.notice = String(
                localized: "Copied to the clipboard. Grant Accessibility access in Settings to paste automatically.",
                bundle: .app
            )
            return
        }
        let app = targetApp
        close()
        Task { await TextInserter.paste(text, into: app) }
    }

    private func copyResult() {
        guard !session.result.isEmpty else { return }
        TextInserter.copy(session.result)
        close()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return event }
                return self.handle(event) ? nil : event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .option, .control, .command])
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        switch true {
        case event.keyCode == 53:
            close()
        case isReturn && modifiers == .command:
            copyResult()
        case isReturn && modifiers.isEmpty:
            submit()
        case modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "r":
            regenerate()
        default:
            return false
        }
        return true
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { close() }
    }

    func windowDidMove(_ notification: Notification) {
        panel.anchorTop = panel.frame.maxY
    }
}
