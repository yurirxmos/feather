import SwiftUI

/// Material's `keyboard_return` glyph on a 24x24 grid, shared with the desktop app's `returnKeyIcon`.
struct ReturnKeyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 19, y: 7))
        path.addLine(to: CGPoint(x: 19, y: 11))
        path.addLine(to: CGPoint(x: 5.83, y: 11))
        path.addLine(to: CGPoint(x: 9.41, y: 7.41))
        path.addLine(to: CGPoint(x: 8, y: 6))
        path.addLine(to: CGPoint(x: 2, y: 12))
        path.addLine(to: CGPoint(x: 8, y: 18))
        path.addLine(to: CGPoint(x: 9.41, y: 16.59))
        path.addLine(to: CGPoint(x: 5.83, y: 13))
        path.addLine(to: CGPoint(x: 21, y: 13))
        path.addLine(to: CGPoint(x: 21, y: 7))
        path.closeSubpath()
        let scale = min(rect.width, rect.height) / 24
        return path.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        )
    }
}
