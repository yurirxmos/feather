import AppKit
import ApplicationServices

/// Reads the focused field and window of the target app through the Accessibility API.
enum AccessibilityContext {
    /// Keep the hotkey responsive when an app exposes a large accessibility tree.
    private static let windowTextBudget: TimeInterval = 0.7

    struct Snapshot: Sendable {
        var windowTitle: String?
        var focusedText: String?
        var selectedText: String?
        var windowText: String?
        var windowTextWasTruncated = false
        /// The focus was in a field the user types into, such as a message or email body.
        var focusIsInTextField = false
        /// Whether the focused field takes a password. Its text is never read, and Insert copies
        /// instead of pasting into it.
        var focusedFieldIsSecure = false
        /// Global coordinates with a top-left origin, matching `SCWindow.frame`.
        var windowFrame: CGRect?
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// The focused window's frame, read on its own so the panel can open before the slower
    /// text capture finishes.
    static func windowFrame(pid: pid_t) -> CGRect? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = element(app, kAXFocusedWindowAttribute),
              let origin = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func capture(pid: pid_t) -> Snapshot {
        var snapshot = Snapshot()
        guard isTrusted else { return snapshot }
        let app = AXUIElementCreateApplication(pid)
        // A hung target app must not freeze the hotkey.
        _ = AXUIElementSetMessagingTimeout(app, 0.3)
        // Chromium and Electron only build their web accessibility tree when asked. The first
        // capture after launch may still come back empty; the screenshot covers that case.
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // The selected text and field draft are the most useful context. Read them before
        // traversing the potentially large window tree.
        if let focused = element(app, kAXFocusedUIElementAttribute) {
            if isSecure(focused) {
                snapshot.focusedFieldIsSecure = true
            } else {
                snapshot.selectedText = string(focused, kAXSelectedTextAttribute)
                snapshot.focusedText = string(focused, kAXValueAttribute)
                snapshot.focusIsInTextField = isTextField(focused)
            }
        }
        if let window = element(app, kAXFocusedWindowAttribute) {
            snapshot.windowTitle = string(window, kAXTitleAttribute)
            let collected = windowText(window, deadline: Date().addingTimeInterval(windowTextBudget))
            snapshot.windowText = collected.text
            snapshot.windowTextWasTruncated = collected.wasTruncated
            if let origin = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) {
                snapshot.windowFrame = CGRect(origin: origin, size: size)
            }
        }
        return snapshot
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
            || string(element, kAXRoleAttribute) == "AXSecureTextField"
    }

    /// Native text fields report a text role; web editors (contenteditable) report an editable
    /// ancestor. A settable value is not enough: sliders and checkboxes have one too.
    private static func isTextField(_ element: AXUIElement) -> Bool {
        let textRoles: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField"]
        if let role = string(element, kAXRoleAttribute), textRoles.contains(role) { return true }
        return copy(element, "AXEditableAncestor") != nil
    }

    private static func windowText(_ window: AXUIElement, deadline: Date) -> (text: String?, wasTruncated: Bool) {
        let maxCharacters = 24_000
        let maxElements = 1_200
        // Web apps nest deeply: WhatsApp Web's messages sit 20 to 28 levels down.
        let maxDepth = 32
        var parts: [String] = []
        var characters = 0
        var elements = 0
        var wasTruncated = false

        func visit(_ element: AXUIElement, depth: Int) {
            guard Date() < deadline, depth < maxDepth, elements < maxElements, characters < maxCharacters else {
                wasTruncated = true
                return
            }
            elements += 1
            if !isSecure(element) {
                for attribute in [kAXTitleAttribute as String, kAXValueAttribute as String] {
                    if let value = string(element, attribute), value.count > 1,
                       !parts.contains(value), characters + value.count <= maxCharacters {
                        parts.append(value)
                        characters += value.count
                    }
                }
            }
            guard let children = copy(element, kAXChildrenAttribute as String) as? [AXUIElement] else { return }
            for child in children { visit(child, depth: depth + 1) }
        }

        visit(window, depth: 0)
        let text = parts.joined(separator: "\n")
        return (text.isEmpty ? nil : text, wasTruncated || elements >= maxElements || characters >= maxCharacters)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let text = copy(element, attribute) as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}
