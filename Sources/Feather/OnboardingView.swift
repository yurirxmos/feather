import FeatherCore
import SwiftUI

/// The first-run welcome guide: welcome, permissions, connect a provider, and try the shortcut. It
/// reuses the permission rows and the Connection and Feather Plus panes, so nothing about signing in
/// is duplicated. Mirrored in the desktop app's `settings.ts`, which has no permissions step.
struct OnboardingView: View {
    let credentialStore: any CredentialStore
    @ObservedObject var permissions: PermissionMonitor
    let finish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, permissions, connect, tryItOut
    }

    @State private var step: Step = .welcome
    @State private var providersSetUp: Set<ConnectionKind> = []
    @State private var isShowingPlus = false
    @State private var sample = ""
    @AppStorage(SettingsKey.connection) private var connection: ConnectionKind = .openCodeGo
    @AppStorage(SettingsKey.hotkey) private var hotkey: HotkeyPreset = .optionSpace

    private var isConnected: Bool { providersSetUp.contains(connection) }
    private var isLast: Bool { step == Step.allCases.last }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear(perform: refreshProviders)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissionsStep
        case .connect: connectStep
        case .tryItOut: tryItOutStep
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            ProviderIcon(kind: .featherPlus, size: 72)
            Text("Welcome to Feather", bundle: .app)
                .font(.largeTitle.weight(.semibold))
            Text("Press a shortcut anywhere. Feather reads what is on your screen, writes a reply, and pastes it into the field you are typing in.", bundle: .app)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(32)
    }

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            header(
                title: String(localized: "Allow access", bundle: .app),
                detail: String(localized: "Feather needs both permissions to read the context around your cursor and paste replies.", bundle: .app)
            )
            Form {
                Section {
                    PermissionsView(monitor: permissions)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var connectStep: some View {
        VStack(spacing: 0) {
            if isShowingPlus {
                HStack {
                    Button {
                        isShowingPlus = false
                        refreshProviders()
                    } label: {
                        Label(String(localized: "Back", bundle: .app), systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    .pointingHandCursor()
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                PlusSettingsView(credentialStore: credentialStore)
            } else {
                header(
                    title: String(localized: "Connect a provider", bundle: .app),
                    detail: String(localized: "Choose how Feather gets its replies. You can change this later in Settings.", bundle: .app)
                )
                ConnectionSettingsView(
                    credentialStore: credentialStore,
                    openPlus: { isShowingPlus = true },
                    credentialsChanged: refreshProviders
                )
            }
        }
    }

    private var tryItOutStep: some View {
        VStack(spacing: 0) {
            header(
                title: String(localized: "Try it out", bundle: .app),
                detail: String(localized: "Click the box below, then press \(hotkey.symbol). Say what you want, and Feather writes it here.", bundle: .app)
            )
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $sample)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
                    .overlay(alignment: .topLeading) {
                        if sample.isEmpty {
                            Text("Your reply appears here", bundle: .app)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 140)
                Text("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
    }

    private func header(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step == .welcome {
                Color.clear.frame(width: 80, height: 1)
            } else {
                Button(String(localized: "Back", bundle: .app), action: goBack)
                    .pointingHandCursor()
                    .frame(width: 80, alignment: .leading)
            }
            Spacer()
            Text(footerStatus)
                .foregroundStyle(.secondary)
            Spacer()
            Button(nextTitle, action: goNext)
                .keyboardShortcut(.defaultAction)
                .disabled(step == .connect && !isConnected)
                .pointingHandCursor()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var footerStatus: String {
        if step == .connect && !isConnected {
            return String(localized: "Connect a provider to continue.", bundle: .app)
        }
        return String(localized: "Step \(step.rawValue + 1) of \(Step.allCases.count)", bundle: .app)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: String(localized: "Get Started", bundle: .app)
        case .tryItOut: String(localized: "Finish", bundle: .app)
        default: String(localized: "Continue", bundle: .app)
        }
    }

    private func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    private func goNext() {
        if isLast {
            finish()
        } else if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func refreshProviders() {
        providersSetUp = Settings.providersSetUp(in: credentialStore, plusAvailable: FeatherPlus.isProviderEnabled())
    }
}
