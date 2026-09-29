# Context Bar

Press a shortcut. Tell your Mac what to write.

Context Bar is a macOS menu-bar app. Press the hotkey (default `⌥Space`) while you are in any
app, type an instruction such as "reply accepting tomorrow at 2 pm, formal tone", and press
`Return`. The model receives your instruction plus the context on screen (app, window title,
focused field, selected text, and a screenshot of the active window), streams a reply, and
pastes it into the field you were typing in.

Nothing is captured until you press the shortcut, and the context is discarded when the panel
closes.

## Keys

| Key | Action |
| --- | --- |
| `Return` | Generate, then insert the result into the focused field |
| `⌘Return` | Copy the result |
| `⌘R` | Regenerate |
| `Esc` | Close |

Typing a new instruction after a result refines it ("shorter", "more casual").

## OpenCode Go

Context Bar uses OpenCode Go through its OpenAI-compatible streaming API. In Settings, paste your
OpenCode Go API key and choose a model. The default is `deepseek-v4.1-flash`.

The key is stored in the macOS Keychain. OpenCode Go models and usage limits are managed by your
OpenCode subscription.

Keys are stored in the macOS Keychain.

## Build

Requires macOS 14+ and Xcode 15+.

```sh
swift build
swift test
scripts/bundle.sh          # produces dist/ContextBar.app
open dist/ContextBar.app
```

On first launch, grant **Accessibility** (read the focused field, paste) and **Screen
Recording** (window screenshot). Set `CODESIGN_IDENTITY` to a stable signing identity before
running `scripts/bundle.sh`; with ad-hoc signing macOS revokes the permissions on every rebuild.
