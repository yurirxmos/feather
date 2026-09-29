import AppKit
import SwiftUI

/// The Feather "feather" glyph on a 24x24 grid, shared by the prompt field and the menu-bar icon.
struct FeatherShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12.67, y: 19))
        path.addCurve(to: CGPoint(x: 14.086, y: 18.412), control1: CGPoint(x: 13.201, y: 19), control2: CGPoint(x: 13.71, y: 18.789))
        path.addLine(to: CGPoint(x: 20.24, y: 12.24))
        path.addCurve(to: CGPoint(x: 20.24, y: 3.75), control1: CGPoint(x: 22.583, y: 9.897), control2: CGPoint(x: 22.583, y: 6.097))
        path.addCurve(to: CGPoint(x: 11.75, y: 3.75), control1: CGPoint(x: 17.897, y: 1.407), control2: CGPoint(x: 14.097, y: 1.407))
        path.addLine(to: CGPoint(x: 5.586, y: 9.914))
        path.addCurve(to: CGPoint(x: 5, y: 11.328), control1: CGPoint(x: 5.211, y: 10.289), control2: CGPoint(x: 5, y: 10.798))
        path.addLine(to: CGPoint(x: 5, y: 18))
        path.addCurve(to: CGPoint(x: 6, y: 19), control1: CGPoint(x: 5, y: 18.552), control2: CGPoint(x: 5.448, y: 19))
        path.closeSubpath()

        path.move(to: CGPoint(x: 16, y: 8))
        path.addLine(to: CGPoint(x: 2, y: 22))

        path.move(to: CGPoint(x: 17.5, y: 15))
        path.addLine(to: CGPoint(x: 9, y: 15))

        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

extension NSImage {
    /// A template rendering of the feather for `NSStatusItem`, so macOS tints it for light, dark
    /// and highlighted menu bars.
    static func featherMenuBarIcon(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let path = FeatherShape().path(in: rect).cgPath
            context.addPath(path)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(size / 24 * 2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
