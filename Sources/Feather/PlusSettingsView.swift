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
        .onDisappear {
            // Leaving the pane abandons a pending browser sign-in and frees its port.
            signInTask?.cancel()
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signedOutContent: some View {
        Section {
            Text("Use Feather without your own API key. Prompts, screen context, and replies are never stored.", bundle: .app)
                .foregroundStyle(.secondary)
            PlanRow(
                name: String(localized: "Starter", bundle: .app),
                price: String(localized: "$5/month", bundle: .app),
                detail: String(localized: "Everyday replies with a fast model.", bundle: .app)
            )
            PlanRow(
                name: String(localized: "Max", bundle: .app),
                price: String(localized: "$20/month", bundle: .app),
                detail: String(localized: "Higher limits and premium models.", bundle: .app)
            )
        } header: {
            Text("Feather Plus", bundle: .app)
        }

        Section {
            LabeledContent(String(localized: "Account", bundle: .app)) {
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
            }
        } footer: {
            footer
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
            if account?.plan != nil, FeatherPlus.isProviderEnabled() {
                LabeledContent(String(localized: "Replies", bundle: .app)) {
                    if connection == .featherPlus {
                        StatusBadge(text: String(localized: "Using Feather Plus", bundle: .app), color: .green)
                    } else {
                        Button(String(localized: "Use Feather Plus", bundle: .app), action: useFeatherPlus)
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
        }

        if let account, account.plan != nil, !account.usage.isEmpty {
            Section {
                ForEach(account.usage, id: \.tier) { usage in
                    UsageRow(usage: usage)
                }
            } header: {
                Text("Usage this period", bundle: .app)
            } footer: {
                if let periodEnd = account.periodEnd {
                    Text("Resets on \(periodEnd.formatted(date: .abbreviated, time: .omitted)).", bundle: .app)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                account = try await PlusAuth.account(token: token)
            } catch PlusAuthError.unauthorized {
                credentialStore.deletePlusToken()
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

    private func signOut() {
        PlusAuth.signOut(store: credentialStore)
        token = nil
        account = nil
        errorMessage = nil
    }
}

private struct PlanRow: View {
    let name: String
    let price: String
    let detail: String

    var body: some View {
        LabeledContent {
            Text(price)
                .monospacedDigit()
        } label: {
            Text(name)
            Text(detail)
        }
    }
}

private struct UsageRow: View {
    let usage: PlusAccount.Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usage.tier.displayName)
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

private extension PlusAccount.Tier {
    var displayName: String {
        switch self {
        case .fast: String(localized: "Fast requests", bundle: .app)
        case .premium: String(localized: "Premium requests", bundle: .app)
        }
    }
}
