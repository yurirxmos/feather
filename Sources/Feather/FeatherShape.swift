import AppKit
import SwiftUI

/// The white feather from the app icon on a 24x24 grid, a filled outline shared by the prompt
/// field, the provider list, and the menu-bar icon. Traced from `Assets/feather-logo.png`.
struct FeatherShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 20.873, y: 1.139))
        path.addCurve(to: CGPoint(x: 18.177, y: 2.476), control1: CGPoint(x: 20.592, y: 1.561), control2: CGPoint(x: 19.355, y: 2.174))
        path.addCurve(to: CGPoint(x: 15.828, y: 2.888), control1: CGPoint(x: 17.595, y: 2.621), control2: CGPoint(x: 16.996, y: 2.729))
        path.addCurve(to: CGPoint(x: 13.68, y: 3.255), control1: CGPoint(x: 14.557, y: 3.065), control2: CGPoint(x: 14.294, y: 3.11))
        path.addCurve(to: CGPoint(x: 9.412, y: 5.615), control1: CGPoint(x: 12.035, y: 3.643), control2: CGPoint(x: 10.583, y: 4.447))
        path.addCurve(to: CGPoint(x: 8.089, y: 7.461), control1: CGPoint(x: 8.736, y: 6.294), control2: CGPoint(x: 8.182, y: 7.063))
        path.addCurve(to: CGPoint(x: 7.711, y: 7.894), control1: CGPoint(x: 8.071, y: 7.531), control2: CGPoint(x: 7.946, y: 7.676))
        path.addCurve(to: CGPoint(x: 4.447, y: 13.299), control1: CGPoint(x: 6.041, y: 9.471), control2: CGPoint(x: 4.828, y: 11.473))
        path.addCurve(to: CGPoint(x: 4.343, y: 16.157), control1: CGPoint(x: 4.277, y: 14.113), control2: CGPoint(x: 4.236, y: 15.226))
        path.addCurve(to: CGPoint(x: 4.42, y: 17.481), control1: CGPoint(x: 4.374, y: 16.424), control2: CGPoint(x: 4.409, y: 17.02))
        path.addCurve(to: CGPoint(x: 4.471, y: 18.302), control1: CGPoint(x: 4.43, y: 17.966), control2: CGPoint(x: 4.451, y: 18.312))
        path.addCurve(to: CGPoint(x: 4.742, y: 17.807), control1: CGPoint(x: 4.489, y: 18.292), control2: CGPoint(x: 4.61, y: 18.066))
        path.addCurve(to: CGPoint(x: 13.174, y: 8.431), control1: CGPoint(x: 6.176, y: 14.938), control2: CGPoint(x: 10.06, y: 10.625))
        path.addCurve(to: CGPoint(x: 16.733, y: 6.592), control1: CGPoint(x: 14.321, y: 7.628), control2: CGPoint(x: 16.161, y: 6.675))
        path.addCurve(to: CGPoint(x: 16.4, y: 6.855), control1: CGPoint(x: 16.871, y: 6.574), control2: CGPoint(x: 16.84, y: 6.599))
        path.addCurve(to: CGPoint(x: 8.626, y: 14.148), control1: CGPoint(x: 13.847, y: 8.352), control2: CGPoint(x: 11.775, y: 10.295))
        path.addCurve(to: CGPoint(x: 5.556, y: 18.077), control1: CGPoint(x: 7.974, y: 14.945), control2: CGPoint(x: 6.273, y: 17.124))
        path.addCurve(to: CGPoint(x: 5.192, y: 18.548), control1: CGPoint(x: 5.518, y: 18.125), control2: CGPoint(x: 5.355, y: 18.337))
        path.addCurve(to: CGPoint(x: 2.809, y: 21.957), control1: CGPoint(x: 4.077, y: 19.975), control2: CGPoint(x: 3.089, y: 21.389))
        path.addCurve(to: CGPoint(x: 3.761, y: 22.674), control1: CGPoint(x: 2.372, y: 22.837), control2: CGPoint(x: 3.11, y: 23.391))
        path.addCurve(to: CGPoint(x: 4.329, y: 21.68), control1: CGPoint(x: 3.886, y: 22.539), control2: CGPoint(x: 4.031, y: 22.286))
        path.addCurve(to: CGPoint(x: 6.845, y: 18.51), control1: CGPoint(x: 5.133, y: 20.069), control2: CGPoint(x: 5.837, y: 19.182))
        path.addCurve(to: CGPoint(x: 10.51, y: 17.301), control1: CGPoint(x: 7.829, y: 17.855), control2: CGPoint(x: 8.681, y: 17.574))
        path.addCurve(to: CGPoint(x: 13.209, y: 16.552), control1: CGPoint(x: 11.972, y: 17.083), control2: CGPoint(x: 12.388, y: 16.968))
        path.addCurve(to: CGPoint(x: 15.277, y: 14.917), control1: CGPoint(x: 13.964, y: 16.171), control2: CGPoint(x: 14.817, y: 15.496))
        path.addCurve(to: CGPoint(x: 15.243, y: 14.74), control1: CGPoint(x: 15.451, y: 14.699), control2: CGPoint(x: 15.447, y: 14.678))
        path.addCurve(to: CGPoint(x: 14.103, y: 14.983), control1: CGPoint(x: 15.025, y: 14.803), control2: CGPoint(x: 14.12, y: 14.997))
        path.addCurve(to: CGPoint(x: 14.415, y: 14.796), control1: CGPoint(x: 14.096, y: 14.976), control2: CGPoint(x: 14.238, y: 14.893))
        path.addCurve(to: CGPoint(x: 17.242, y: 12.059), control1: CGPoint(x: 15.797, y: 14.048), control2: CGPoint(x: 16.646, y: 13.226))
        path.addCurve(to: CGPoint(x: 17.568, y: 10.929), control1: CGPoint(x: 17.498, y: 11.563), control2: CGPoint(x: 17.661, y: 10.988))
        path.addCurve(to: CGPoint(x: 17.162, y: 11.065), control1: CGPoint(x: 17.554, y: 10.923), control2: CGPoint(x: 17.37, y: 10.981))
        path.addCurve(to: CGPoint(x: 14.72, y: 11.55), control1: CGPoint(x: 16.442, y: 11.352), control2: CGPoint(x: 15.936, y: 11.453))
        path.addCurve(to: CGPoint(x: 13.424, y: 11.726), control1: CGPoint(x: 14.082, y: 11.602), control2: CGPoint(x: 13.632, y: 11.66))
        path.addLine(to: CGPoint(x: 13.351, y: 11.751))
        path.addLine(to: CGPoint(x: 13.42, y: 11.671))
        path.addCurve(to: CGPoint(x: 16.504, y: 10.233), control1: CGPoint(x: 13.777, y: 11.266), control2: CGPoint(x: 15, y: 10.697))
        path.addCurve(to: CGPoint(x: 19.054, y: 8.764), control1: CGPoint(x: 17.647, y: 9.88), control2: CGPoint(x: 18.33, y: 9.485))
        path.addCurve(to: CGPoint(x: 21.216, y: 4.62), control1: CGPoint(x: 20.142, y: 7.673), control2: CGPoint(x: 20.914, y: 6.193))
        path.addCurve(to: CGPoint(x: 21.049, y: 1.028), control1: CGPoint(x: 21.434, y: 3.47), control2: CGPoint(x: 21.33, y: 1.204))
        path.addCurve(to: CGPoint(x: 20.873, y: 1.139), control1: CGPoint(x: 20.984, y: 0.986), control2: CGPoint(x: 20.97, y: 0.993))
        path.closeSubpath()
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
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
