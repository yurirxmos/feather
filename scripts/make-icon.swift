// Renders Assets/AppIcon.icns: the feather-web favicon (a white feather stroke on #0a84ff) laid out
// on the macOS app icon grid. Run from the repository root: `swift scripts/make-icon.swift`.
import AppKit

let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

/// The glyph from `Sources/Feather/FeatherShape.swift`, on its 24x24 grid with y pointing down.
func featherPath() -> CGPath {
    let path = CGMutablePath()
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
    return path
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let scale = CGFloat(pixels) / canvas
    context.scaleBy(x: scale, y: scale)

    let tilePath = CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Drop shadow under the tile, as macOS icons have.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor(srgbRed: 10 / 255, green: 132 / 255, blue: 1, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    // A slight top-to-bottom gradient around the favicon's #0a84ff.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colors = [
        NSColor(srgbRed: 52 / 255, green: 154 / 255, blue: 1, alpha: 1).cgColor,
        NSColor(srgbRed: 10 / 255, green: 112 / 255, blue: 240 / 255, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    context.restoreGState()

    // The feather, centered on the tile; the glyph grid is flipped to match CoreGraphics.
    let glyphSize = tile.width * 0.62
    let unit = glyphSize / 24
    var transform = CGAffineTransform(translationX: tile.midX - glyphSize / 2, y: tile.midY + glyphSize / 2)
        .scaledBy(x: unit, y: -unit)
    context.addPath(featherPath().copy(using: &transform)!)
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(unit * 2)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

try FileManager.default.createDirectory(atPath: "Assets", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Assets/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
