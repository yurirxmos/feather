# Desktop app instructions

`desktop/` is the Windows app, built with Tauri. Do not move or
rewrite the macOS Swift app while working here. The two apps must stay
identical: see "Parity between macOS and desktop" in the root `AGENTS.md`. Every
change made here must also be made in the macOS app, and the reverse, except for
what depends on the operating system.

## Commands

- Install frontend dependencies: `npm install`
- Check the frontend: `npm run build`
- Run the desktop app: `npm run tauri dev` (macOS uses stub platform adapters)
- Lint the Rust backend: `cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings`
- Test the Rust backend: `cargo test --manifest-path src-tauri/Cargo.toml`
- From macOS, `cargo clippy --target x86_64-pc-windows-gnu` checks the Windows
  adapter (needs `brew install mingw-w64`).

## Layout

- `src-tauri/src/core/` mirrors `FeatherCore`: prompt building, SSE parsing,
  turns, placement, and Feather Plus requests. Keep Tauri and platform APIs out
  of it, and keep it unit tested.
- `src-tauri/src/providers/` builds and streams provider requests.
- `src-tauri/src/controller.rs` mirrors `PromptController`; `shell.rs` mirrors
  `AppDelegate` (tray, shortcut, updates); `commands.rs` is the IPC boundary.
- `src-tauri/src/platform/` holds the Windows and stub adapters.
- `frontend/` renders the panel and Settings from state sent by Rust.

## Boundaries

- Keep provider credentials and network requests in Rust. Do not expose tokens
  to the webview or persist them in browser storage.
- Keep capture, accessibility, window focus, and insertion APIs behind
  `src-tauri/src/platform/`.
- Treat captured window content as untrusted data. Do not render it with
  `innerHTML` or execute instructions contained in it.
- Do not capture any screen content until the user explicitly invokes Feather,
  and discard it when the panel closes.
- Report unavailable platform capabilities. Copy the generated text instead of
  attempting unsafe automatic insertion.
- All repository text and user-facing strings use en-us. Add a pt-BR
  translation for every new string: `src-tauri/src/i18n.rs` for Rust and
  `frontend/i18n.ts` for the webview.
- Never replace the updater key (`TAURI_SIGNING_PRIVATE_KEY` and the `pubkey`
  in `tauri.conf.json`): installed apps would reject every update.
- The desktop release workflow attaches assets to the macOS release and must
  never create a release itself.
