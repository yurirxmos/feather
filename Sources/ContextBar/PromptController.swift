import AppKit
import ContextBarCore
import SwiftUI

/// State shown by `PromptView` for one hotkey invocation.
@MainActor
final class PromptSession: ObservableObject {
    enum CaptureStatus {
        case readingScreen
        case capturingWindow
    }

    @Published var instruction = ""
    @Published var result = ""
    @Published var streamingResult = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var context = ScreenContext()
    @Published var isCapturing = false
    @Published var captureStatus: CaptureStatus?
    @Published var options = ContextOptions()
    @Published var showScreenshot = false
    /// Bumped on every show so the view re-focuses its text field.
    @Published var focusToken = 0

    var history: [Exchange] = []
    var lastInstruction = ""
    var sessionID = UUID().uuidString
    var isSuspendedForRecapture = false
    var captureCount = 0

    func reset(includeWindow: Bool) {
        instruction = ""
        result = ""
        streamingResult = ""
        isGenerating = false
        errorMessage = nil
        notice = nil
        context = ScreenContext()
        isCapturing = false
        captureStatus = nil
        options = ContextOptions(includeApp: true, includeFocusedText: true, includeWindow: includeWindow)
        showScreenshot = false
        history = []
        lastInstruction = ""
        sessionID = UUID().uuidString
        isSuspendedForRecapture = false
        captureCount = 0
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
        if panel.isVisible {
            suspendForRecapture()
        } else {
            show()
        }
    }

    // MARK: Showing

    private func show() {
        // Remember the target before the panel takes keyboard focus.
        let front = NSWorkspace.shared.frontmostApplication
        targetApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let settings = Settings.current()
        if !session.isSuspendedForRecapture {
            session.reset(includeWindow: settings.includeScreenshot)
        } else {
            session.options.includeWindow = settings.includeScreenshot
        }
        startCapture(includeScreenshot: settings.includeScreenshot)

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            panel.position(on: screen)
        }
        panel.makeKeyAndOrderFront(nil)
        session.isSuspendedForRecapture = false
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

    /// Hides the panel without discarding the task, allowing the user to scroll and capture again.
    private func suspendForRecapture() {
        generationTask?.cancel()
        captureTask?.cancel()
        generationTask = nil
        captureTask = nil
        removeKeyMonitor()
        session.isSuspendedForRecapture = true
        panel.orderOut(nil)
    }

    private func makePanel() -> PromptPanel {
        let panel = PromptPanel.make()
        let hosting = NSHostingController(
            rootView: PromptView(
                session: session,
                copyResult: { [weak self] in self?.copyResult() },
                retryResult: { [weak self] in self?.regenerate() }
            )
        )
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
        session.captureStatus = .readingScreen
        let pid = app.processIdentifier
        captureTask = Task { [weak self] in
            let snapshot = await Task.detached { AccessibilityContext.capture(pid: pid) }.value
            guard let self, !Task.isCancelled else { return }
            if let frame = snapshot.windowFrame {
                let screenTop = NSScreen.main?.frame.maxY ?? 0
                let appKitFrame = NSRect(
                    x: frame.origin.x,
                    y: screenTop - frame.origin.y - frame.size.height,
                    width: frame.size.width,
                    height: frame.size.height
                )
                let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitFrame) }) ?? NSScreen.main
                if let screen {
                panel.position(on: screen, windowFrame: appKitFrame)
                }
            }
            session.context.windowTitle = snapshot.windowTitle ?? session.context.windowTitle
            session.context.focusedText = snapshot.focusedText ?? session.context.focusedText
            session.context.selectedText = snapshot.selectedText ?? session.context.selectedText
            session.context.windowText = merge(snapshot.windowText, with: session.context.windowText)
            session.context.windowTextWasTruncated = session.context.windowTextWasTruncated || snapshot.windowTextWasTruncated
            session.captureCount += 1
            if includeScreenshot {
                session.captureStatus = .capturingWindow
                let jpeg = await WindowCapture.captureJPEG(pid: pid, title: snapshot.windowTitle, frame: snapshot.windowFrame)
                guard !Task.isCancelled else { return }
                session.context.screenshotJPEG = jpeg
            }
            session.isCapturing = false
            session.captureStatus = nil
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
        session.streamingResult = ""
        session.errorMessage = nil
        session.notice = nil
        session.isGenerating = true
        let settings = Settings.current()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await captureTask?.value
            guard !Task.isCancelled else { return }
            let provider: LLMProvider
            if settings.connection == .chatGPT {
                do {
                    let credentials = try await ChatGPTAuth.validCredentials()
                    provider = settings.makeProvider(accessToken: credentials.accessToken, accountID: credentials.accountID)
                } catch {
                    session.errorMessage = error.localizedDescription
                    session.isGenerating = false
                    return
                }
            } else {
                provider = settings.makeProvider()
            }
            let request = PromptBuilder.request(
                instruction: session.lastInstruction,
                context: session.context,
                options: session.options,
                history: session.history,
                model: settings.model,
                sessionID: session.sessionID,
                includeContext: true
            )
            do {
                for try await text in provider.stream(request) {
                    session.streamingResult += text
                }
                session.result = session.streamingResult.trimmingCharacters(in: .whitespacesAndNewlines)
                session.streamingResult = ""
            } catch {
                guard !Task.isCancelled else { return }
                session.errorMessage = (error as? LLMError)?.localizedMessage ?? error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            session.isGenerating = false
        }
    }

    private func merge(_ newText: String?, with oldText: String?) -> String? {
        guard let newText, !newText.isEmpty else { return oldText }
        guard let oldText, !oldText.isEmpty else { return newText }
        let oldParts = Set(oldText.split(separator: "\n").map(String.init))
        let additions = newText.split(separator: "\n").map(String.init).filter { !oldParts.contains($0) }
        return additions.isEmpty ? oldText : oldText + "\n" + additions.joined(separator: "\n")
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
        session.notice = String(localized: "Copied to the clipboard.", bundle: .app)
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
            suspendForRecapture()
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
        if panel.isVisible { suspendForRecapture() }
    }

    func windowDidMove(_ notification: Notification) {
        panel.anchorTop = panel.frame.maxY
    }
}
