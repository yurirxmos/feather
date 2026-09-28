import AppKit
import SwiftUI

@main
enum ContextBarMain {
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
    private let promptController = PromptController()
    private var settingsWindow: NSWindow?
    private var registeredHotkey: HotkeyPreset?
    private var hotkeyMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.onPress = { [weak self] in self?.promptController.toggle() }
        registerHotkey()
        setUpStatusItem()
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil
        )
        if !AccessibilityContext.isTrusted || !WindowCapture.hasPermission || !Settings.current().hasCredentials {
            showSettings()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Context Bar")
        let menu = NSMenu()
        let open = NSMenuItem(title: "", action: #selector(openPrompt), keyEquivalent: "")
        open.target = self
        hotkeyMenuItem = open
        menu.addItem(open)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Settings…", bundle: .app), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Context Bar", bundle: .app), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        updateHotkeyMenuTitle()
    }

    private func registerHotkey() {
        let preset = Settings.current().hotkey
        guard preset != registeredHotkey else { return }
        if HotkeyManager.shared.register(preset) {
            registeredHotkey = preset
        } else {
            registeredHotkey = nil
            NSLog("Context Bar: could not register hotkey \(preset.symbol); another app may own it.")
        }
        updateHotkeyMenuTitle()
    }

    private func updateHotkeyMenuTitle() {
        let symbol = Settings.current().hotkey.symbol
        hotkeyMenuItem?.title = String(localized: "Open Context Bar (\(symbol))", bundle: .app)
    }

    @objc private func defaultsChanged() {
        registerHotkey()
    }

    @objc private func openPrompt() {
        promptController.toggle()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "Context Bar Settings", bundle: .app)
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
