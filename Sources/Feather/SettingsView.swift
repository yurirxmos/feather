import FeatherCore
import ServiceManagement
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case connection
    case plus
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: String(localized: "Connection", bundle: .app)
        case .general: String(localized: "General", bundle: .app)
        case .plus: String(localized: "Feather Plus", bundle: .app)
        case .permissions: String(localized: "Permissions", bundle: .app)
        }
    }

    var symbol: String {
        switch self {
        case .connection: "network"
        case .general: "gearshape"
        case .plus: "sparkles"
        case .permissions: "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .connection: .blue
        case .general: .gray
        case .plus: .orange
        case .permissions: .indigo
        }
    }
}

struct SettingsView: View {
    private let credentialStore: any CredentialStore
    @State private var selectedSection: SettingsSection? = .general
    @StateObject private var permissions = PermissionMonitor()
    @AppStorage(SettingsKey.connection) private var connection: ConnectionKind = .openCodeGo
    @AppStorage(SettingsKey.hotkey) private var hotkey: HotkeyPreset = .optionSpace
    @AppStorage(SettingsKey.includeScreenshot) private var includeScreenshot = true
    @AppStorage(SettingsKey.customInstructions) private var customInstructions = ""
    // The app delegate sets this at launch, so an unset value never reaches here.
    @AppStorage(SettingsKey.onboardingCompleted) private var onboardingCompleted = true
    @State private var providersSetUp: Set<ConnectionKind> = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(credentialStore: any CredentialStore = KeychainCredentialStore.shared) {
        self.credentialStore = credentialStore
    }

    var body: some View {
        if onboardingCompleted {
            settingsBody
        } else {
            OnboardingView(credentialStore: credentialStore, permissions: permissions) {
                selectedSection = .general
                onboardingCompleted = true
            }
        }
    }

    private var settingsBody: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .navigationTitle((selectedSection ?? .general).title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            refreshProviders()
            if !isConnected {
                selectedSection = .connection
            } else if !permissions.allGranted {
                selectedSection = .permissions
            }
        }
        .onChange(of: selectedSection) { _, _ in
            // Feather Plus sign-in happens in its own pane; refresh when coming back.
            refreshProviders()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(visibleSections, selection: $selectedSection) { section in
            HStack(spacing: 8) {
                SectionIcon(symbol: section.symbol, tint: section.tint)
                Text(section.title)
                Spacer(minLength: 0)
                if needsAttention(section) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(String(localized: "Needs attention", bundle: .app))
                }
            }
            .padding(.vertical, 2)
            .tag(section)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(String(localized: "Quit Feather", bundle: .app), systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
    }

    private var visibleSections: [SettingsSection] {
        SettingsSection.allCases.filter { $0 != .plus || FeatherPlus.isEnabled() }
    }

    private func needsAttention(_ section: SettingsSection) -> Bool {
        switch section {
        case .connection: !isConnected
        case .general, .plus: false
        case .permissions: !permissions.allGranted
        }
    }

    /// Whether the provider in use is set up.
    private var isConnected: Bool {
        providersSetUp.contains(connection)
    }

    private func refreshProviders() {
        providersSetUp = Settings.providersSetUp(in: credentialStore, plusAvailable: FeatherPlus.isProviderEnabled())
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .general {
        case .connection:
            ConnectionSettingsView(
                credentialStore: credentialStore,
                openPlus: { selectedSection = .plus },
                credentialsChanged: refreshProviders
            )
        case .general: generalView
        case .plus: PlusSettingsView(credentialStore: credentialStore)
        case .permissions: permissionsView
        }
    }

    // MARK: - General

    /// Reads and writes the login item through the system instead of `UserDefaults`, so the toggle
    /// stays right when the user removes Feather from System Settings > Login Items.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Feather could not change its login item: \(error.localizedDescription)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private var generalView: some View {
        Form {
            Section {
                Toggle(isOn: launchAtLoginBinding) {
                    Text("Open Feather at login", bundle: .app)
                    Text("Starts Feather in the background when you sign in to your computer.", bundle: .app)
                }
            } header: {
                Text("Startup", bundle: .app)
            }

            Section {
                Picker(String(localized: "Open Feather", bundle: .app), selection: $hotkey) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.symbol).tag(preset)
                    }
                }
            } header: {
                Text("Shortcut", bundle: .app)
            }

            Section {
                Toggle(isOn: $includeScreenshot) {
                    Text("Include a screenshot of the active window", bundle: .app)
                    Text("Gives the model visual context. Requires Screen Recording.", bundle: .app)
                }
            } header: {
                Text("Context", bundle: .app)
            } footer: {
                Text("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .sectionFooter()
            }

            Section {
                Button(String(localized: "Show Welcome Guide…", bundle: .app)) {
                    onboardingCompleted = false
                }
            }

            Section {
                TextEditor(text: $customInstructions)
                    .font(.body)
                    .frame(minHeight: 88)
            } header: {
                Text("Instructions", bundle: .app)
            } footer: {
                Text("Set writing preferences for every response, such as “Do not use emojis or em dashes.”", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .sectionFooter()
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: - Permissions

    private var permissionsView: some View {
        Form {
            Section {
                PermissionsView(monitor: permissions)
            } footer: {
                Text("Feather needs both permissions to read the context around your cursor and paste replies.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .sectionFooter()
            }
        }
        .formStyle(.grouped)
    }
}

private struct SectionIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Lays a Form section footer across the section's full width, aligned left. Left alone,
    /// grouped forms on macOS wrap a long footer into a narrow, centered column.
    func sectionFooter() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}
