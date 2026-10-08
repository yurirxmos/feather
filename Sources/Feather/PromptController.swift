import AppKit
import FeatherCore
import os
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
    /// What Feather says to the user, in assistant mode only; `result` is the text to insert.
    @Published var answer = ""
    @Published var streamingAnswer = ""
    @Published var isGenerating = false
    @Published var generationStartedAt: Date?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var context = ScreenContext()
    @Published var isCapturing = false
    @Published var captureStatus: CaptureStatus?
    @Published var options = ContextOptions()
    @Published var showScreenshot = false
    /// The last instruction was a question on a connection that only assists typing.
    @Published var suggestsPlus = false
    /// Bumped on every show so the view re-focuses its text field.
    @Published var focusToken = 0

    var history: [Exchange] = []
    var lastInstruction = ""
    /// Which recent conversation ↑ brought back: nil is this panel's own, 0 the newest saved one.
    @Published var browsingIndex: Int?
    @Published var browsingCount = 0
    /// This panel's own conversation, put back when ↓ returns to it.
    var ownConversation: SavedConversation?
    /// The saved conversation shown or refined here, replaced when this one is saved.
    var restoredFrom: SavedConversation?
    /// The turn state before the running generation, restored when it is cancelled.
    var turnBeforeGeneration: (history: [Exchange], lastInstruction: String)?
    var sessionID = UUID().uuidString
    var isSuspendedForRecapture = false
    var captureCount = 0

    /// Clears the conversation but keeps what was captured, so a new one starts on the same screen.
    func startNewConversation() {
        instruction = ""
        result = ""
        streamingResult = ""
        answer = ""
        streamingAnswer = ""
        isGenerating = false
        generationStartedAt = nil
        errorMessage = nil
        notice = nil
        suggestsPlus = false
        history = []
        lastInstruction = ""
        browsingIndex = nil
        browsingCount = 0
        ownConversation = nil
        restoredFrom = nil
        turnBeforeGeneration = nil
        sessionID = UUID().uuidString
        focusToken += 1
    }

    func reset(includeWindow: Bool) {
        instruction = ""
        result = ""
        streamingResult = ""
        answer = ""
        streamingAnswer = ""
        isGenerating = false
        generationStartedAt = nil
        errorMessage = nil
        notice = nil
        context = ScreenContext()
        isCapturing = false
        captureStatus = nil
        options = ContextOptions(includeApp: true, includeFocusedText: true, includeWindow: includeWindow)
        showScreenshot = false
        suggestsPlus = false
        history = []
        lastInstruction = ""
        browsingIndex = nil
        browsingCount = 0
        ownConversation = nil
        restoredFrom = nil
        turnBeforeGeneration = nil
        sessionID = UUID().uuidString
        isSuspendedForRecapture = false
        captureCount = 0
    }
}

@MainActor
final class PromptController: NSObject, NSWindowDelegate {
    /// Timings only; screen content, instructions, and responses are never logged.
    private static let timingLogger = Logger(subsystem: "com.feather.app", category: "generation")

    private let credentialStore: any CredentialStore
    private let session = PromptSession()
    private let recentConversations = RecentConversationStore.shared
    private lazy var panel: PromptPanel = makePanel()
    private var targetApp: NSRunningApplication?
    /// Feather's own window that was key when the shortcut was pressed, such as the welcome
    /// guide's practice box. Replies go straight into its field: ⌘V posted to Feather itself
    /// pastes nowhere, because the menu-bar app has no Edit menu.
    private weak var ownWindow: NSWindow?
    private var captureTask: Task<Void, Never>?
    private var screenshotTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var isPresenting = false

    init(credentialStore: any CredentialStore = KeychainCredentialStore.shared) {
        self.credentialStore = credentialStore
        super.init()
    }

    func toggle() {
        if panel.isVisible || isPresenting {
            suspendForRecapture()
        } else {
            show()
        }
    }

    // MARK: Showing

    private func show() {
        // Remember the target before the panel takes keyboard focus.
        let front = NSWorkspace.shared.frontmostApplication
        let isFeather = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        targetApp = isFeather ? nil : front
        ownWindow = isFeather ? NSApp.keyWindow : nil

        let settings = FeatherCore.Settings.current()
        if !session.isSuspendedForRecapture {
            saveConversation()
            session.reset(includeWindow: settings.includeScreenshot)
        } else {
            session.options.includeWindow = settings.includeScreenshot
        }
        isPresenting = true
        // Connecting can take seconds on a cold or flaky network; do it while the user types.
        let provider = settings.makeProvider()
        Task.detached(priority: .utility) { await provider.preconnect() }
        startCapture(includeScreenshot: settings.includeScreenshot)
    }

    /// Closes the panel and discards everything captured for this invocation.
    func close() {
        noticeTask?.cancel()
        generationTask?.cancel()
        captureTask?.cancel()
        screenshotTask?.cancel()
        noticeTask = nil
        generationTask = nil
        captureTask = nil
        screenshotTask = nil
        removeKeyMonitor()
        isPresenting = false
        panel.orderOut(nil)
        restoreOwnWindow()
        saveConversation()
        session.reset(includeWindow: false)
    }

    // MARK: Recent conversations

    private var currentConversation: SavedConversation? {
        RecentConversations.conversation(
            history: session.history,
            lastInstruction: session.lastInstruction,
            answer: session.answer,
            result: session.result
        )
    }

    /// Keeps the finished conversation on this computer for ↑. Screen context is not part of it.
    private func saveConversation() {
        guard !session.isGenerating, let conversation = currentConversation else { return }
        recentConversations.save(conversation, restoredFrom: session.restoredFrom)
    }

    /// ↑ and ↓ with an empty field move through recent conversations. Returns false when there is
    /// nowhere to go, so the key keeps its usual meaning.
    private func browse(_ direction: RecentConversations.Direction) -> Bool {
        guard session.instruction.isEmpty, !session.isGenerating else { return false }
        let saved = recentConversations.conversations
        let index = RecentConversations.browse(from: session.browsingIndex, direction, count: saved.count)
        guard index != session.browsingIndex else { return false }
        if session.browsingIndex == nil {
            session.ownConversation = currentConversation
        }
        let shown = index.map { saved[$0] } ?? session.ownConversation
        session.history = shown?.history ?? []
        session.lastInstruction = shown?.lastInstruction ?? ""
        session.answer = shown?.answer ?? ""
        session.result = shown?.result ?? ""
        session.restoredFrom = index.map { saved[$0] }
        session.browsingIndex = index
        session.browsingCount = saved.count
        session.errorMessage = nil
        session.notice = nil
        session.suggestsPlus = false
        return true
    }

    /// Hides the panel without discarding the task, allowing the user to scroll and capture again.
    /// A running generation keeps going, so clicking away to reread the conversation loses nothing.
    private func suspendForRecapture() {
        captureTask?.cancel()
        screenshotTask?.cancel()
        captureTask = nil
        screenshotTask = nil
        removeKeyMonitor()
        session.isCapturing = false
        session.captureStatus = nil
        session.isSuspendedForRecapture = true
        isPresenting = false
        panel.orderOut(nil)
        restoreOwnWindow()
    }

    /// Gives the keyboard back to Feather's own window; closing a key panel does not.
    private func restoreOwnWindow() {
        guard NSApp.isActive, let ownWindow, ownWindow.isVisible else { return }
        ownWindow.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> PromptPanel {
        let panel = PromptPanel.make()
        let hosting = NSHostingController(
            rootView: PromptView(
                session: session,
                insertResult: { [weak self] in self?.insert() },
                copyResult: { [weak self] in self?.copyResult() },
                retryResult: { [weak self] in self?.regenerate() },
                newConversation: { [weak self] in self?.startNewConversation() },
                cancelGeneration: { [weak self] in self?.cancelGeneration() }
            )
        )
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        return panel
    }

    private func startCapture(includeScreenshot: Bool) {
        guard let app = targetApp else {
            if let screen = screenUnderPointer() { panel.position(on: screen) }
            presentPanel()
            return
        }
        session.context.appName = app.localizedName
        session.context.bundleID = app.bundleIdentifier
        session.isCapturing = true
        session.captureStatus = .readingScreen
        let pid = app.processIdentifier
        captureTask = Task { [weak self] in
            // Open the panel as soon as the window's position is known; the field stays disabled
            // while the window text is read, which can take up to the capture budget.
            let frame = await Task.detached { AccessibilityContext.windowFrame(pid: pid) }.value
            guard let self, !Task.isCancelled else { return }
            if let frame, let primaryScreen {
                let appKitFrame = PanelPlacement.appKitFrame(fromAccessibilityFrame: frame, primaryScreenFrame: primaryScreen.frame)
                let screen = screen(intersecting: appKitFrame) ?? primaryScreen
                panel.position(on: screen, windowFrame: appKitFrame)
            } else {
                if let screen = screenUnderPointer() { panel.position(on: screen) }
            }
            presentPanel()

            let snapshot = await Task.detached { AccessibilityContext.capture(pid: pid) }.value
            guard !Task.isCancelled else { return }
            session.context.windowTitle = snapshot.windowTitle ?? session.context.windowTitle
            session.context.focusedText = snapshot.focusedText ?? session.context.focusedText
            session.context.selectedText = snapshot.selectedText ?? session.context.selectedText
            session.context.windowText = PromptTurn.mergeWindowText(snapshot.windowText, with: session.context.windowText)
            session.context.windowTextWasTruncated = session.context.windowTextWasTruncated || snapshot.windowTextWasTruncated
            session.context.focusIsInTextField = session.context.focusIsInTextField || snapshot.focusIsInTextField
            session.captureCount += 1
            if includeScreenshot {
                session.captureStatus = .capturingWindow
                // A screenshot improves visual context but must not delay a submitted prompt.
                // Keep it in a separate task so `run()` only waits for the text capture above.
                screenshotTask = Task { [weak self] in
                    let jpeg = await WindowCapture.captureJPEG(pid: pid, title: snapshot.windowTitle, frame: snapshot.windowFrame)
                    guard let self, !Task.isCancelled else { return }
                    session.context.screenshotJPEG = jpeg
                    session.isCapturing = false
                    session.captureStatus = nil
                }
            } else {
                session.isCapturing = false
                session.captureStatus = nil
            }
        }
    }

    private var primaryScreen: NSScreen? {
        // NSScreen.main follows keyboard focus; AX's top-left origin is anchored to the primary display.
        NSScreen.screens.first
    }

    private func screen(intersecting frame: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })
    }

    private func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? primaryScreen
    }

    private func presentPanel() {
        guard isPresenting else { return }
        isPresenting = false
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        session.isSuspendedForRecapture = false
        installKeyMonitor()
        session.focusToken += 1

        guard panel.alphaValue == 0 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    // MARK: Actions

    private func submit() {
        switch PromptTurn.submission(instruction: session.instruction, result: session.result, answer: session.answer, isGenerating: session.isGenerating) {
        case .generate(let text): generate(text)
        case .insert: insert()
        case .copy: copyResult()
        case .none: break
        }
    }

    /// A new instruction after a result refines that result.
    private func generate(_ instruction: String) {
        session.turnBeforeGeneration = (session.history, session.lastInstruction)
        session.history = PromptTurn.history(
            session.history,
            lastInstruction: session.lastInstruction,
            result: AssistantReply(answer: session.answer, suggestion: session.result).raw,
            isGenerating: session.isGenerating
        )
        session.lastInstruction = instruction
        session.instruction = ""
        // A refined conversation is this panel's own again, and replaces the one it came from.
        session.browsingIndex = nil
        run()
    }

    /// Saves this conversation for ↑ and starts a new one on the same screen.
    private func startNewConversation() {
        noticeTask?.cancel()
        noticeTask = nil
        cancelGeneration()
        saveConversation()
        session.startNewConversation()
    }

    private func regenerate() {
        guard !session.lastInstruction.isEmpty else { return }
        session.turnBeforeGeneration = (session.history, session.lastInstruction)
        run()
    }

    /// Stops the stream, keeps the previous result, and puts the instruction back for editing.
    private func cancelGeneration() {
        guard session.isGenerating else { return }
        generationTask?.cancel()
        generationTask = nil
        let instruction = session.lastInstruction
        if let previous = session.turnBeforeGeneration {
            session.history = previous.history
            session.lastInstruction = previous.lastInstruction
        }
        session.turnBeforeGeneration = nil
        session.streamingResult = ""
        session.streamingAnswer = ""
        session.generationStartedAt = nil
        session.isGenerating = false
        if session.instruction.isEmpty {
            session.instruction = instruction
        }
    }

    private func run() {
        generationTask?.cancel()
        session.streamingResult = ""
        session.streamingAnswer = ""
        session.errorMessage = nil
        session.notice = nil
        session.isGenerating = true
        session.generationStartedAt = .now
        let settings = FeatherCore.Settings.current()
        // Only the paid plans answer questions; the free version assists typing.
        let mode: PromptMode = settings.connection == .featherPlus ? .assistant : .typeAssist
        session.suggestsPlus = mode == .typeAssist && FeatherPlus.isEnabled() && PromptTurn.looksLikeQuestion(session.lastInstruction)
        generationTask = Task { [weak self] in
            guard let self else { return }
            await captureTask?.value
            guard !Task.isCancelled else { return }
            let provider: LLMProvider
            switch settings.connection {
            case .openAI:
                provider = settings.makeProvider(openAIAPIKey: credentialStore.openAIAPIKey() ?? "")
            case .claude:
                provider = settings.makeProvider(claudeAPIKey: credentialStore.claudeAPIKey() ?? "")
            case .featherPlus:
                guard let token = credentialStore.plusToken() else {
                    session.errorMessage = String(localized: "Sign in to Feather Plus in Settings.", bundle: .app)
                    session.isGenerating = false
                    return
                }
                provider = settings.makeProvider(plusToken: token)
            case .openCodeGo:
                provider = settings.makeProvider(apiKey: credentialStore.apiKey() ?? "")
            }
            let request = PromptBuilder.request(
                instruction: session.lastInstruction,
                context: session.context,
                options: session.options,
                history: session.history,
                model: settings.model,
                sessionID: session.sessionID,
                includeContext: true,
                customInstructions: settings.replyStyle.writingPreferences(customInstructions: settings.customInstructions),
                mode: mode
            )
            let requestStartedAt = ContinuousClock.now
            var firstTextAfter: Duration?
            var text = ""
            var publishedAt = requestStartedAt
            var outcome = "completed"
            do {
                for try await chunk in provider.stream(request) {
                    text += chunk
                    if firstTextAfter == nil { firstTextAfter = requestStartedAt.duration(to: .now) }
                    // Every published delta re-lays out the panel; a few updates per second
                    // still read as live typing.
                    if publishedAt.duration(to: .now) >= .milliseconds(80) {
                        let reply = AssistantReply(parsing: text, mode: mode)
                        session.streamingResult = reply.suggestion
                        session.streamingAnswer = reply.answer
                        publishedAt = .now
                    }
                }
                guard !Task.isCancelled else { return }
                let reply = AssistantReply(parsing: text, mode: mode)
                session.result = reply.suggestion
                session.answer = reply.answer
            } catch {
                guard !Task.isCancelled else { return }
                let partial = AssistantReply(parsing: text, mode: mode)
                if error as? LLMError == .timedOut, !partial.suggestion.isEmpty || !partial.answer.isEmpty {
                    outcome = "timed_out_with_text"
                    session.result = partial.suggestion
                    session.answer = partial.answer
                    session.notice = String(localized: "Stopped after 1 minute. Review the text before inserting it.", bundle: .app)
                } else {
                    outcome = "failed"
                    session.errorMessage = (error as? LLMError)?.localizedMessage ?? error.localizedDescription
                }
            }
            session.streamingResult = ""
            session.streamingAnswer = ""
            session.isGenerating = false
            logTiming(outcome: outcome, firstTextAfter: firstTextAfter, total: requestStartedAt.duration(to: .now))
        }
    }

    private func logTiming(outcome: String, firstTextAfter: Duration?, total: Duration) {
        func seconds(_ duration: Duration) -> String {
            String(format: "%.2fs", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }
        let firstText = firstTextAfter.map(seconds) ?? "none"
        Self.timingLogger.notice("generation \(outcome, privacy: .public): first_text=\(firstText, privacy: .public) total=\(seconds(total), privacy: .public)")
    }

    private func insert() {
        let text = session.result
        guard !text.isEmpty else { return }
        if let field = ownWindow?.firstResponder as? NSTextView {
            close()
            field.insertText(text, replacementRange: field.selectedRange())
            return
        }
        guard targetApp != nil, TextInserter.canPaste else {
            TextInserter.copy(text)
            showCopiedNotice(explanation: TextInserter.canPaste
                ? String(localized: "Copied. Paste it with ⌘V.", bundle: .app)
                : String(localized: "Copied. To insert text, allow Feather in System Settings › Privacy & Security › Accessibility. For now, paste it with ⌘V.", bundle: .app))
            return
        }
        let app = targetApp
        close()
        Task { await TextInserter.paste(text, into: app) }
    }

    private func copyResult() {
        let text = PromptTurn.copyableText(result: session.result, answer: session.answer)
        guard !text.isEmpty else { return }
        TextInserter.copy(text)
        showCopiedNotice()
    }

    /// Copying keeps the panel open, so the user can copy again, refine, or insert. The plain
    /// notice fades after a moment; an explanation of why Insert copied instead stays up.
    private func showCopiedNotice(explanation: String? = nil) {
        noticeTask?.cancel()
        noticeTask = nil
        guard explanation == nil else {
            session.notice = explanation
            return
        }
        let notice = String(localized: "Copied to clipboard.", bundle: .app)
        session.notice = notice
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: PromptTurn.copiedNoticeDuration)
            guard let self, !Task.isCancelled, session.notice == notice else { return }
            session.notice = nil
        }
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
        let command = PromptTurn.command(for: PromptKeyInput(
            keyCode: event.keyCode,
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift),
            option: modifiers.contains(.option),
            control: modifiers.contains(.control),
            characters: event.charactersIgnoringModifiers
        ))
        switch command {
        case .cancel:
            suspendForRecapture()
        case .copy:
            copyResult()
        case .submit:
            submit()
        case .regenerate:
            regenerate()
        case .newConversation:
            startNewConversation()
        case .older:
            return browse(.older)
        case .newer:
            return browse(.newer)
        case nil:
            return false
        }
        return true
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { suspendForRecapture() }
    }

    func windowDidMove(_ notification: Notification) {
        panel.anchorBottom = panel.frame.minY
    }
}
