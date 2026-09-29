# Agent Instructions

Context Bar is a macOS menu-bar app (macOS 14+, SwiftPM `swift-tools-version: 5.9`) that captures
screen context on a hotkey, streams a reply from an LLM, and pastes it into the focused field.

## Commands

- Build and test from the repository root: `swift build`, `swift test`.
- Single test: `swift test --filter SSEParserTests` (or `--filter SSEParserTests/testParsesEventAndData`).
- `scripts/bundle.sh` builds `dist/ContextBar.app`; set `CODESIGN_IDENTITY` before running it.
- Only `ContextBarCore` has unit tests. AppKit, Accessibility, and ScreenCaptureKit changes must be
  verified manually by running the bundled app.
- `swift build` prints known Swift 6 `Sendable` warnings (e.g. `NSEvent` in `PromptController`); the
  package still targets Swift 5 semantics, so don't chase them.

## Architecture

- `Sources/ContextBarCore` — pure, testable logic (prompt building, provider request encoding, SSE
  parsing). Keep AppKit, Accessibility, and ScreenCaptureKit out of it.
- `Sources/ContextBar` — the executable. `AppDelegate` (`ContextBarApp.swift`) is the entrypoint; it
  wires `PromptController`, which owns the non-activating `PromptPanel` and streams through the
  provider built from `Settings`.
- Provider base URLs include the API version: Anthropic appends `/v1/messages`, OpenAI-compatible
  appends `/chat/completions` (so its base is e.g. `http://localhost:11434/v1`). See
  `URL.endpoint(base:path:)` in `LLMProvider.swift`.
- Nothing is captured outside the hotkey: screen context is read only when the user presses the
  shortcut and is discarded when the panel closes. Do not add background capture.

## Conventions

- All repository text must be en-us, including Swift comments, UI strings, commit messages, and docs.
- Every user-facing string must go through `Bundle.app` (`Text("…", bundle: .app)` or
  `String(localized: "…", bundle: .app)`; see `Sources/ContextBar/Resources.swift`) and be added to
  `Sources/ContextBar/Localizable.xcstrings` with a pt-BR translation.
- Never call `Bundle.module` directly in the app: the executable's generated `Bundle.module` traps
  when the resource bundle is missing. Use `Bundle.app`, which resolves the bundled
  `ContextBar_ContextBar.bundle` in `Contents/Resources`.
- API keys live in the macOS Keychain (one item per provider). Non-secret settings live in
  `UserDefaults` under the keys in `Settings.swift`; preserve those keys when changing settings.
- Do not commit credentials, `.build/`, or `dist/`.
