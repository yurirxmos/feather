//! Puts generated text into the target app's focused field by pasting, then restores the user's
//! clipboard. Pasting works in web apps (Gmail, WhatsApp Web, Slack) where setting a field's value
//! through accessibility does not.

use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use arboard::{Clipboard, ImageData};

use crate::platform::{self, Target};

/// One clipboard for the app's lifetime. On X11 the owner must stay alive to serve what it copied.
static CLIPBOARD: LazyLock<Mutex<Option<Clipboard>>> = LazyLock::new(|| Mutex::new(Clipboard::new().ok()));

enum Saved {
    Text(String),
    Image(ImageData<'static>),
    Nothing,
}

pub fn copy(text: &str) -> bool {
    with_clipboard(|clipboard| clipboard.set_text(text).is_ok()).unwrap_or(false)
}

/// Whether `paste` can work on this platform and session.
pub fn can_paste() -> bool {
    platform::capabilities().iter().any(|capability| capability.id == "automatic-insertion" && capability.available)
}

/// Blocking; call it off the main thread after the panel has closed.
pub fn paste(text: &str, target: &Target) {
    platform::activate(target);
    std::thread::sleep(Duration::from_millis(150));

    let saved = with_clipboard(|clipboard| match clipboard.get_text() {
        Ok(text) => Saved::Text(text),
        Err(_) => clipboard.get_image().map(Saved::Image).unwrap_or(Saved::Nothing),
    })
    .unwrap_or(Saved::Nothing);
    if !copy(text) {
        return;
    }
    let ours = platform::clipboard_change_token();

    platform::send_paste_shortcut();
    std::thread::sleep(Duration::from_millis(400));

    // Leave the clipboard alone if something else wrote to it in the meantime.
    with_clipboard(|clipboard| {
        let unchanged = match ours {
            Some(token) => platform::clipboard_change_token() == Some(token),
            None => clipboard.get_text().is_ok_and(|current| current == text),
        };
        if !unchanged {
            return;
        }
        let _ = match saved {
            Saved::Text(previous) => clipboard.set_text(previous),
            Saved::Image(image) => clipboard.set_image(image),
            Saved::Nothing => clipboard.clear(),
        };
    });
}

fn with_clipboard<T>(action: impl FnOnce(&mut Clipboard) -> T) -> Option<T> {
    let mut guard = CLIPBOARD.lock().ok()?;
    if guard.is_none() {
        *guard = Clipboard::new().ok();
    }
    guard.as_mut().map(action)
}
