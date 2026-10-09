//! Platform adapters for reading the focused window, capturing it, and pasting into it. Nothing
//! here runs until the user presses the shortcut.

#[cfg(windows)]
mod windows;
#[cfg(windows)]
use self::windows as imp;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux as imp;
#[cfg(target_os = "linux")]
mod session;

// Other systems, such as macOS, only build the app for development: it captures and pastes nothing.
#[cfg(not(any(windows, target_os = "linux")))]
mod unsupported;
#[cfg(not(any(windows, target_os = "linux")))]
use unsupported as imp;

use std::io::Cursor;
use std::time::Duration;

use image::{imageops::FilterType, DynamicImage, RgbaImage};
use serde::Serialize;

/// Keeps the shortcut responsive when an app exposes a large accessibility tree.
pub const WINDOW_TEXT_BUDGET: Duration = Duration::from_millis(700);
pub const MAX_WINDOW_TEXT_CHARACTERS: usize = 24_000;
pub const MAX_WINDOW_ELEMENTS: usize = 1_200;
/// Web apps nest deeply: WhatsApp Web's messages sit 20 to 28 levels down.
pub const MAX_TREE_DEPTH: usize = 32;
/// Large documents can expose megabytes of text; the prompt keeps only the tail anyway.
#[cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]
pub const MAX_FIELD_TEXT: i32 = 200_000;

/// Vision models downscale anything larger, so sending more only adds latency.
const MAX_SCREENSHOT_LONG_EDGE: u32 = 1_568;

/// The app that was frontmost when the shortcut was pressed.
#[derive(Clone, Debug)]
pub struct Target {
    /// An `HWND`.
    pub window: u64,
    pub pid: u32,
    pub app_name: Option<String>,
    pub app_id: Option<String>,
}

/// Physical pixels in global coordinates with a top-left origin.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Debug, Default)]
pub struct Snapshot {
    pub window_title: Option<String>,
    pub focused_text: Option<String>,
    pub selected_text: Option<String>,
    pub window_text: Option<String>,
    pub window_text_was_truncated: bool,
    /// The focus was in a field the user types into, such as a message or email body.
    pub focus_is_in_text_field: bool,
    /// Whether the focused field takes a password. Its text is never read, and Insert copies
    /// instead of pasting into it.
    pub focused_field_is_secure: bool,
    pub window_frame: Option<Rect>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Capability {
    pub id: &'static str,
    pub available: bool,
}

/// The operating system, as the webview names it.
pub fn name() -> &'static str {
    if cfg!(windows) {
        "windows"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else {
        "other"
    }
}

/// On Linux, `x11`, `wayland`, or `unknown`; `None` elsewhere.
pub fn session_name() -> Option<&'static str> {
    #[cfg(target_os = "linux")]
    {
        Some(session::current().name())
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

/// Turns on what the platform needs before the first capture, such as accessibility support.
pub fn prepare() {
    imp::prepare();
}

/// Returns the frontmost window unless it belongs to Feather itself.
pub fn foreground_target() -> Option<Target> {
    imp::foreground_target().filter(|target| target.pid != std::process::id())
}

/// The target window's frame, read on its own so the panel can open before the slower text
/// capture finishes. Blocking but quick.
pub fn window_frame(target: &Target) -> Option<Rect> {
    imp::window_frame(target)
}

/// Reads the focused field and window text. Blocking; call it off the main thread.
pub fn capture(target: &Target) -> Snapshot {
    imp::capture(target)
}

/// Whether the screenshot must be taken before the panel appears, because the platform can only
/// read what is visible on screen.
pub const CAPTURES_SCREENSHOT_BEFORE_PANEL: bool = imp::CAPTURES_SCREENSHOT_BEFORE_PANEL;

/// A JPEG of the target window. Blocking; call it off the main thread.
pub fn screenshot_jpeg(target: &Target, frame: Option<Rect>) -> Option<Vec<u8>> {
    imp::screenshot(target, frame).and_then(encode_jpeg)
}

/// Whether the target window still exists, so a paste cannot land in whatever app replaced it.
pub fn is_open(target: &Target) -> bool {
    imp::is_open(target)
}

/// Brings the target window back to the front.
pub fn activate(target: &Target) {
    imp::activate(target);
}

/// Sends the platform's paste shortcut to the focused window.
pub fn send_paste_shortcut() {
    imp::send_paste_shortcut();
}

/// A value that changes whenever anything writes to the clipboard, where the platform has one.
pub fn clipboard_change_token() -> Option<u64> {
    imp::clipboard_change_token()
}

pub fn capabilities() -> Vec<Capability> {
    imp::capabilities()
}

fn encode_jpeg(image: RgbaImage) -> Option<Vec<u8>> {
    let (width, height) = image.dimensions();
    if width == 0 || height == 0 {
        return None;
    }
    let mut image = DynamicImage::ImageRgba8(image);
    let long_edge = width.max(height);
    if long_edge > MAX_SCREENSHOT_LONG_EDGE {
        let scale = MAX_SCREENSHOT_LONG_EDGE as f64 / long_edge as f64;
        let size = |value: u32| ((value as f64 * scale).round() as u32).max(1);
        image = image.resize_exact(size(width), size(height), FilterType::Triangle);
    }
    let mut jpeg = Vec::new();
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(Cursor::new(&mut jpeg), 70);
    DynamicImage::ImageRgb8(image.to_rgb8()).write_with_encoder(encoder).ok()?;
    Some(jpeg)
}

/// Collects distinct text from an accessibility tree within the element, character, and time
/// budgets shared by every platform.
pub struct TextCollector {
    parts: Vec<String>,
    characters: usize,
    elements: usize,
    deadline: std::time::Instant,
    pub truncated: bool,
}

impl TextCollector {
    /// Starts the time budget.
    pub fn start() -> Self {
        Self {
            parts: Vec::new(),
            characters: 0,
            elements: 0,
            deadline: std::time::Instant::now() + WINDOW_TEXT_BUDGET,
            truncated: false,
        }
    }

    /// Counts one element; returns false once a budget is spent and the walk should stop.
    pub fn visit(&mut self, depth: usize) -> bool {
        if std::time::Instant::now() >= self.deadline
            || depth >= MAX_TREE_DEPTH
            || self.elements >= MAX_WINDOW_ELEMENTS
            || self.characters >= MAX_WINDOW_TEXT_CHARACTERS
        {
            self.truncated = true;
            return false;
        }
        self.elements += 1;
        true
    }

    pub fn add(&mut self, value: String) {
        let count = value.chars().count();
        if count > 1 && !self.parts.contains(&value) && self.characters + count <= MAX_WINDOW_TEXT_CHARACTERS {
            self.characters += count;
            self.parts.push(value);
        }
    }

    pub fn finish(self) -> (Option<String>, bool) {
        let truncated = self.truncated
            || self.elements >= MAX_WINDOW_ELEMENTS
            || self.characters >= MAX_WINDOW_TEXT_CHARACTERS;
        let text = self.parts.join("\n");
        ((!text.is_empty()).then_some(text), truncated)
    }
}

/// Trims and drops empty values.
pub fn non_empty(value: String) -> Option<String> {
    (!value.trim().is_empty()).then_some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collector_skips_duplicates_and_single_characters() {
        let mut collector = TextCollector::start();
        assert!(collector.visit(0));
        collector.add("Hello".into());
        collector.add("Hello".into());
        collector.add("x".into());
        assert_eq!(collector.finish(), (Some("Hello".into()), false));
    }

    #[test]
    fn collector_stops_at_the_depth_limit() {
        let mut collector = TextCollector::start();
        assert!(!collector.visit(MAX_TREE_DEPTH));
        assert!(collector.finish().1);
    }

    #[test]
    fn screenshots_are_downscaled_jpegs() {
        let jpeg = encode_jpeg(RgbaImage::new(3_000, 1_000)).unwrap();
        let decoded = image::load_from_memory(&jpeg).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (1_568, 523));
    }
}
