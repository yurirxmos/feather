import Foundation

/// What was on screen when the hotkey was pressed. Captured once per invocation and discarded
/// when the prompt panel closes.
public struct ScreenContext: Equatable, Sendable {
    public var appName: String?
    public var bundleID: String?
    public var windowTitle: String?
    public var focusedText: String?
    public var selectedText: String?
    public var windowText: String?
    public var windowTextWasTruncated: Bool
    /// The shortcut was pressed while typing in a field, such as a message or email body.
    public var focusIsInTextField: Bool
    public var screenshotJPEG: Data?

    public init(
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil,
        focusedText: String? = nil,
        selectedText: String? = nil,
        windowText: String? = nil,
        windowTextWasTruncated: Bool = false,
        focusIsInTextField: Bool = false,
        screenshotJPEG: Data? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.focusedText = focusedText
        self.selectedText = selectedText
        self.windowText = windowText
        self.windowTextWasTruncated = windowTextWasTruncated
        self.focusIsInTextField = focusIsInTextField
        self.screenshotJPEG = screenshotJPEG
    }
}

/// Which parts of the captured context the user allowed to be sent.
public struct ContextOptions: Equatable, Sendable {
    public var includeApp: Bool
    public var includeFocusedText: Bool
    public var includeSelection: Bool
    public var includeWindowText: Bool
    public var includeWindow: Bool

    public init(
        includeApp: Bool = true,
        includeFocusedText: Bool = true,
        includeSelection: Bool = true,
        includeWindowText: Bool = true,
        includeWindow: Bool = true
    ) {
        self.includeApp = includeApp
        self.includeFocusedText = includeFocusedText
        self.includeSelection = includeSelection
        self.includeWindowText = includeWindowText
        self.includeWindow = includeWindow
    }
}
