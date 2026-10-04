import AppKit
import FeatherCore
import SwiftUI

@main
enum FeatherMain {
    @MainActor private static let delegate = AppDelegate()

    @MainActor static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let credentialStore: any CredentialStore = KeychainCredentialStore.shared
    private lazy var promptController = PromptController(credentialStore: credentialStore)
    private var settingsWindow: NSWindow?
    private var registeredHotkey: HotkeyPreset?
    private var hotkeyMenuItem: NSMenuItem?
    private let updater = AppUpdater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.onPress = { [weak self] in self?.openPrompt() }
        registerHotkey()
        setUpStatusItem()
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil
        )
        // The welcome guide runs once on every install, including ones that already have credentials.
        let hasCredentials = FeatherCore.Settings.current().hasCredentials(using: credentialStore)
        let defaults = UserDefaults.standard
        let onboardingDone = FeatherCore.Settings.onboardingCompleted(
            stored: defaults.object(forKey: SettingsKey.onboardingCompleted) as? Bool
        )
        defaults.set(onboardingDone, forKey: SettingsKey.onboardingCompleted)
        if !onboardingDone || !AccessibilityContext.isTrusted || !WindowCapture.hasPermission || !hasCredentials {
            showSettings()
        }
        updater.checkForUpdatesInBackground()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage.featherMenuBarIcon()
        icon.accessibilityDescription = String(localized: "Feather", bundle: .app)
        item.button?.image = icon
        let menu = NSMenu()
        let open = NSMenuItem(title: "", action: #selector(openPrompt), keyEquivalent: "")
        open.target = self
        open.image = NSImage.featherMenuBarIcon(size: 16)
        hotkeyMenuItem = open
        menu.addItem(open)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Settings…", bundle: .app), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = menuSymbol("gearshape")
        menu.addItem(settings)
        if updater.isConfigured {
            let updates = NSMenuItem(title: String(localized: "Check for Updates…", bundle: .app), action: #selector(AppUpdater.checkForUpdates(_:)), keyEquivalent: "")
            updates.target = updater
            updates.image = menuSymbol("arrow.triangle.2.circlepath")
            menu.addItem(updates)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit", bundle: .app), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = menuSymbol("power")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        updateHotkeyMenuTitle()
    }

    /// An SF Symbol for a menu item; the desktop app's tray menu draws the same glyphs.
    private func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func registerHotkey() {
        let preset = FeatherCore.Settings.current().hotkey
        guard preset != registeredHotkey else { return }
        if HotkeyManager.shared.register(preset) {
            registeredHotkey = preset
        } else {
            registeredHotkey = nil
            NSLog("Feather: could not register hotkey \(preset.symbol); another app may own it.")
        }
        updateHotkeyMenuTitle()
    }

    private func updateHotkeyMenuTitle() {
        let symbol = FeatherCore.Settings.current().hotkey.symbol
        hotkeyMenuItem?.title = String(localized: "Open Feather (\(symbol))", bundle: .app)
    }

    @objc private func defaultsChanged() {
        registerHotkey()
    }

    @objc private func openPrompt() {
        guard FeatherCore.Settings.current().hasCredentials(using: credentialStore) else {
            showSettings()
            return
        }
        promptController.toggle()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "Feather Settings", bundle: .app)
            window.minSize = NSSize(width: 680, height: 480)
            window.toolbarStyle = .unified
            let hosting = NSHostingController(rootView: SettingsView(credentialStore: credentialStore))
            hosting.sizingOptions = [.minSize]
            hosting.sceneBridgingOptions = [.title, .toolbars]
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 720, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
