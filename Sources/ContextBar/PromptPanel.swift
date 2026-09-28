import AppKit

/// A floating panel that takes keyboard focus without activating Context Bar, so the target
/// app stays frontmost with its caret where the user left it.
final class PromptPanel: NSPanel {
    /// The panel grows downward as the result streams in, keeping its top edge fixed.
    var anchorTop: CGFloat?

    static func make() -> PromptPanel {
        let panel = PromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.configure()
        return panel
    }

    private func configure() {
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if let anchorTop { rect.origin.y = anchorTop - rect.height }
        super.setFrame(rect, display: flag)
    }

    /// Centers the panel horizontally on the screen under the mouse, in the upper third.
    func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let top = visible.maxY - visible.height * 0.2
        anchorTop = top
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: top - frame.height))
    }
}
