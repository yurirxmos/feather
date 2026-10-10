import FeatherCore
import Foundation

/// Keeps Settings > Replies the same on every computer signed in to the account (`ReplySettings`).
/// Signing in takes the account's settings, or saves this computer's when the account has none.
/// Each change is saved a moment after it is made, and the account's are taken again at launch,
/// when Settings opens, and at most once a minute when the panel opens.
@MainActor
final class ReplySettingsSync {
    static let shared = ReplySettingsSync()

    private static let uploadDelay: Duration = .seconds(1.5)
    private static let panelPullInterval: TimeInterval = 60

    private let defaults: UserDefaults
    private let credentialStore: any CredentialStore
    private var lastSeen: ReplySettings
    /// Set while storing the account's settings, so that isn't taken for a change to save.
    private var isApplying = false
    private var uploadTask: Task<Void, Never>?
    private var pullTask: Task<Void, Never>?
    private var lastPull = Date.distantPast

    init(defaults: UserDefaults = .standard, credentialStore: any CredentialStore = KeychainCredentialStore.shared) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        lastSeen = .stored(in: defaults)
    }

    func start() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.defaultsChanged() }
        }
        pull()
    }

    /// Takes the account's settings. From the panel (`throttled`), at most once a minute.
    func pull(throttled: Bool = false) {
        guard pullTask == nil, credentialStore.plusToken() != nil else { return }
        if throttled, Date().timeIntervalSince(lastPull) < Self.panelPullInterval { return }
        lastPull = Date()
        pullTask = Task {
            await fetchAndMerge()
            // A pull cancelled by a new sign-in leaves the new one in place.
            if !Task.isCancelled { pullTask = nil }
        }
    }

    /// A new sign-in: the account's settings win over this computer's.
    func signedIn() {
        uploadTask?.cancel()
        defaults.set(false, forKey: SettingsKey.replySettingsChangePending)
        pullTask?.cancel()
        pullTask = nil
        pull()
    }

    /// Settings stay as they are; there is just nothing to save them to.
    func signedOut() {
        uploadTask?.cancel()
        defaults.set(false, forKey: SettingsKey.replySettingsChangePending)
    }

    private func defaultsChanged() {
        let current = ReplySettings.stored(in: defaults)
        guard current != lastSeen else { return }
        lastSeen = current
        // Changes made signed out stay on this computer; signing in brings the account's.
        guard !isApplying, credentialStore.plusToken() != nil else { return }
        defaults.set(true, forKey: SettingsKey.replySettingsChangePending)
        scheduleUpload()
    }

    /// Waits for typing to pause, so the instructions are saved once rather than per keystroke.
    private func scheduleUpload() {
        uploadTask?.cancel()
        uploadTask = Task {
            try? await Task.sleep(for: Self.uploadDelay)
            guard !Task.isCancelled else { return }
            await upload(ReplySettings.stored(in: defaults))
        }
    }

    private func fetchAndMerge() async {
        guard let token = credentialStore.plusToken(),
              var request = try? FeatherPlus.replySettingsRequest(base: FeatherPlus.baseURL(defaults), token: token)
        else { return }
        request.timeoutInterval = 15
        // Offline or failing, the settings stay as they are; the next pull tries again.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              let remote = try? FeatherPlus.decodeReplySettings(data),
              !Task.isCancelled
        else { return }
        let action = ReplySettings.syncAction(
            local: .stored(in: defaults),
            remote: remote,
            localChangePending: defaults.bool(forKey: SettingsKey.replySettingsChangePending)
        )
        switch action {
        case .none:
            break
        case .apply(let settings):
            isApplying = true
            settings.store(in: defaults)
            lastSeen = settings
            isApplying = false
        case .upload(let settings):
            await upload(settings)
        }
    }

    private func upload(_ settings: ReplySettings) async {
        guard let token = credentialStore.plusToken(),
              var request = try? FeatherPlus.saveReplySettingsRequest(base: FeatherPlus.baseURL(defaults), token: token, settings: settings)
        else { return }
        request.timeoutInterval = 15
        // A failed save stays pending, so the next pull saves it instead of replacing it.
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return }
        // A change made while this one was on its way is still pending.
        if ReplySettings.stored(in: defaults) == settings {
            defaults.set(false, forKey: SettingsKey.replySettingsChangePending)
        }
    }
}
