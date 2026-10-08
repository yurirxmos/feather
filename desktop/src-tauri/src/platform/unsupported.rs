//! Lets the desktop app build and run on development machines that are not Windows.
//! It captures nothing and pastes nothing; the macOS app is the real client there.

use super::{Capability, Rect, Snapshot, Target};

pub const CAPTURES_SCREENSHOT_BEFORE_PANEL: bool = false;

pub fn prepare() {}

pub fn foreground_target() -> Option<Target> {
    None
}

pub fn window_frame(_target: &Target) -> Option<Rect> {
    None
}

pub fn capture(_target: &Target) -> Snapshot {
    Snapshot::default()
}

pub fn screenshot(_target: &Target, _frame: Option<Rect>) -> Option<image::RgbaImage> {
    None
}

pub fn activate(_target: &Target) {}

pub fn send_paste_shortcut() {}

pub fn clipboard_change_token() -> Option<u64> {
    None
}

pub fn capabilities() -> Vec<Capability> {
    ["focused-context", "window-screenshot", "automatic-insertion"]
        .into_iter()
        .map(|id| Capability { id, available: false })
        .collect()
}
