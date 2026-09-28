# Agent Instructions

- All repository text must be en-us, including Swift comments, UI strings, commit messages, and documentation.
- All user-facing strings must be localized through `Bundle.app` (`Text("…", bundle: .app)` or `String(localized: "…", bundle: .app)`; see `Sources/ContextBar/Resources.swift`) and added to `Sources/ContextBar/Localizable.xcstrings` with a pt-BR translation.
- Context Bar is a menu-bar AppKit app (macOS 14+) whose prompt panel and settings are SwiftUI views coordinated by `AppDelegate` in `Sources/ContextBar/ContextBarApp.swift`.
- Pure, testable logic (prompt building, provider request encoding, SSE parsing) lives in the `ContextBarCore` library target. Keep AppKit, Accessibility, and ScreenCaptureKit code out of it.
- Nothing is captured outside the hotkey: screen context is read only when the user presses the shortcut and is discarded when the panel closes. Do not add background capture.
- API keys live in the macOS Keychain (one item per provider). Non-secret settings live in `UserDefaults` under the keys in `Settings.swift`; preserve those keys when changing settings behavior.
- Run `swift build` and `swift test` from the repository root for verification.
- For manual testing, run `scripts/bundle.sh` to produce `dist/ContextBar.app`. Accessibility and Screen Recording permissions are tied to the code signature, so sign with a stable identity (`CODESIGN_IDENTITY`) or macOS revokes them on every rebuild.
- Do not commit credentials, `.build/`, or `dist/`.
