import ContextBarCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case model
    case general
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: String(localized: "Model", bundle: .app)
        case .general: String(localized: "General", bundle: .app)
        case .permissions: String(localized: "Permissions", bundle: .app)
        }
    }

    var symbol: String {
        switch self {
        case .model: "cpu"
        case .general: "gearshape"
        case .permissions: "lock.shield"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .model
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

    var body: some View {
        HSplitView {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSection.title)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                Divider()
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 460, idealHeight: 520)
        .onAppear {
            loadCredentials(for: connection)
        }
        .onChange(of: connection) { _, value in
            if model == ConnectionKind.openCodeGo.defaultModel || model == ConnectionKind.chatGPT.defaultModel {
                model = value.defaultModel
            }
            loadCredentials(for: value)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FeatherShape()
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, height: 18)
                Text(verbatim: "Context Bar")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)

            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label(String(localized: "Quit Context Bar", bundle: .app), systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 170, idealWidth: 180, maxWidth: 210)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .model: modelView
        case .general: generalView
        case .permissions: permissionsView
        }
    }

    private var modelView: some View {
        Form {
            Section {
                Picker(String(localized: "Connection", bundle: .app), selection: $connection) {
                    Text("OpenCode Go", bundle: .app).tag(ConnectionKind.openCodeGo)
                    Text("ChatGPT", bundle: .app).tag(ConnectionKind.chatGPT)
                }
                if connection == .openCodeGo {
                    keyEditor
                } else {
                    chatGPTEditor
                }
            } header: {
                Label(String(localized: "Connection", bundle: .app), systemImage: "link")
            } footer: {
                Text("Your key is stored in the macOS Keychain.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if connection == .chatGPT {
                    Picker(String(localized: "Model", bundle: .app), selection: $model) {
                        ForEach(ChatGPTModelCatalog.models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                } else {
                    TextField(String(localized: "Model", bundle: .app), text: $model)
                }
            } header: {
                Label(String(localized: "Model", bundle: .app), systemImage: "cpu")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var generalView: some View {
        Form {
            Section {
                Picker(String(localized: "Open Context Bar", bundle: .app), selection: $hotkey) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.symbol).tag(preset)
                    }
                }
            } header: {
                Label(String(localized: "Shortcut", bundle: .app), systemImage: "command")
            }

            Section {
                Toggle(String(localized: "Include a screenshot of the active window", bundle: .app), isOn: $includeScreenshot)
            } header: {
                Label(String(localized: "Context", bundle: .app), systemImage: "macwindow")
            } footer: {
                Text("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var permissionsView: some View {
        Form {
            Section {
                PermissionsView()
            } header: {
                Label(String(localized: "Permissions", bundle: .app), systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    @ViewBuilder
    private var chatGPTEditor: some View {
        if chatGPTConnected {
            HStack {
                Label(String(localized: "Connected to ChatGPT", bundle: .app), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button(String(localized: "Disconnect", bundle: .app)) {
                    Keychain.deleteChatGPTCredentials()
                    chatGPTConnected = false
                }
            }
        } else {
            Button(isLoggingIn ? String(localized: "Signing in…", bundle: .app) : String(localized: "Sign in with ChatGPT", bundle: .app)) {
                isLoggingIn = true
                authError = nil
                Task {
                    do {
                        _ = try await ChatGPTAuth.login()
                        chatGPTConnected = true
                    } catch {
                        authError = error.localizedDescription
                    }
                    isLoggingIn = false
                }
            }
            .disabled(isLoggingIn)
            if let authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var keyEditor: some View {
        if storedKey.isEmpty || isEditingKey {
            SecureField(String(localized: "API key", bundle: .app), text: $newKey)
            HStack {
                Button(String(localized: "Save", bundle: .app)) {
                    saveKey()
                }
                .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !storedKey.isEmpty {
                    Button(String(localized: "Cancel", bundle: .app)) {
                        newKey = ""
                        isEditingKey = false
                    }
                }
            }
        } else {
            HStack {
                Text(APIKey.masked(storedKey))
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button(String(localized: "Replace key…", bundle: .app)) {
                    newKey = ""
                    isEditingKey = true
                }
            }
        }
    }

    private func saveKey() {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Keychain.setAPIKey(trimmed) else { return }
        storedKey = trimmed
        newKey = ""
        isEditingKey = false
    }

    private func loadCredentials(for connection: ConnectionKind) {
        switch connection {
        case .openCodeGo:
            storedKey = Keychain.apiKey() ?? ""
        case .chatGPT:
            chatGPTConnected = Keychain.chatGPTCredentials() != nil
        }
    }
}
