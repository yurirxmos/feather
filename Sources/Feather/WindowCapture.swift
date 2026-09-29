import AppKit
import ScreenCaptureKit

/// Captures a single screenshot of the target app's front window.
enum WindowCapture {
    /// Vision models downscale anything larger, so sending more only adds latency.
    static let maxLongEdgePixels: CGFloat = 1568

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func captureJPEG(pid: pid_t, title: String?, frame: CGRect?) async -> Data? {
        guard hasPermission else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let candidates = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
                    && $0.frame.width > 50 && $0.frame.height > 50
            }
            guard let window = bestMatch(candidates, title: title, frame: frame) else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let pixelWidth = window.frame.width * scale
            let pixelHeight = window.frame.height * scale
            let factor = min(1, maxLongEdgePixels / max(pixelWidth, pixelHeight))

            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(pixelWidth * factor))
            configuration.height = max(1, Int(pixelHeight * factor))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        } catch {
            NSLog("Feather: window capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func bestMatch(_ windows: [SCWindow], title: String?, frame: CGRect?) -> SCWindow? {
        if let frame {
            let byFrame = windows.min {
                distance($0.frame, frame) < distance($1.frame, frame)
            }
            if let byFrame, distance(byFrame.frame, frame) < 40 { return byFrame }
        }
        if let title, let byTitle = windows.first(where: { $0.title == title }) {
            return byTitle
        }
        return windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
