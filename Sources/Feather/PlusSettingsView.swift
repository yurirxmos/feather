import AppKit
import FeatherCore
import SwiftUI

/// The Feather Plus pane: sign-in, the active plan, and this period's usage.
struct PlusSettingsView: View {
    let credentialStore: any CredentialStore
    /// Tells the sidebar whether this pane is the account (signed in, with a plan) or the invitation.
    @Binding var showsAccount: Bool
    @AppStorage(SettingsKey.connection) private var connection: ConnectionKind = .openCodeGo
    @AppStorage(SettingsKey.model) private var model = OpenCodeGoProvider.defaultModel
    @State private var token: String?
    @State private var account: PlusAccount?
    @State private var isLoadingAccount = false
    @State private var signInTask: Task<Void, Never>?
    @State private var errorMessage: String?
    /// Set while switching accounts, so Feather Plus is in use again once the new account signs in.
    @State private var switchingAccounts = false
    @AppStorage(offerFeatherPlusKey) private var offerFeatherPlus = false
    @State private var isAskingToUsePlus = false

    var body: some View {
        Form {
            if token == nil {
                signedOutContent
            } else {
                signedInContent
            }
        }
        .formStyle(.grouped)
        .onAppear {
            token = credentialStore.plusToken()
            showsAccount = isAccountView
            loadAccount()
        }
        .onChange(of: isAccountView) { _, value in
            showsAccount = value
        }
        // Plans change in the browser (checkout, the portal), so refresh on returning to the app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loadAccount()
        }
        .onDisappear {
            // Leaving the pane abandons a pending browser sign-in and frees its port.
            signInTask?.cancel()
        }
        .modifier(UseFeatherPlusAlert(isPresented: $isAskingToUsePlus, current: connection, accept: useFeatherPlus))
    }

    /// Signed in with a plan, or still loading it; no plan reads as an invitation to become Plus.
    private var isAccountView: Bool {
        token != nil && (account == nil || account?.plan != nil)
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            invitation {
                if signInTask != nil {
                    ProgressView()
                        .controlSize(.small)
                    Button(String(localized: "Cancel", bundle: .app)) {
                        signInTask?.cancel()
                    }
                    .pointingHandCursor()
                } else {
                    Button(String(localized: "Sign in to Feather Plus", bundle: .app), action: signIn)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .pointingHandCursor()
                }
            }
        } footer: {
            footer
                .sectionFooter()
        }
    }

    /// The Plus card from the Connection pane, with what to do next under it.
    private func invitation<Actions: View>(@ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ProviderIcon(kind: .featherPlus, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Feather Plus", bundle: .app)
                        .font(.title3.weight(.semibold))
                    Text("No API key, and it also answers questions. Paid plan.", bundle: .app)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                perk(String(localized: "Answers your questions", bundle: .app))
                perk(String(localized: "No API key to manage", bundle: .app))
                perk(String(localized: "$4 a month or $36 a year", bundle: .app))
            }
            .font(.callout)
            .padding(.leading, 54)
            HStack(spacing: 10) {
                actions()
            }
            .padding(.leading, 54)
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

    // MARK: - Signed in

    @ViewBuilder
    private var signedInContent: some View {
        // Without a plan the invitation leads, and the account sits under it.
        if let account, account.plan == nil {
            Section {
                invitation {
                    Button(String(localized: "Choose a plan…", bundle: .app), action: openBilling)
                        .buttonStyle(.borderedProminent)
                        .pointingHandCursor()
                }
            }
        }

        Section {
            profile
        } footer: {
            footer
                .sectionFooter()
        }

        if let account, account.plan != nil, !account.usage.isEmpty {
            Section {
                ForEach(account.usage, id: \.limit) { usage in
                    UsageRow(usage: usage)
                }
            } header: {
                Text("Usage this month", bundle: .app)
            } footer: {
                if let periodEnd = account.periodEnd {
                    Text("Resets on \(periodEnd.formatted(date: .abbreviated, time: .omitted)).", bundle: .app)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .sectionFooter()
                }
            }
        }
    }

    /// Who is signed in, with the plan under the address and the actions as icons, like the provider rows.
    private var profile: some View {
        HStack(spacing: 14) {
            Text(String(account?.email.first ?? " ").uppercased())
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(ProviderIcon.featherBlue, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let account {
                    Text(account.email)
                        .font(.headline)
                        .textSelection(.enabled)
                    if let plan = account.plan {
                        StatusBadge(text: plan.displayName, color: .green)
                    } else {
                        Text("No plan", bundle: .app)
                            .foregroundStyle(.secondary)
                    }
                } else if isLoadingAccount {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 12)
            if account?.plan != nil {
                iconButton("creditcard", String(localized: "Manage subscription…", bundle: .app), action: openBilling)
            }
            iconButton("rectangle.portrait.and.arrow.right", String(localized: "Sign out", bundle: .app), action: signOut)
        }
        .padding(.vertical, 6)
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

    @ViewBuilder
    private var footer: some View {
        if let errorMessage {
            HStack(spacing: 10) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                if token != nil {
                    Button(String(localized: "Retry", bundle: .app), action: loadAccount)
                        .buttonStyle(.link)
                        .pointingHandCursor()
                }
            }
            .font(.callout)
        } else if token == nil {
            Text("Sign-in continues in your browser.", bundle: .app)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func signIn() {
        errorMessage = nil
        signInTask = Task {
            do {
                token = try await PlusAuth.signIn(store: credentialStore)
                offerFeatherPlus = true
                credentialsDidChange(preferring: .featherPlus)
                loadAccount()
            } catch is CancellationError {
                // The user cancelled or left the pane.
            } catch {
                errorMessage = PlusAuthError.message(for: error)
            }
            signInTask = nil
        }
    }

    private func loadAccount() {
        guard let token, !isLoadingAccount else { return }
        isLoadingAccount = true
        errorMessage = nil
        Task {
            defer { isLoadingAccount = false }
            do {
                let loaded = try await PlusAuth.account(token: token)
                account = loaded
                // Once a newly signed-in account has a plan, ask to reply with it.
                if offerFeatherPlus, loaded.plan != nil {
                    offerFeatherPlus = false
                    if connection != .featherPlus { isAskingToUsePlus = true }
                }
            } catch PlusAuthError.unauthorized {
                credentialStore.deletePlusToken()
                credentialsDidChange()
                self.token = nil
                account = nil
                errorMessage = PlusAuthError.unauthorized.errorDescription
            } catch {
                errorMessage = PlusAuthError.message(for: error)
            }
        }
    }

    private func openBilling() {
        guard let url = try? FeatherPlus.accountURL(base: FeatherPlus.baseURL()) else { return }
        NSWorkspace.shared.open(url)
    }

    private func useFeatherPlus() {
        model = FeatherCore.Settings.model(afterChangingTo: .featherPlus, preserving: model)
        connection = .featherPlus
    }

    /// Signing in or out changes which providers are set up; the Connection pane's rule decides
    /// whether Feather Plus is now the one in use.
    private func credentialsDidChange(preferring preferred: ConnectionKind? = nil) {
        let setUp = FeatherCore.Settings.providersSetUp(in: credentialStore, plusAvailable: FeatherPlus.isProviderEnabled())
        var next = FeatherCore.Settings.connection(current: connection, setUp: setUp, preferring: preferred)
        if switchingAccounts, setUp.contains(.featherPlus) {
            next = .featherPlus
            switchingAccounts = false
        }
        guard next != connection else { return }
        model = FeatherCore.Settings.model(afterChangingTo: next, preserving: model)
        connection = next
    }

    private func signOut() {
        switchingAccounts = connection == .featherPlus
        PlusAuth.signOut(store: credentialStore)
        token = nil
        account = nil
        errorMessage = nil
        credentialsDidChange()
        // Signing out is how you switch accounts, so open the sign-in right away.
        signIn()
    }
}

private struct UsageRow: View {
    let usage: PlusAccount.Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This month's allowance", bundle: .app)
                Spacer()
                // Usage is model cost; it is shown as a share of the allowance, never as money.
                Text("\(usage.percentUsed)% used", bundle: .app)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(usage.percentUsed), total: 100)
                .tint(usage.used >= usage.limit ? .orange : .accentColor)
        }
        .padding(.vertical, 2)
    }
}

private extension PlusAccount.Plan {
    var displayName: String {
        switch self {
        case .monthly: String(localized: "Plus Monthly", bundle: .app)
        case .yearly: String(localized: "Plus Yearly", bundle: .app)
        }
    }
}
