# Feather for Windows and Linux

This directory contains Feather's Windows and Linux app, built with
[Tauri](https://v2.tauri.app). The macOS app remains in the repository root and
is not built from here. Both apps send the same prompt and requests, and the
desktop app follows the macOS app's behavior:

- A global shortcut (Ctrl+Shift+Space by default) opens a floating panel at the
  bottom of the screen, centered on the window you were using.
- On demand only, Feather reads the app name, window title, focused field,
  selection, and window text, and can attach a screenshot of the window.
- Replies stream from OpenCode Go, ChatGPT, or Feather Plus. Follow-up
  instructions refine the reply, and Enter pastes it into the field you were
  typing in. The clipboard is restored afterward.
- Settings, a tray menu, pt-BR translations, and signed automatic updates.

## Platform support

| Capability | Windows | Linux X11 | Linux Wayland |
| --- | --- | --- | --- |
| Shortcut, panel, generation | Yes | Yes | Yes |
| Focused field and window text | UI Automation | AT-SPI | No |
| Window screenshot | `PrintWindow` | X11 `GetImage` | No |
| Paste into the focused field | `SendInput` | XTest | No, copies instead |

Wayland does not let one app read or type into another, so on Wayland Feather
generates the reply and copies it. Settings > System shows what works in the
current session.

## Run

Install Node.js 20 or later, Rust 1.88 or later, and the platform prerequisites
required by [Tauri](https://v2.tauri.app/start/prerequisites/). On Linux, also
install `libdbus-1-dev` for the Secret Service credential store. Then run:

```sh
npm install
npm run tauri dev
```

On macOS, the app runs with stub platform adapters: it captures and pastes
nothing, which is enough to work on the UI and providers.

## Check

```sh
npm run build
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml
```

## Release

`.github/workflows/release-desktop.yml` builds the Windows installer, the
AppImage, and the .deb for every `v*` tag and attaches them, with the
`latest-desktop.json` update feed, to the release the macOS workflow publishes.
Updates are signed with the `TAURI_SIGNING_PRIVATE_KEY` secret and verified with
the public key in `src-tauri/tauri.conf.json`. The Windows installer is not
code-signed yet, so SmartScreen warns on first install.
