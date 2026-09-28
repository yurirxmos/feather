import AppKit
import ApplicationServices

/// Reads the focused field and window of the target app through the Accessibility API.
enum AccessibilityContext {
    struct Snapshot: Sendable {
        var windowTitle: String?
        var focusedText: String?
        var selectedText: String?
        /// Global coordinates with a top-left origin, matching `SCWindow.frame`.
        var windowFrame: CGRect?
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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

        if let window = element(app, kAXFocusedWindowAttribute) {
            snapshot.windowTitle = string(window, kAXTitleAttribute)
            if let origin = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) {
                snapshot.windowFrame = CGRect(origin: origin, size: size)
            }
        }
        if let focused = element(app, kAXFocusedUIElementAttribute), !isSecure(focused) {
            snapshot.selectedText = string(focused, kAXSelectedTextAttribute)
            snapshot.focusedText = string(focused, kAXValueAttribute)
        }
        return snapshot
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
            || string(element, kAXRoleAttribute) == "AXSecureTextField"
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
