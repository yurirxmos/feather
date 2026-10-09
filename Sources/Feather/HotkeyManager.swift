import Carbon.HIToolbox
import FeatherCore
import Combine
import Foundation

/// Carbon's `RegisterEventHotKey` needs no Accessibility permission and swallows the keystroke.
extension HotkeyPreset {
    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .controlOptionSpace, .shiftCommandSpace: UInt32(kVK_Space)
        case .controlOptionReturn: UInt32(kVK_Return)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .shiftCommandSpace: UInt32(shiftKey | cmdKey)
        case .controlOptionReturn: UInt32(controlKey | optionKey)
        }
    }

    var symbol: String {
        switch self {
        case .optionSpace: String(localized: "⌥ Space", bundle: .app)
        case .controlOptionSpace: String(localized: "⌃ ⌥ Space", bundle: .app)
        case .shiftCommandSpace: String(localized: "⇧ ⌘ Space", bundle: .app)
        case .controlOptionReturn: String(localized: "⌃ ⌥ ↩", bundle: .app)
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    var onPress: (() -> Void)?
    /// False when another app already owns the chosen shortcut; Settings then says so.
    @Published private(set) var isRegistered = true
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    @discardableResult
    func register(_ preset: HotkeyPreset) -> Bool {
        installHandlerIfNeeded()
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4354_4241), id: 1) // 'CTBA'
        let status = RegisterEventHotKey(preset.keyCode, preset.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
        return isRegistered
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { manager.onPress?() } }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
