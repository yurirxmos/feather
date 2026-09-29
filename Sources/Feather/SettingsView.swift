import FeatherCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case connection
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: String(localized: "Connection", bundle: .app)
        case .general: String(localized: "General", bundle: .app)
        case .permissions: String(localized: "Permissions", bundle: .app)
        }
    }

    var symbol: String {
        switch self {
        case .connection: "network"
        case .general: "gearshape"
        case .permissions: "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .connection: .blue
        case .general: .gray
        case .permissions: .indigo
        }
    }
}

struct SettingsView: View {
    private let credentialStore: any CredentialStore
    @State private var selectedSection: SettingsSection? = .general
    @StateObject private var permissions = PermissionMonitor()
    @AppStorage(SettingsKey.connection) private var connection: ConnectionKind = .openCodeGo
    @AppStorage(SettingsKey.model) private var model = OpenCodeGoProvider.defaultModel
    @AppStorage(SettingsKey.hotkey) private var hotkey: HotkeyPreset = .optionSpace
    @AppStorage(SettingsKey.includeScreenshot) private var includeScreenshot = true
    @State private var storedKey = ""
    @State private var newKey = ""
    @State private var isEditingKey = false
    @State private var isLoggingIn = false
    @State private var authError: String?
    @State private var chatGPTConnected = false
    @State private var openCodeModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsFailed = false

    init(credentialStore: any CredentialStore = KeychainCredentialStore.shared) {
        self.credentialStore = credentialStore
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .navigationTitle((selectedSection ?? .general).title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            loadCredentials(for: connection)
            if !isConnected {
                selectedSection = .connection
            } else if !permissions.allGranted {
                selectedSection = .permissions
            }
        }
        .onChange(of: connection) { _, value in
            model = FeatherCore.Settings.model(afterChangingTo: value, preserving: model)
            authError = nil
            loadCredentials(for: value)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selectedSection) { section in
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

    private func needsAttention(_ section: SettingsSection) -> Bool {
        switch section {
        case .connection: !isConnected
        case .general: false
        case .permissions: !permissions.allGranted
        }
    }

    private var isConnected: Bool {
        switch connection {
        case .openCodeGo: !storedKey.isEmpty
        case .chatGPT: chatGPTConnected
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .general {
        case .connection: connectionView
        case .general: generalView
        case .permissions: permissionsView
        }
    }

    // MARK: - Connection

    private var connectionView: some View {
        Form {
            Section {
                Picker(String(localized: "Provider", bundle: .app), selection: $connection) {
                    Text("OpenCode Go", bundle: .app).tag(ConnectionKind.openCodeGo)
                    Text("ChatGPT", bundle: .app).tag(ConnectionKind.chatGPT)
                }
                .pickerStyle(.segmented)

                if connection == .openCodeGo {
                    keyEditor
                } else {
                    chatGPTEditor
                }
            } header: {
                Text("Account", bundle: .app)
            } footer: {
                Text("Credentials are stored in the macOS Keychain.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                modelEditor
            } header: {
                Text("Model", bundle: .app)
            } footer: {
                if connection == .openCodeGo, storedKey.isEmpty {
                    Text("Add an API key to load the available models.", bundle: .app)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if connection == .openCodeGo, modelsFailed {
                    Label {
                        Text("Couldn't load the models. Check your key and connection.", bundle: .app)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var keyEditor: some View {
        if storedKey.isEmpty || isEditingKey {
            LabeledContent(String(localized: "API key", bundle: .app)) {
                HStack(spacing: 8) {
                    SecureField(String(localized: "API key", bundle: .app), text: $newKey, prompt: Text("Paste your key", bundle: .app))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)
                        .onSubmit(saveKey)
                    if !storedKey.isEmpty {
                        Button(String(localized: "Cancel", bundle: .app)) {
                            newKey = ""
                            isEditingKey = false
                        }
                    }
                    Button(String(localized: "Save", bundle: .app), action: saveKey)
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedNewKey.isEmpty)
                }
            }
        } else {
            LabeledContent(String(localized: "API key", bundle: .app)) {
                HStack(spacing: 10) {
                    Text(APIKey.masked(storedKey))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.disabled)
                    Button(String(localized: "Replace…", bundle: .app)) {
                        newKey = ""
                        isEditingKey = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chatGPTEditor: some View {
        LabeledContent(String(localized: "Account", bundle: .app)) {
            if chatGPTConnected {
                HStack(spacing: 10) {
                    StatusBadge(text: String(localized: "Connected", bundle: .app), color: .green)
                    Button(String(localized: "Disconnect", bundle: .app)) {
                        credentialStore.deleteChatGPTCredentials()
                        chatGPTConnected = false
                    }
                }
            } else {
                HStack(spacing: 10) {
                    if isLoggingIn {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(isLoggingIn ? String(localized: "Signing in…", bundle: .app) : String(localized: "Sign in with ChatGPT", bundle: .app), action: signInWithChatGPT)
                        .disabled(isLoggingIn)
                }
            }
        }
        if !chatGPTConnected, !isLoggingIn, authError == nil {
            Text("Sign-in continues in your browser.", bundle: .app)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let authError {
            Label(authError, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var modelEditor: some View {
        switch connection {
        case .chatGPT:
            Picker(String(localized: "Model", bundle: .app), selection: $model) {
                ForEach(ChatGPTModelCatalog.models) { model in
                    Text(model.name).tag(model.id)
                }
            }
        case .openCodeGo:
            HStack(spacing: 8) {
                Picker(String(localized: "Model", bundle: .app), selection: $model) {
                    ForEach(OpenCodeGoModelCatalog.sortedUniqueModels(openCodeModels, including: model), id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .disabled(storedKey.isEmpty || isLoadingModels)
                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: loadOpenCodeModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(storedKey.isEmpty)
                    .help(String(localized: "Refresh", bundle: .app))
                    .accessibilityLabel(String(localized: "Refresh", bundle: .app))
                }
            }
        }
    }

    // MARK: - General

    private var generalView: some View {
        Form {
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
                Label {
                    Text("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.", bundle: .app)
                } icon: {
                    Image(systemName: "hand.raised.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private var trimmedNewKey: String {
        newKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveKey() {
        let trimmed = trimmedNewKey
        guard !trimmed.isEmpty, credentialStore.setAPIKey(trimmed) else { return }
        storedKey = trimmed
        newKey = ""
        isEditingKey = false
        openCodeModels = []
        loadOpenCodeModels()
    }

    private func signInWithChatGPT() {
        isLoggingIn = true
        authError = nil
        Task {
            do {
                _ = try await ChatGPTAuth.login(store: credentialStore)
                chatGPTConnected = true
            } catch {
                authError = error.localizedDescription
            }
            isLoggingIn = false
        }
    }

    private func loadCredentials(for connection: ConnectionKind) {
        switch connection {
        case .openCodeGo:
            storedKey = credentialStore.apiKey() ?? ""
            if openCodeModels.isEmpty { loadOpenCodeModels() }
        case .chatGPT:
            chatGPTConnected = credentialStore.chatGPTCredentials() != nil
        }
    }

    private func loadOpenCodeModels() {
        guard !isLoadingModels, !storedKey.isEmpty else { return }
        let apiKey = storedKey
        isLoadingModels = true
        modelsFailed = false
        Task {
            defer { isLoadingModels = false }
            guard let fetched = try? await OpenCodeGoModelCatalog.fetchModels(apiKey: apiKey) else {
                modelsFailed = true
                return
            }
            openCodeModels = fetched
        }
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

private struct StatusBadge: View {
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
