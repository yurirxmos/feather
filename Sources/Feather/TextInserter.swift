import AppKit
import Carbon.HIToolbox

/// Puts generated text into the target app's focused field by pasting, then restores the
/// user's clipboard. Pasting works in web apps (Gmail, WhatsApp Web, Slack) where writing
/// `kAXSelectedTextAttribute` does not.
enum TextInserter {
    /// Posting ⌘V needs the same Accessibility trust as reading the focused field.
    static var canPaste: Bool { AccessibilityContext.isTrusted }

    @MainActor
    static func paste(_ text: String, into app: NSRunningApplication?) async {
        app?.activate()
        try? await Task.sleep(for: .milliseconds(150))

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        postCommandV()
        try? await Task.sleep(for: .milliseconds(400))

        // Leave the clipboard alone if something else wrote to it in the meantime.
        if pasteboard.changeCount == ourChangeCount {
            restore(saved, to: pasteboard)
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
