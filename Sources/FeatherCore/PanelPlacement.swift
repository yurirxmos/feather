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

    public static func origin(
        panelSize: CGSize,
        windowFrame: CGRect?,
        visibleFrame: CGRect,
        gap: CGFloat = 10,
        inset: CGFloat = 18
    ) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        let safeMinX = visibleFrame.origin.x + inset
        let safeMaxX = visibleFrame.origin.x + visibleFrame.size.width - inset
        let safeMinY = visibleFrame.origin.y + inset
        let safeMaxY = visibleFrame.origin.y + visibleFrame.size.height - inset

        if let windowFrame {
            let windowMidX = windowFrame.origin.x + windowFrame.size.width / 2
            let windowMinY = windowFrame.origin.y
            let windowMaxY = windowFrame.origin.y + windowFrame.size.height
            x = clamped(windowMidX - panelSize.width / 2, minimum: safeMinX, maximum: safeMaxX - panelSize.width)
            let below = windowMinY - gap - panelSize.height
            let above = windowMaxY + gap
            if below >= safeMinY {
                y = min(below, safeMaxY - panelSize.height)
            } else {
                y = min(max(above, safeMinY), safeMaxY - panelSize.height)
            }
        } else {
            x = safeMinX + (safeMaxX - safeMinX) / 2 - panelSize.width / 2
            y = safeMinY + (safeMaxY - safeMinY) * 0.8 - panelSize.height
        }

        return NSPoint(x: x, y: y)
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else { return minimum }
        return min(max(value, minimum), maximum)
    }
}
