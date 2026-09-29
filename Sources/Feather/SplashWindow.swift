import AppKit
import SwiftUI

/// A brief launch screen: the feather above a loading spinner, then the window fades out.
@MainActor
final class SplashWindow {
    private static let duration: TimeInterval = 2.4
    private static let size = NSSize(width: 240, height: 240)

    private var window: NSPanel?

    func show(completion: @escaping @MainActor () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: SplashView())

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.midY - Self.size.height / 2))
        }

        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animates ? 0 : 1
        panel.orderFrontRegardless()
        window = panel
        if animates {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = animates ? 0.35 : 0
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
            self?.window = nil
            completion()
        }
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            FeatherShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 52, height: 52)
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
        }
        .frame(width: 140, height: 140)
        .background(Color.black, in: Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Feather", bundle: .app))
    }
}
