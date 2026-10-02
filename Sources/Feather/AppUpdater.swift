import AppKit
import Sparkle

/// Owns Sparkle's standard updater. Release builds carry `SUFeedURL` in their Info.plist (see
/// `scripts/bundle.sh`); local builds without it never start the updater.
@MainActor
final class AppUpdater: NSObject {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        if let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feedURL.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        }
    }

    var isConfigured: Bool {
        controller != nil
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    /// Silent check on launch, in addition to Sparkle's scheduled checks; it only shows UI when an
    /// update is found.
    func checkForUpdatesInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    /// Feather is a menu-bar accessory app, so an update found by a background check would
    /// otherwise open its alert behind other windows. Activating first brings it to the front.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
