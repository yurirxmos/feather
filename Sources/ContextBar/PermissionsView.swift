import AppKit
import Combine
import SwiftUI

struct PermissionsView: View {
    @State private var accessibilityGranted = AccessibilityContext.isTrusted
    @State private var screenRecordingGranted = WindowCapture.hasPermission
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        PermissionRow(
            title: String(localized: "Accessibility", bundle: .app),
            detail: String(localized: "Reads the focused field and pastes the result.", bundle: .app),
            isGranted: accessibilityGranted
        ) {
            AccessibilityContext.requestTrust()
            openPrivacyPane("Privacy_Accessibility")
        }
        PermissionRow(
            title: String(localized: "Screen Recording", bundle: .app),
            detail: String(localized: "Captures the active window when you press the shortcut. Takes effect after relaunching Context Bar.", bundle: .app),
            isGranted: screenRecordingGranted
        ) {
            WindowCapture.requestPermission()
            openPrivacyPane("Privacy_ScreenCapture")
        }
        .onReceive(timer) { _ in
            accessibilityGranted = AccessibilityContext.isTrusted
            screenRecordingGranted = WindowCapture.hasPermission
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
    let isGranted: Bool
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isGranted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isGranted {
                Button(String(localized: "Grant…", bundle: .app), action: grant)
            }
        }
    }
}
