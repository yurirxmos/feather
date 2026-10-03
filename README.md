# Feather

**Press a shortcut. Tell your Mac what to write.**

Feather is a macOS menu-bar writing assistant. While working in any app, press a
global shortcut, describe what you want to write, and Feather generates a reply
from the context around your cursor. Press `Return` again to paste it into the
field you were using.

For example:

> Reply that I can do tomorrow at 2 pm, in a formal tone.

Feather can draft messages, rewrite text, translate, summarize, and refine a
previous result with follow-up instructions such as “shorter” or “more casual.”

## How it works

When you invoke Feather, it captures the available context from the frontmost
app and sends it with your instruction to the selected provider. Context can
include:

- App and window name
- Text in the focused field and selected text
- Readable text from the active window
- A screenshot of the active window, when enabled

The reply streams into Feather's panel. You can insert it, copy it, regenerate
it, or keep writing an instruction to refine it.

Nothing is captured until you press the shortcut. Context, instructions, and
responses are discarded when the panel closes. Feather logs generation timings
only; it does not log screen contents, instructions, or responses.

## Providers

Set up a provider in **Feather > Settings > Connection**. Providers you have set up are listed
first, with the one in use marked; click **Use** to switch. The first one you set up is used right
away, and removing the one in use switches to another that is set up.

### Feather Plus

Feather Plus is the hosted option: no API key needed. Click **Set Up…** next to Feather Plus in
**Settings > Connection**, sign in with a one-time email link, and pick a plan. The account and
usage are in **Settings > Feather Plus**.

| Plan | Price | Includes |
| --- | --- | --- |
| Starter | $5/month | 500 requests per billing period |
| Max | $20/month | 4,000 requests per billing period |

Both plans use the same model; they differ only in how many requests they include. Feather
never stores your instructions, screen context, or replies; they pass through its server to
the model provider, which handles them under its own data policy. Only your email, plan, and
request and token counts are kept.

Bringing your own OpenCode Go key or ChatGPT account stays free.

### OpenCode Go

OpenCode Go uses its OpenAI-compatible streaming API. Paste an OpenCode Go API
key in Settings, then select a model from the available-model list. The default
model is `deepseek-v4.1-flash`.

Your API key is stored in the macOS Keychain. Model availability and usage are
managed by your OpenCode subscription.

### ChatGPT

ChatGPT connects through a browser sign-in flow. Select **ChatGPT** in Settings
and choose **Sign in with ChatGPT**. Feather stores the resulting session
credentials in the macOS Keychain and refreshes them when needed.

Select one of the ChatGPT models offered in Settings. Access and model
availability depend on your ChatGPT account.

## Setup

1. Launch Feather from the menu bar.
2. Open **Settings** and connect OpenCode Go or ChatGPT.
3. Grant the required permissions:
   - **Accessibility** lets Feather read the focused field and paste a result.
   - **Screen Recording** lets Feather capture the active-window screenshot.
4. Choose a shortcut and, optionally, configure writing preferences or disable
   screenshots.

Screen Recording is required by the current permissions flow even when the
screenshot option is disabled. Relaunch Feather after granting it.

## Download

Preview builds are published on the [GitHub Releases](https://github.com/yurirxmos/feather/releases)
page for macOS 14 or later:

- `Feather-arm64.dmg` for Apple Silicon Macs
- `Feather-x86_64.dmg` for Intel Macs

The preview builds are signed with Feather's own certificate and are not notarized
yet. macOS may block the first launch. To open Feather anyway:

1. In Finder, Control-click `Feather.app` and choose **Open**.
2. If macOS still blocks it, open **System Settings > Privacy & Security**.
3. Scroll to the Security section and choose **Open Anyway** beside Feather.
4. Confirm **Open** in the dialog.

After Feather opens, grant **Accessibility** and **Screen Recording** in its
Settings page. You can also grant them manually in **System Settings > Privacy
& Security > Accessibility** and **Screen Recording**. Quit and reopen Feather
after granting Screen Recording.

Feather checks for updates on launch and every hour. When a new version is out it
asks before installing, and the permissions carry over. You can also choose
**Check for Updates…** from the menu-bar icon.

A future stable release will use a Developer ID signature and Apple
notarization.

## Keyboard shortcuts

### Global shortcut

The default shortcut is `⌥ Space`. Choose one of these presets in Settings:

| Shortcut | Action |
| --- | --- |
| `⌥ Space` | Open Feather (default) |
| `⌃ ⌥ Space` | Open Feather |
| `⇧ ⌘ Space` | Open Feather |
| `⌃ ⌥ ↩` | Open Feather |

### In the Feather panel

| Key | Action |
| --- | --- |
| `Return` | Generate a result, then insert it into the focused field |
| `⌘ Return` | Copy the result |
| `⌘ R` | Regenerate the result |
| `Esc` | Hide Feather so you can adjust the source window and capture again |

If Feather cannot paste into the target field, it copies the result instead.

## Build from source

Requirements:

- macOS 14 or later
- Xcode 15 or later

From the repository root:

```sh
swift build
swift test
scripts/bundle.sh          # produces dist/Feather.app
open dist/Feather.app
```

The bundle script uses ad-hoc signing by default. macOS ties Accessibility and
Screen Recording grants to the code signature, so use a stable signing identity
while developing to retain those permissions between builds:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/bundle.sh
```

Set `VERSION` to override the app version embedded in the bundle:

```sh
VERSION=1.0.0 scripts/bundle.sh
```

Local builds leave the updater off. To publish a release, push a version tag; the
`Release macOS` workflow builds both architectures, signs them, and publishes the
disk images with a signed Sparkle feed per architecture:

```sh
git tag v0.1.7 && git push origin v0.1.7
```

## Development

`FeatherCore` contains the pure, testable logic for prompt construction,
provider requests, and server-sent-event parsing. The `Feather` target contains
the macOS app, including the menu-bar UI, permissions, hotkey, screen capture,
and text insertion.

Run the unit tests with:

```sh
swift test
```

AppKit, Accessibility, and ScreenCaptureKit behavior should also be verified by
running the bundled app.

## License

Feather is released under the [MIT License](LICENSE).
