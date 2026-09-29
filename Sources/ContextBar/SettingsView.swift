import ContextBarCore
import SwiftUI

struct SettingsView: View {
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
                Text("Model", bundle: .app)
            } footer: {
                Text("Your key is stored in the macOS Keychain.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "Open Context Bar", bundle: .app), selection: $hotkey) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.symbol).tag(preset)
                    }
                }
            } header: {
                Text("Shortcut", bundle: .app)
            }

            Section {
                Toggle(String(localized: "Include a screenshot of the active window", bundle: .app), isOn: $includeScreenshot)
            } header: {
                Text("Context", bundle: .app)
            } footer: {
                Text("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.", bundle: .app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PermissionsView()
            } header: {
                Text("Permissions", bundle: .app)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
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
