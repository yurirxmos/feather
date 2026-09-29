import AppKit
import ApplicationServices

/// Reads the focused field and window of the target app through the Accessibility API.
enum AccessibilityContext {
    struct Snapshot: Sendable {
        var windowTitle: String?
        var focusedText: String?
        var selectedText: String?
        var windowText: String?
        var windowTextWasTruncated = false
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
            let collected = windowText(window)
            snapshot.windowText = collected.text
            snapshot.windowTextWasTruncated = collected.wasTruncated
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

    private static func windowText(_ window: AXUIElement) -> (text: String?, wasTruncated: Bool) {
        let maxCharacters = 24_000
        let maxElements = 1_200
        var parts: [String] = []
        var characters = 0
        var elements = 0
        var wasTruncated = false

        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 18, elements < maxElements, characters < maxCharacters else {
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
