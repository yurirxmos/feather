import Foundation

public enum PanelPlacement {
    /// Converts top-left global accessibility coordinates to AppKit's bottom-left coordinates.
    public static func appKitFrame(fromAccessibilityFrame frame: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: frame.origin.x,
                y: primaryScreenFrame.origin.y + primaryScreenFrame.size.height
                    - frame.origin.y - frame.size.height
            ),
            size: frame.size
        )
    }

    /// Anchors the panel to the bottom of the visible frame, centered on the target window when known.
    public static func origin(
        panelSize: CGSize,
        windowFrame: CGRect?,
        visibleFrame: CGRect,
        inset: CGFloat = 18
    ) -> CGPoint {
        let safeMinX = visibleFrame.origin.x + inset
        let safeMaxX = visibleFrame.origin.x + visibleFrame.size.width - inset
        let midX = windowFrame.map { $0.origin.x + $0.size.width / 2 } ?? (safeMinX + safeMaxX) / 2
        let x = clamped(midX - panelSize.width / 2, minimum: safeMinX, maximum: safeMaxX - panelSize.width)
        return CGPoint(x: x, y: visibleFrame.origin.y + inset)
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else { return minimum }
        return min(max(value, minimum), maximum)
    }
}
