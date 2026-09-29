import AppKit
import FeatherCore

/// A floating panel that takes keyboard focus without activating Feather, so the target
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
        animationBehavior = .utilityWindow
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

    /// Positions the panel near the target window, falling back to the upper third of the screen.
    func position(on screen: NSScreen, windowFrame: CGRect? = nil) {
        let visible = screen.visibleFrame
        let origin = PanelPlacement.origin(
            panelSize: frame.size,
            windowFrame: windowFrame,
            visibleFrame: visible
        )
        anchorTop = nil
        setFrameOrigin(origin)
        anchorTop = frame.maxY
    }
}
