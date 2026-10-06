import AppKit
import FeatherCore
import SwiftUI

/// A short form, opened from the menu bar menu, that sends feedback to the team through
/// `feather-api`. It sends only what the user types plus the app and system versions.
struct FeedbackView: View {
    let close: () -> Void

    @State private var message = ""
    @State private var email = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    @FocusState private var messageFocused: Bool

    var body: some View {
        Group {
            if sent { thanks } else { form }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tell us what works, what doesn't, or what you'd like Feather to do.", bundle: .app)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $message)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 140)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .overlay(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("Your feedback", bundle: .app)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .focused($messageFocused)
                .accessibilityLabel(String(localized: "Your feedback", bundle: .app))

            VStack(alignment: .leading, spacing: 4) {
                TextField(String(localized: "Email (optional)", bundle: .app), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                Text("Only if you'd like a reply.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if message.utf16.count > Feedback.maxMessageLength {
                Text("Keep your message under 5,000 characters.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Sends your message and the Feather and system versions. Nothing from your screen.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(String(localized: "Cancel", bundle: .app), role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await send() }
                } label: {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send", bundle: .app)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sending || !Feedback.canSend(message))
            }
        }
        .onAppear { messageFocused = true }
    }

    private var thanks: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Thanks for your feedback!", bundle: .app)
                .font(.headline)
            Text("It goes straight to the people who build Feather.", bundle: .app)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Done", bundle: .app), action: close)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let platform = "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        let outcome: Feedback.Outcome
        do {
            var request = try Feedback.request(base: FeatherPlus.baseURL(), message: message, email: email, appVersion: version, platform: platform)
            request.timeoutInterval = 20
            let (_, response) = try await URLSession.shared.data(for: request)
            outcome = Feedback.outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            NSLog("Feather could not send feedback: \(error.localizedDescription)")
            outcome = .failed
        }
        switch outcome {
        case .sent:
            sent = true
        case .invalid:
            error = String(localized: "Check the email address, or leave it empty.", bundle: .app)
        case .rateLimited:
            error = String(localized: "You've sent a lot of feedback today. Try again tomorrow.", bundle: .app)
        case .failed:
            error = String(localized: "Couldn't send your feedback. Check your connection and try again.", bundle: .app)
        }
    }
}
