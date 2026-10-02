# Agent Instructions

Feather is a macOS menu-bar app (macOS 14+, SwiftPM `swift-tools-version: 5.9`) that captures
screen context on a hotkey, streams a reply from an LLM, and pastes it into the focused field.

## Commands

- Build and test from the repository root: `swift build`, `swift test`.
- Single test: `swift test --filter SSEParserTests` (or `--filter SSEParserTests/testParsesEventAndData`).
- `scripts/bundle.sh` builds `dist/Feather.app`; set `CODESIGN_IDENTITY` before running it.
- Releases come only from `v*` tags (`.github/workflows/release-macos.yml`); every published
  release reaches installed apps through Sparkle, which reads
  `releases/latest/download/appcast-<arch>.xml`. Keep publishing full releases (not
  prereleases) with both `appcast-arm64.xml` and `appcast-x86_64.xml`, or installs stop updating.
- Release builds are signed with the self-signed "Feather Release Signing" certificate
  (`RELEASE_CERTIFICATE_*` secrets) and updates with the Sparkle EdDSA key
  (`SPARKLE_PRIVATE_ED_KEY`). Never replace either: a new certificate resets users' Accessibility
  and Screen Recording grants, and a new EdDSA key makes installed apps reject every update.
  No hardened runtime: its library validation refuses Sparkle without a Team ID.
- Only `FeatherCore` has unit tests. AppKit, Accessibility, and ScreenCaptureKit changes must be
  verified manually by running the bundled app.
- `swift build` prints known Swift 6 `Sendable` warnings (e.g. `NSEvent` in `PromptController`); the
  package still targets Swift 5 semantics, so don't chase them.

## Architecture

- `Sources/FeatherCore` — pure, testable logic (prompt building, provider request encoding, SSE
  parsing). Keep AppKit, Accessibility, and ScreenCaptureKit out of it.
- `Sources/Feather` — the executable. `AppDelegate` (`FeatherApp.swift`) is the entrypoint; it
  wires `PromptController`, which owns the non-activating `PromptPanel` and streams through the
  provider built from `Settings`.
- Provider base URLs include the API version: Anthropic appends `/v1/messages`, OpenAI-compatible
  appends `/chat/completions` (so its base is e.g. `http://localhost:11434/v1`). See
  `URL.endpoint(base:path:)` in `LLMProvider.swift`.
- Nothing is captured outside the hotkey: screen context is read only when the user presses the
  shortcut and is discarded when the panel closes. Do not add background capture.
- Feather Plus is the paid, hosted option. Its backend is the private `feather-api` repository
  (a Cloudflare Worker, cloned next to this one); its README is the contract the app follows.
  Never add backend code here: this repository is public. Its web pages (landing, sign-in,
  account) live in the private `feather-web` repository (`https://feather.rxmos.dev`, cloned
  next to this one); the API redirects `/auth/authorize` and `/account` there, so the app only
  needs the API base URL.
  - `FeatherPlus.swift` (requests, account decoding) and `FeatherPlusProvider.swift` (sends the
    `fast` or `premium` tier as the model) live in `FeatherCore`; `PlusAuth.swift` (browser
    sign-in with PKCE over a 127.0.0.1 loopback redirect) and `PlusSettingsView.swift` in the app.
  - It rolls out in stages: `FeatherPlus.accountsLaunched` shows the pane (sign-in, plan, usage)
    and `providerLaunched` lets it generate replies. Release builds hide both until launch;
    testers enable them with the `plusEnabled` and `plusProviderEnabled` defaults. Debug builds
    always show the pane and talk to `wrangler dev`; `plusBaseURL` overrides the server.

## Conventions

- All repository text must be en-us, including Swift comments, UI strings, commit messages, and docs.
- Every user-facing string must go through `Bundle.app` (`Text("…", bundle: .app)` or
  `String(localized: "…", bundle: .app)`; see `Sources/Feather/Resources.swift`) and be added to
  `Sources/Feather/Localizable.xcstrings` with a pt-BR translation.
- Never call `Bundle.module` directly in the app: the executable's generated `Bundle.module` traps
  when the resource bundle is missing. Use `Bundle.app`, which resolves the bundled
  `Feather_Feather.bundle` in `Contents/Resources`.
- API keys live in the macOS Keychain (one item per provider). Non-secret settings live in
  `UserDefaults` under the keys in `Settings.swift`; preserve those keys when changing settings.
- Do not commit credentials, `.build/`, or `dist/`.
