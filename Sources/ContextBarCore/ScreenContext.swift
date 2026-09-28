import Foundation

/// What was on screen when the hotkey was pressed. Captured once per invocation and discarded
/// when the prompt panel closes.
public struct ScreenContext: Equatable, Sendable {
    public var appName: String?
    public var bundleID: String?
    public var windowTitle: String?
    public var focusedText: String?
    public var selectedText: String?
    public var screenshotJPEG: Data?

    public init(
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil,
        focusedText: String? = nil,
        selectedText: String? = nil,
        screenshotJPEG: Data? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.focusedText = focusedText
        self.selectedText = selectedText
        self.screenshotJPEG = screenshotJPEG
    }
}

/// Which parts of the captured context the user allowed to be sent.
public struct ContextOptions: Equatable, Sendable {
    public var includeApp: Bool
    public var includeFocusedText: Bool
    public var includeWindow: Bool

    public init(includeApp: Bool = true, includeFocusedText: Bool = true, includeWindow: Bool = true) {
        self.includeApp = includeApp
        self.includeFocusedText = includeFocusedText
        self.includeWindow = includeWindow
    }
}
