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
    @State private var storedClaudeKey = ""
    @State private var storedOpenAIKey = ""
    /// The provider whose API key field is open.
    @State private var enteringKeyFor: ConnectionKind?
    @State private var newKey = ""
    @State private var busy: ConnectionKind?
    @State private var signInTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var openCodeModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsFailed = false
    @State private var claudeModels = ClaudeModelCatalog.fallbackModels
    @State private var isLoadingClaudeModels = false
    @State private var claudeModelsFailed = false
    @State private var openAIModels = OpenAIModelCatalog.fallbackModels
    @State private var isLoadingOpenAIModels = false
    @State private var openAIModelsFailed = false
    @State private var didLoadOpenAIModels = false
    @State private var didLoadClaudeModels = false
    @AppStorage(offerFeatherPlusKey) private var offerFeatherPlus = false
    @State private var isAskingToUsePlus = false

    private var providers: [ConnectionKind] {
        Settings.providerOrder.filter { $0 != .featherPlus || FeatherPlus.isProviderEnabled() }
    }

    var body: some View {
        Form {
            if providers.contains(.featherPlus) {
                Section {
                    plusCard
                        .listRowBackground(Color.accentColor.opacity(0.07))
                }
            }

            // Ready providers first; the ones still to set up below them, dimmed.
            let free: [ConnectionKind] = [.openAI, .claude, .openCodeGo]
            let ready = free.filter(setUp.contains)
            let pending = free.filter { !setUp.contains($0) }
            Section {
                ForEach(ready + pending, id: \.self, content: providerRow)
            } header: {
                Text("Free plan", bundle: .app)
            } footer: {
                Text("Use your own OpenAI, Claude, or OpenCode Go API key. Keys are stored in the macOS Keychain.", bundle: .app)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .sectionFooter()
            }

            // Feather Plus picks its own model, so there is nothing to choose.
            if setUp.contains(connection), connection != .featherPlus {
                Section {
                    modelEditor
                } header: {
                    Text("Model", bundle: .app)
                } footer: {
                    modelFooter
                        .sectionFooter()
                }
            }

            if let errorMessage {
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

    /// Feather Plus, set apart above the free providers.
    private var plusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ProviderIcon(kind: .featherPlus, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Feather Plus", bundle: .app)
                        .font(.title3.weight(.semibold))
                    if setUp.contains(.featherPlus) {
                        detail(.featherPlus)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No API key, and it also answers questions. Paid plan.", bundle: .app)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                accessory(.featherPlus)
            }
            if !setUp.contains(.featherPlus) {
                HStack(spacing: 18) {
                    perk(String(localized: "Answers your questions", bundle: .app))
                    perk(String(localized: "No API key to manage", bundle: .app))
                    perk(String(localized: "$4 a month or $36 a year", bundle: .app))
                }
                .font(.callout)
                .padding(.leading, 54)
            }
        }
        .padding(.vertical, 8)
    }

    private func perk(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .fontWeight(.semibold)
        }
    }

    private func providerRow(_ kind: ConnectionKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // A provider still to set up reads quieter than the ready ones; its button does not.
                HStack(spacing: 12) {
                    ProviderIcon(kind: kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        detail(kind)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(setUp.contains(kind) ? 1 : 0.55)
                Spacer(minLength: 12)
                accessory(kind)
            }
            if enteringKeyFor == kind {
                keyField(for: kind)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func detail(_ kind: ConnectionKind) -> some View {
        switch (kind, setUp.contains(kind)) {
        case (.featherPlus, false):
            Text("No API key, and it also answers questions. Paid plan.", bundle: .app)
        case (.openAI, false):
            Text("Paste an OpenAI API key from the Platform.", bundle: .app)
        case (.claude, false):
            Text("Paste an Anthropic API key from the Console.", bundle: .app)
        case (.openCodeGo, false):
            Text("Paste an OpenCode Go API key. Free.", bundle: .app)
        case (.featherPlus, true):
            switch plusAccount?.plan {
            case .monthly: Text("Monthly plan", bundle: .app)
            case .yearly: Text("Yearly plan", bundle: .app)
            case nil: plusAccount == nil ? Text("Signed in", bundle: .app) : Text("No plan yet", bundle: .app)
            }
        case (.openAI, true):
            Text(APIKey.masked(storedOpenAIKey))
                .font(.system(.callout, design: .monospaced))
        case (.claude, true):
            Text(APIKey.masked(storedClaudeKey))
                .font(.system(.callout, design: .monospaced))
        case (.openCodeGo, true):
            Text(APIKey.masked(storedKey))
                .font(.system(.callout, design: .monospaced))
        }
    }

    /// The row's actions, as icons with tooltips: a check when in use, a circle to use it, a plus to
    /// set it up, a card to choose a Feather Plus plan, and the ⋯ menu for the rest.
    @ViewBuilder
    private func accessory(_ kind: ConnectionKind) -> some View {
        if busy == kind {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                // Only Feather Plus signs in; the other providers take a key.
                iconButton("xmark.circle", String(localized: "Cancel", bundle: .app)) { signInTask?.cancel() }
            }
        } else if !setUp.contains(kind) {
            if enteringKeyFor != kind {
                iconButton(kind == .featherPlus ? "plus.circle.fill" : "plus.circle", String(localized: "Set Up…", bundle: .app)) { beginSetUp(kind) }
                    .foregroundStyle(kind == .featherPlus ? Color.accentColor : Color.primary)
                    .disabled(busy != nil)
            }
        } else {
            HStack(spacing: 10) {
                if kind == .featherPlus, let plusAccount, plusAccount.plan == nil {
                    iconButton("creditcard", String(localized: "Choose a plan…", bundle: .app), action: openBilling)
                        .foregroundStyle(Color.accentColor)
                } else if connection == kind {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.green)
                        .help(String(localized: "In use", bundle: .app))
                        .accessibilityLabel(Text("In use", bundle: .app))
                } else {
                    iconButton("circle", String(localized: "Use", bundle: .app)) { use(kind) }
                        .foregroundStyle(.secondary)
                }
                actions(kind)
            }
        }
    }

    private func iconButton(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        // A tooltip names the action; the trailing "…" belongs on buttons that open something.
        .help(label.hasSuffix("…") ? String(label.dropLast()) : label)
        .accessibilityLabel(label)
        .pointingHandCursor()
    }

    private func actions(_ kind: ConnectionKind) -> some View {
        Menu {
            switch kind {
            case .openCodeGo, .openAI, .claude:
                Button(String(localized: "Replace…", bundle: .app)) {
                    newKey = ""
                    enteringKeyFor = kind
                }
                Button(String(localized: "Remove Key", bundle: .app), role: .destructive) { removeKey(kind) }
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
        .pointingHandCursor()
    }

    private func keyField(for kind: ConnectionKind) -> some View {
        HStack(spacing: 8) {
            SecureField(String(localized: "API key", bundle: .app), text: $newKey, prompt: Text("Paste your key", bundle: .app))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveKey(kind) }
            Button(String(localized: "Cancel", bundle: .app)) {
                newKey = ""
                enteringKeyFor = nil
            }
            .pointingHandCursor()
            Button(String(localized: "Save", bundle: .app)) { saveKey(kind) }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedNewKey.isEmpty)
                .pointingHandCursor()
        }
        .padding(.leading, 40)
    }

    // MARK: - Model

    @ViewBuilder
    private var modelEditor: some View {
        switch connection {
        case .featherPlus:
            EmptyView()
        case .openAI:
            HStack(spacing: 8) {
                Picker(String(localized: "Model", bundle: .app), selection: $model) {
                    ForEach(openAIModels.contains(model) ? openAIModels : openAIModels + [model], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .disabled(isLoadingOpenAIModels)
                .pointingHandCursor()
                if isLoadingOpenAIModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: loadOpenAIModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Refresh", bundle: .app))
                    .accessibilityLabel(String(localized: "Refresh", bundle: .app))
                    .pointingHandCursor()
                }
            }
        case .claude:
            HStack(spacing: 8) {
                Picker(String(localized: "Model", bundle: .app), selection: $model) {
                    ForEach(claudeModels.contains(model) ? claudeModels : claudeModels + [model], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .disabled(isLoadingClaudeModels)
                .pointingHandCursor()
                if isLoadingClaudeModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: loadClaudeModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Refresh", bundle: .app))
                    .accessibilityLabel(String(localized: "Refresh", bundle: .app))
                    .pointingHandCursor()
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
                .pointingHandCursor()
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
                    .pointingHandCursor()
                }
            }
        }
    }

    @ViewBuilder
    private var modelFooter: some View {
        if connection == .openAI, openAIModelsFailed {
            Label {
                Text("Couldn't load the models. Check your key and connection.", bundle: .app)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.red)
        } else if connection == .claude, claudeModelsFailed {
            Label {
                Text("Couldn't load the models. Check your key and connection.", bundle: .app)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.red)
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

    // MARK: - Actions

    private var trimmedNewKey: String {
        newKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reload() {
        setUp = Settings.providersSetUp(in: credentialStore, plusAvailable: FeatherPlus.isProviderEnabled())
        storedKey = credentialStore.apiKey() ?? ""
        storedClaudeKey = credentialStore.claudeAPIKey() ?? ""
        storedOpenAIKey = credentialStore.openAIAPIKey() ?? ""
        if setUp.contains(.openCodeGo), openCodeModels.isEmpty { loadOpenCodeModels() }
        if setUp.contains(.openAI), !didLoadOpenAIModels { loadOpenAIModels() }
        if setUp.contains(.claude), !didLoadClaudeModels { loadClaudeModels() }
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
        if kind == .openAI { loadOpenAIModels() }
        if kind == .claude { loadClaudeModels() }
    }

    private func beginSetUp(_ kind: ConnectionKind) {
        errorMessage = nil
        switch kind {
        case .openCodeGo, .openAI, .claude:
            newKey = ""
            enteringKeyFor = kind
        case .featherPlus:
            signInToPlus()
        }
    }

    private func saveKey(_ kind: ConnectionKind) {
        let trimmed = trimmedNewKey
        guard !trimmed.isEmpty else { return }
        switch kind {
        case .claude:
            guard credentialStore.setClaudeAPIKey(trimmed) else { return }
            claudeModels = ClaudeModelCatalog.fallbackModels
            didLoadClaudeModels = false
        case .openAI:
            guard credentialStore.setOpenAIAPIKey(trimmed) else { return }
            openAIModels = OpenAIModelCatalog.fallbackModels
            didLoadOpenAIModels = false
        default:
            guard credentialStore.setAPIKey(trimmed) else { return }
            openCodeModels = []
        }
        newKey = ""
        enteringKeyFor = nil
        credentialsDidChange(preferring: kind)
        if kind == .openCodeGo { loadOpenCodeModels() }
    }

    private func removeKey(_ kind: ConnectionKind) {
        if kind == .claude {
            credentialStore.deleteClaudeAPIKey()
            claudeModels = ClaudeModelCatalog.fallbackModels
            didLoadClaudeModels = false
        } else if kind == .openAI {
            credentialStore.deleteOpenAIAPIKey()
            openAIModels = OpenAIModelCatalog.fallbackModels
            didLoadOpenAIModels = false
        } else {
            credentialStore.deleteAPIKey()
            openCodeModels = []
        }
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
        Task { await PlusAuth.openWebsite(path: FeatherPlus.pricingPath, store: credentialStore) }
    }

    /// Asks OpenAI which chat models the key can use, and moves a selection it lacks to the default
    /// or the newest one. The built-in list stays if that fails.
    private func loadOpenAIModels() {
        guard !isLoadingOpenAIModels, !storedOpenAIKey.isEmpty else { return }
        let apiKey = storedOpenAIKey
        isLoadingOpenAIModels = true
        openAIModelsFailed = false
        Task {
            defer { isLoadingOpenAIModels = false }
            guard let fetched = try? await OpenAIModelCatalog.fetchModels(apiKey: apiKey), !fetched.isEmpty else {
                openAIModelsFailed = true
                return
            }
            openAIModels = fetched
            didLoadOpenAIModels = true
            if connection == .openAI, let available = OpenAIModelCatalog.model(for: fetched, current: model) {
                model = available
            }
        }
    }

    /// Asks Anthropic which models the key can use, and moves a selection it lacks to the first one
    /// listed. The built-in list stays if that fails.
    private func loadClaudeModels() {
        guard !isLoadingClaudeModels, !storedClaudeKey.isEmpty else { return }
        let apiKey = storedClaudeKey
        isLoadingClaudeModels = true
        claudeModelsFailed = false
        Task {
            defer { isLoadingClaudeModels = false }
            guard let fetched = try? await ClaudeModelCatalog.fetchModels(apiKey: apiKey), !fetched.isEmpty else {
                claudeModelsFailed = true
                return
            }
            claudeModels = fetched
            didLoadClaudeModels = true
            if connection == .claude, !fetched.contains(model), let first = fetched.first { model = first }
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
        case .openAI: String(localized: "OpenAI", bundle: .app)
        case .claude: String(localized: "Claude", bundle: .app)
        case .openCodeGo: String(localized: "OpenCode Go", bundle: .app)
        }
    }
}

/// Feather Plus uses Feather's own mark, the app icon's white feather on blue; Claude its mark in
/// white on its orange, since the orange mark is hard to see on white; OpenAI and OpenCode Go
/// their original black logos on white. The logos come from `ProviderLogos` in the app's resource
/// bundle (shared with the desktop app).
struct ProviderIcon: View {
    let kind: ConnectionKind
    var size: CGFloat = 28

    private static let logos: [ConnectionKind: NSImage] = {
        var logos: [ConnectionKind: NSImage] = [:]
        for (kind, file) in [(ConnectionKind.openAI, "openai_logo.svg"), (.claude, "claude_logo.png"), (.openCodeGo, "opencode_logo.png")] {
            if let url = Bundle.app.url(forResource: file, withExtension: nil, subdirectory: "ProviderLogos"),
               let image = NSImage(contentsOf: url) {
                logos[kind] = image
            }
        }
        return logos
    }()

    /// The app icon's gradient around #0a84ff (`scripts/make-icon.swift`).
    static let featherBlue = LinearGradient(
        colors: [Color(red: 52 / 255, green: 154 / 255, blue: 1), Color(red: 10 / 255, green: 112 / 255, blue: 240 / 255)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Claude's brand orange, #D97757.
    static let claudeOrange = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)

    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: size / 4, style: .continuous) }

    var body: some View {
        Group {
            if kind == .featherPlus {
                FeatherShape()
                    .fill(.white)
                    .frame(width: size * 0.57, height: size * 0.57)
                    .frame(width: size, height: size)
                    .background(Self.featherBlue, in: tile)
            } else if kind == .claude, let logo = Self.logos[kind] {
                Image(nsImage: logo)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(size * 0.2)
                    .frame(width: size, height: size)
                    .background(Self.claudeOrange, in: tile)
            } else if let logo = Self.logos[kind] {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * (kind == .openCodeGo ? 0.1 : 0.18))
                    .frame(width: size, height: size)
                    .background(.white, in: tile)
                    .overlay(tile.strokeBorder(.black.opacity(0.1)))
            } else {
                Image(systemName: "key.fill")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: size, height: size)
                    .background(.white, in: tile)
                    .overlay(tile.strokeBorder(.black.opacity(0.1)))
            }
        }
        .accessibilityHidden(true)
    }
}
