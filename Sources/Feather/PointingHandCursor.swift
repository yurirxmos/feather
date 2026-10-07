import AppKit
import SwiftUI

extension View {
    /// Shows the pointing-hand cursor over a clickable control, as the Windows and Linux app does,
    /// and the arrow again when the pointer leaves it. Disabled controls keep the arrow.
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

private struct PointingHandCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        // `set` rather than `push`/`pop`: a control that disappears under the pointer, such as a
        // Cancel button once signing in ends, never gets to pop, and the stack would stay unbalanced.
        content.onContinuousHover { phase in
            switch phase {
            case .active where isEnabled:
                NSCursor.pointingHand.set()
            case .active, .ended:
                NSCursor.arrow.set()
            }
        }
    }
}
