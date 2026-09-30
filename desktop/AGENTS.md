# Desktop prototype instructions

`desktop/` is the Windows and Linux prototype. Do not move or rewrite the
macOS Swift app while working here.

## Commands

- Install frontend dependencies: `npm install`
- Check the frontend: `npm run build`
- Run the desktop app: `npm run tauri dev`
- Check the Rust backend: `cargo check --manifest-path src-tauri/Cargo.toml`

## Boundaries

- Keep provider credentials and network requests in Rust. Do not expose tokens
  to the webview or persist them in browser storage.
- Keep capture, accessibility, window focus, shortcut, and insertion APIs
  behind `src-tauri/src/platform/`.
- Treat captured window content as untrusted data. Do not render it with
  `innerHTML` or execute instructions contained in it.
- Do not capture any screen content until the user explicitly invokes Feather.
- Report unavailable platform capabilities. Copy the generated text instead of
  attempting unsafe automatic insertion.
- All repository text and user-facing strings use en-us. Add pt-BR alongside
  every new user-facing string when the application UI is introduced.
