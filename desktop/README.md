# Feather Desktop prototype

This directory contains the Windows and Linux prototype. The macOS app remains
in the repository root and is not built from here.

The prototype validates the desktop features Feather needs before capture and
text-insertion code is added:

- A global shortcut
- A tray-resident app window with a show, hide, and quit menu
- Capability reporting for the current platform
- A small, explicit IPC boundary between the frontend and Rust
- OpenCode Go generation with an API key stored in the system credential store

It deliberately does not capture screen content. The current UI can generate
and copy text, but it cannot yet insert it into another application.

## Run

Install Node.js 20 or later, Rust, and the platform prerequisites required by
[Tauri](https://v2.tauri.app/start/prerequisites/). Then run:

```sh
npm install
npm run tauri dev
```

Press `Ctrl+Shift+Space` to show or hide the probe window. The shortcut is a
temporary default used only by this prototype.

## Validate on each platform

Record the results before adding capture or insertion code:

| Check | Windows | Linux X11 | Linux Wayland |
| --- | --- | --- | --- |
| App opens from tray | | | |
| Global shortcut works | | | |
| Window restores after shortcut | | | |
| Shortcut conflicts are reported | | | |

The next milestone adds platform adapters for focused-window context,
accessibility text, screenshots, and text insertion. Those capabilities must
be verified per desktop environment before they are presented as supported.
