import AppKit
import FeatherCore
import SwiftUI

/// The Feather Plus pane: sign-in, the active plan, and this period's usage.
struct PlusSettingsView: View {
    let credentialStore: any CredentialStore
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
            loadAccount()
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

    // MARK: - Signed out

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            VStack(spacing: 8) {
                Text("Sign in to Feather Plus", bundle: .app)
                    .font(.headline)
                Text("Use your Feather Plus account.", bundle: .app)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if signInTask != nil {
                        ProgressView()
                            .controlSize(.small)
                        Button(String(localized: "Cancel", bundle: .app)) {
                            signInTask?.cancel()
                        }
                    } else {
                        Button(String(localized: "Sign in", bundle: .app), action: signIn)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } header: {
            Text("Feather Plus", bundle: .app)
        } footer: {
            footer
                .sectionFooter()
        }
    }

    // MARK: - Signed in

    @ViewBuilder
    private var signedInContent: some View {
        Section {
            LabeledContent(String(localized: "Email", bundle: .app)) {
                if let account {
                    Text(account.email)
                        .textSelection(.enabled)
                } else if isLoadingAccount {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            LabeledContent(String(localized: "Plan", bundle: .app)) {
                if let account {
                    if let plan = account.plan {
                        StatusBadge(text: plan.displayName, color: .green)
                    } else {
                        Text("No plan", bundle: .app)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button(account?.plan == nil ? String(localized: "Choose a plan…", bundle: .app) : String(localized: "Manage subscription…", bundle: .app), action: openBilling)
                    .disabled(account == nil)
                Spacer()
                Button(String(localized: "Sign out", bundle: .app), action: signOut)
            }
        } header: {
            Text("Account", bundle: .app)
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
                Text("Usage this period", bundle: .app)
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

    @ViewBuilder
    private var footer: some View {
        if let errorMessage {
            HStack(spacing: 10) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                if token != nil {
                    Button(String(localized: "Retry", bundle: .app), action: loadAccount)
                        .buttonStyle(.link)
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
                Text("Requests", bundle: .app)
                Spacer()
                Text("\(usage.used) of \(usage.limit)", bundle: .app)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(usage.used, usage.limit)), total: Double(max(usage.limit, 1)))
                .tint(usage.used >= usage.limit ? .orange : .accentColor)
        }
        .padding(.vertical, 2)
    }
}

private extension PlusAccount.Plan {
    var displayName: String {
        switch self {
        case .starter: String(localized: "Starter", bundle: .app)
        case .max: String(localized: "Max", bundle: .app)
        }
    }
}
