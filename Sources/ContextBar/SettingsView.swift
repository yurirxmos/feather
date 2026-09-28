import ContextBarCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.provider) private var provider: ProviderKind = .anthropic
    @AppStorage(SettingsKey.anthropicModel) private var anthropicModel = ""
    @AppStorage(SettingsKey.anthropicBaseURL) private var anthropicBaseURL = ""
    @AppStorage(SettingsKey.openAIModel) private var openAIModel = ""
    @AppStorage(SettingsKey.openAIBaseURL) private var openAIBaseURL = ""
    @AppStorage(SettingsKey.hotkey) private var hotkey: HotkeyPreset = .optionSpace
    @AppStorage(SettingsKey.includeScreenshot) private var includeScreenshot = true
    @State private var apiKey = ""

    private var model: Binding<String> { provider == .anthropic ? $anthropicModel : $openAIModel }
    private var baseURL: Binding<String> { provider == .anthropic ? $anthropicBaseURL : $openAIBaseURL }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Provider", bundle: .app), selection: $provider) {
                    Text("Anthropic", bundle: .app).tag(ProviderKind.anthropic)
                    Text("OpenAI-compatible", bundle: .app).tag(ProviderKind.openAICompatible)
                }
                TextField(
                    String(localized: "Base URL", bundle: .app),
                    text: baseURL,
                    prompt: Text(provider.defaultBaseURL)
                )
                TextField(
                    String(localized: "Model", bundle: .app),
                    text: model,
                    prompt: Text(provider.defaultModel.isEmpty ? String(localized: "Model ID", bundle: .app) : provider.defaultModel)
                )
                SecureField(
                    String(localized: "API key", bundle: .app),
                    text: $apiKey,
                    prompt: provider.requiresAPIKey ? nil : Text("Optional for local servers", bundle: .app)
                )
            } header: {
                Text("Model", bundle: .app)
            } footer: {
                if provider == .openAICompatible {
                    Text("Works with OpenAI, OpenRouter, Groq, Ollama (http://localhost:11434/v1), LM Studio, and any server that speaks /chat/completions. Pick a model that accepts images to use the window screenshot.", bundle: .app)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your key is stored in the macOS Keychain.", bundle: .app)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onAppear { apiKey = Keychain.apiKey(for: provider) ?? "" }
        .onChange(of: provider) { apiKey = Keychain.apiKey(for: provider) ?? "" }
        .onChange(of: apiKey) {
            if apiKey != (Keychain.apiKey(for: provider) ?? "") {
                Keychain.setAPIKey(apiKey, for: provider)
            }
        }
    }
}
