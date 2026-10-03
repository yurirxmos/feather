import AppKit
import FeatherCore
import SwiftUI

/// The Connection pane. Providers that are set up come first, with the one in use marked; the rest
/// wait below with a Set Up button. Only a provider that is set up can be used, the first one set up
/// is used right away, and removing the one in use falls back to another (`Settings.connection`).
/// Mirrored in the desktop app's `settings.ts`.
struct ConnectionSettingsView: View {
    let credentialStore: any CredentialStore
    /// Opens the Feather Plus pane, for the account and usage.
    let openPlus: () -> Void
    /// Tells the window that credentials changed, so the sidebar can update.
    let credentialsChanged: () -> Void

    @AppStorage(SettingsKey.connection) private var connection: ConnectionKind = .openCodeGo
    @AppStorage(SettingsKey.model) private var model = OpenCodeGoProvider.defaultModel
    @State private var setUp: Set<ConnectionKind> = []
    @State private var storedKey = ""
    @State private var plusAccount: PlusAccount?
    @State private var isEnteringKey = false
    @State private var newKey = ""
    @State private var busy: ConnectionKind?
    @State private var signInTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var openCodeModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsFailed = false
    @AppStorage(offerFeatherPlusKey) private var offerFeatherPlus = false
    @State private var isAskingToUsePlus = false

    private var providers: [ConnectionKind] {
        Settings.providerOrder.filter { $0 != .featherPlus || FeatherPlus.isProviderEnabled() }
    }

    var body: some View {
        let ready = providers.filter(setUp.contains)
        let rest = providers.filter { !setUp.contains($0) }
        Form {
            if !ready.isEmpty {
                Section {
                    ForEach(ready, id: \.self, content: providerRow)
                } header: {
                    Text("Your providers", bundle: .app)
                } footer: {
                    Text("Credentials are stored in the macOS Keychain.", bundle: .app)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // Feather Plus picks its own model, so there is nothing to choose.
            if setUp.contains(connection), connection != .featherPlus {
                Section {
                    modelEditor
                } header: {
                    Text("Model", bundle: .app)
                } footer: {
                    modelFooter
                }
            }

            if !rest.isEmpty {
                Section {
                    ForEach(rest, id: \.self, content: providerRow)
                } header: {
                    if ready.isEmpty {
                        Text("Choose how Feather writes", bundle: .app)
                    } else {
                        Text("Add a provider", bundle: .app)
                    }
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    } else if ready.isEmpty {
                        Text("Set up one to start. You can add the others later.", bundle: .app)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        // Plans change in the browser (checkout, the portal), so refresh on returning to the app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
        .onDisappear {
            // Leaving the pane abandons a pending browser sign-in and frees its port.
            signInTask?.cancel()
        }
        .modifier(UseFeatherPlusAlert(isPresented: $isAskingToUsePlus, current: connection) { use(.featherPlus) })
    }

    // MARK: - Rows

    private func providerRow(_ kind: ConnectionKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProviderIcon(kind: kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    detail(kind)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                accessory(kind)
            }
            if kind == .openCodeGo, isEnteringKey {
                keyField
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func detail(_ kind: ConnectionKind) -> some View {
        switch (kind, setUp.contains(kind)) {
        case (.featherPlus, false):
            Text("No API key, and it also answers questions. Paid plan.", bundle: .app)
        case (.chatGPT, false):
            Text("Sign in with your ChatGPT account. Free.", bundle: .app)
        case (.openCodeGo, false):
            Text("Paste an OpenCode Go API key. Free.", bundle: .app)
        case (.featherPlus, true):
            switch plusAccount?.plan {
            case .starter: Text("Starter plan", bundle: .app)
            case .max: Text("Max plan", bundle: .app)
            case nil: plusAccount == nil ? Text("Signed in", bundle: .app) : Text("No plan yet", bundle: .app)
            }
        case (.chatGPT, true):
            Text("Signed in", bundle: .app)
        case (.openCodeGo, true):
            Text(APIKey.masked(storedKey))
                .font(.system(.callout, design: .monospaced))
        }
    }

    @ViewBuilder
    private func accessory(_ kind: ConnectionKind) -> some View {
        if busy == kind {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                if kind == .featherPlus {
                    Button(String(localized: "Cancel", bundle: .app)) { signInTask?.cancel() }
                } else {
                    Text("Signing in…", bundle: .app)
                        .foregroundStyle(.secondary)
                }
            }
        } else if !setUp.contains(kind) {
            if !(kind == .openCodeGo && isEnteringKey) {
                Button(String(localized: "Set Up…", bundle: .app)) { beginSetUp(kind) }
                    .disabled(busy != nil)
            }
        } else {
            HStack(spacing: 8) {
                if kind == .featherPlus, let plusAccount, plusAccount.plan == nil {
                    Button(String(localized: "Choose a plan…", bundle: .app), action: openBilling)
                } else if connection == kind {
                    Label {
                        Text("In use", bundle: .app)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.green)
                } else {
                    Button(String(localized: "Use", bundle: .app)) { use(kind) }
                }
                actions(kind)
            }
        }
    }

    private func actions(_ kind: ConnectionKind) -> some View {
        Menu {
            switch kind {
            case .openCodeGo:
                Button(String(localized: "Replace…", bundle: .app)) {
                    newKey = ""
                    isEnteringKey = true
                }
                Button(String(localized: "Remove Key", bundle: .app), role: .destructive, action: removeKey)
            case .chatGPT:
                Button(String(localized: "Disconnect", bundle: .app), role: .destructive, action: disconnectChatGPT)
            case .featherPlus:
                Button(String(localized: "Manage…", bundle: .app), action: openPlus)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "More", bundle: .app))
        .accessibilityLabel(String(localized: "More", bundle: .app))
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            SecureField(String(localized: "API key", bundle: .app), text: $newKey, prompt: Text("Paste your key", bundle: .app))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveKey)
            Button(String(localized: "Cancel", bundle: .app)) {
                newKey = ""
                isEnteringKey = false
            }
            Button(String(localized: "Save", bundle: .app), action: saveKey)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedNewKey.isEmpty)
        }
        .padding(.leading, 40)
    }

    // MARK: - Model

    @ViewBuilder
    private var modelEditor: some View {
        switch connection {
        case .featherPlus:
            EmptyView()
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
                .disabled(isLoadingModels)
                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: loadOpenCodeModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Refresh", bundle: .app))
                    .accessibilityLabel(String(localized: "Refresh", bundle: .app))
                }
            }
        }
    }

    @ViewBuilder
    private var modelFooter: some View {
        if connection == .openCodeGo, modelsFailed {
            Label {
                Text("Couldn't load the models. Check your key and connection.", bundle: .app)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private var trimmedNewKey: String {
        newKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reload() {
        setUp = Settings.providersSetUp(in: credentialStore, plusAvailable: FeatherPlus.isProviderEnabled())
        storedKey = credentialStore.apiKey() ?? ""
        if setUp.contains(.openCodeGo), openCodeModels.isEmpty { loadOpenCodeModels() }
        loadPlusAccount()
    }

    /// Re-reads the credentials, then keeps the provider in use or moves to one that is set up.
    private func credentialsDidChange(preferring preferred: ConnectionKind? = nil) {
        reload()
        let next = Settings.connection(current: connection, setUp: setUp, preferring: preferred)
        if next != connection { use(next) }
        credentialsChanged()
    }

    private func use(_ kind: ConnectionKind) {
        model = Settings.model(afterChangingTo: kind, preserving: model)
        connection = kind
        if kind == .openCodeGo, openCodeModels.isEmpty { loadOpenCodeModels() }
    }

    private func beginSetUp(_ kind: ConnectionKind) {
        errorMessage = nil
        switch kind {
        case .openCodeGo:
            newKey = ""
            isEnteringKey = true
        case .chatGPT:
            signInWithChatGPT()
        case .featherPlus:
            signInToPlus()
        }
    }

    private func saveKey() {
        let trimmed = trimmedNewKey
        guard !trimmed.isEmpty, credentialStore.setAPIKey(trimmed) else { return }
        newKey = ""
        isEnteringKey = false
        openCodeModels = []
        credentialsDidChange(preferring: .openCodeGo)
        loadOpenCodeModels()
    }

    private func removeKey() {
        credentialStore.deleteAPIKey()
        openCodeModels = []
        credentialsDidChange()
    }

    private func signInWithChatGPT() {
        busy = .chatGPT
        Task {
            do {
                _ = try await ChatGPTAuth.login(store: credentialStore)
                credentialsDidChange(preferring: .chatGPT)
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = nil
        }
    }

    private func disconnectChatGPT() {
        credentialStore.deleteChatGPTCredentials()
        credentialsDidChange()
    }

    private func signInToPlus() {
        busy = .featherPlus
        signInTask = Task {
            do {
                _ = try await PlusAuth.signIn(store: credentialStore)
                offerFeatherPlus = true
                credentialsDidChange(preferring: .featherPlus)
            } catch is CancellationError {
                // The user cancelled or left the pane.
            } catch {
                errorMessage = PlusAuthError.message(for: error)
            }
            busy = nil
            signInTask = nil
        }
    }

    private func loadPlusAccount() {
        guard let token = credentialStore.plusToken(), setUp.contains(.featherPlus) else {
            plusAccount = nil
            return
        }
        Task {
            do {
                let account = try await PlusAuth.account(token: token)
                plusAccount = account
                offerFeatherPlusIfReady(account)
            } catch PlusAuthError.unauthorized {
                credentialStore.deletePlusToken()
                plusAccount = nil
                credentialsDidChange()
            } catch {
                // The row still works offline; the Feather Plus pane shows the error.
            }
        }
    }

    /// Once a newly signed-in account has a plan, asks to reply with it, unless it already does.
    private func offerFeatherPlusIfReady(_ account: PlusAccount) {
        guard offerFeatherPlus, account.plan != nil else { return }
        offerFeatherPlus = false
        if connection != .featherPlus { isAskingToUsePlus = true }
    }

    private func openBilling() {
        guard let url = try? FeatherPlus.accountURL(base: FeatherPlus.baseURL()) else { return }
        NSWorkspace.shared.open(url)
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

/// Set when a Feather Plus account signs in, until its plan is known: then Settings asks once
/// whether to reply with Feather Plus. Shared by the Connection and Feather Plus panes.
let offerFeatherPlusKey = "offerFeatherPlus"

/// Asks whether to switch replies to Feather Plus, naming the provider in use now.
struct UseFeatherPlusAlert: ViewModifier {
    @Binding var isPresented: Bool
    let current: ConnectionKind
    let accept: () -> Void

    func body(content: Content) -> some View {
        content.alert(Text("Use Feather Plus for replies?", bundle: .app), isPresented: $isPresented) {
            Button(String(localized: "Use Feather Plus", bundle: .app), action: accept)
                .keyboardShortcut(.defaultAction)
            Button(String(localized: "Keep \(current.title)", bundle: .app), role: .cancel) {}
        } message: {
            Text("Feather is using \(current.title) now. You can switch again in Settings > Connection anytime.", bundle: .app)
        }
    }
}

extension ConnectionKind {
    var title: String {
        switch self {
        case .featherPlus: String(localized: "Feather Plus", bundle: .app)
        case .chatGPT: String(localized: "ChatGPT", bundle: .app)
        case .openCodeGo: String(localized: "OpenCode Go", bundle: .app)
        }
    }
}

/// Feather Plus uses Feather's own mark, the app icon's white feather on blue; ChatGPT and OpenCode
/// Go use their original black logos on white, from `ProviderLogos` in the app's resource bundle
/// (shared with the desktop app).
private struct ProviderIcon: View {
    let kind: ConnectionKind

    private static let logos: [ConnectionKind: NSImage] = {
        var logos: [ConnectionKind: NSImage] = [:]
        for (kind, file) in [(ConnectionKind.chatGPT, "openai_logo.svg"), (.openCodeGo, "opencode_logo.png")] {
            if let url = Bundle.app.url(forResource: file, withExtension: nil, subdirectory: "ProviderLogos"),
               let image = NSImage(contentsOf: url) {
                logos[kind] = image
            }
        }
        return logos
    }()

    /// The app icon's gradient around #0a84ff (`scripts/make-icon.swift`).
    private static let featherBlue = LinearGradient(
        colors: [Color(red: 52 / 255, green: 154 / 255, blue: 1), Color(red: 10 / 255, green: 112 / 255, blue: 240 / 255)],
        startPoint: .top,
        endPoint: .bottom
    )

    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }

    var body: some View {
        Group {
            if kind == .featherPlus {
                FeatherShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .background(Self.featherBlue, in: tile)
            } else if let logo = Self.logos[kind] {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(kind == .openCodeGo ? 3 : 5)
                    .frame(width: 28, height: 28)
                    .background(.white, in: tile)
                    .overlay(tile.strokeBorder(.black.opacity(0.1)))
            } else {
                Image(systemName: kind == .chatGPT ? "bubble.left.and.bubble.right.fill" : "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(.white, in: tile)
                    .overlay(tile.strokeBorder(.black.opacity(0.1)))
            }
        }
        .accessibilityHidden(true)
    }
}
