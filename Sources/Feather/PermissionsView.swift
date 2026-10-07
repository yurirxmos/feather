import AppKit
import Combine
import SwiftUI

/// Polls the system permissions Feather depends on so the settings UI reflects changes made in
/// System Settings without relaunching.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var accessibilityGranted = AccessibilityContext.isTrusted
    @Published private(set) var screenRecordingGranted = WindowCapture.hasPermission
    private var timer: AnyCancellable?

    var allGranted: Bool { accessibilityGranted && screenRecordingGranted }

    init() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let accessibility = AccessibilityContext.isTrusted
        let screenRecording = WindowCapture.hasPermission
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
    }
}

struct PermissionsView: View {
    @ObservedObject var monitor: PermissionMonitor

    var body: some View {
        PermissionRow(
            title: String(localized: "Accessibility", bundle: .app),
            detail: String(localized: "Reads the focused field and pastes the result.", bundle: .app),
            symbol: "accessibility",
            isGranted: monitor.accessibilityGranted
        ) {
            AccessibilityContext.requestTrust()
            openPrivacyPane("Privacy_Accessibility")
        }
        PermissionRow(
            title: String(localized: "Screen Recording", bundle: .app),
            detail: String(localized: "Captures the active window when you press the shortcut. Takes effect after relaunching Feather.", bundle: .app),
            symbol: "rectangle.dashed.badge.record",
            isGranted: monitor.screenRecordingGranted
        ) {
            WindowCapture.requestPermission()
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let isGranted: Bool
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(isGranted ? Color.green : Color.orange, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isGranted {
                Label(String(localized: "Granted", bundle: .app), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            } else {
                Button(String(localized: "Grant…", bundle: .app), action: grant)
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, 2)
    }
}
