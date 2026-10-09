//! Windows adapter: UI Automation for text, `PrintWindow` for screenshots, and `SendInput` for
//! pasting. None of these need a permission prompt on Windows.

use std::ffi::c_void;
use std::path::Path;

use uiautomation::patterns::{UITextPattern, UIValuePattern};
use uiautomation::types::{ControlType, Handle, UIProperty};
use uiautomation::variants::Value;
use uiautomation::{UIAutomation, UIElement};
use windows::core::{PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HWND, RECT};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_EXTENDED_FRAME_BOUNDS};
use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows::Win32::System::DataExchange::GetClipboardSequenceNumber;
use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_CONTROL,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetForegroundWindow, GetWindowTextW, GetWindowThreadProcessId, IsIconic, IsWindow, SetForegroundWindow, ShowWindow,
    SW_RESTORE,
};

use super::{non_empty, Capability, Rect, Snapshot, Target, TextCollector, MAX_FIELD_TEXT};

/// `PrintWindow` renders the window itself, so the panel covering it does not matter.
pub const CAPTURES_SCREENSHOT_BEFORE_PANEL: bool = false;


const VK_V: VIRTUAL_KEY = VIRTUAL_KEY(0x56);

fn hwnd(target: &Target) -> HWND {
    HWND(target.window as isize as *mut c_void)
}

pub fn prepare() {}

pub fn foreground_target() -> Option<Target> {
    let window = unsafe { GetForegroundWindow() };
    if window.is_invalid() {
        return None;
    }
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(window, Some(&mut pid)) };
    if pid == 0 {
        return None;
    }
    let path = process_path(pid);
    let app_id = path.as_deref().and_then(|path| Path::new(path).file_name()).map(|name| name.to_string_lossy().into_owned());
    let app_name = path
        .as_deref()
        .and_then(file_description)
        .or_else(|| path.as_deref().and_then(|path| Path::new(path).file_stem()).map(|stem| stem.to_string_lossy().into_owned()));
    Some(Target { window: window.0 as usize as u64, pid, app_name, app_id })
}

pub fn window_frame(target: &Target) -> Option<Rect> {
    visible_frame(hwnd(target))
}

pub fn capture(target: &Target) -> Snapshot {
    let mut snapshot = Snapshot { window_title: window_title(hwnd(target)), window_frame: visible_frame(hwnd(target)), ..Snapshot::default() };
    let Ok(automation) = UIAutomation::new() else {
        return snapshot;
    };

    // The selected text and field draft are the most useful context. Read them before traversing
    // the potentially large window tree.
    if let Ok(focused) = automation.get_focused_element() {
        let belongs_to_target = focused.get_process_id().map(|pid| pid == target.pid).unwrap_or(false);
        // Unknown counts as a password for reading, but only a known one stops Insert from pasting.
        let is_password = focused.is_password().ok();
        if belongs_to_target && is_password == Some(true) {
            snapshot.focused_field_is_secure = true;
        } else if belongs_to_target && is_password == Some(false) {
            snapshot.selected_text = selected_text(&focused);
            snapshot.focused_text = field_text(&focused);
            snapshot.focus_is_in_text_field = is_text_field(&focused);
        }
    }

    if let Ok(window) = automation.element_from_handle(Handle::from(target.window as isize)) {
        let (text, truncated) = window_text(&automation, &window);
        snapshot.window_text = text;
        snapshot.window_text_was_truncated = truncated;
    }
    snapshot
}

fn selected_text(element: &UIElement) -> Option<String> {
    let pattern = element.get_pattern::<UITextPattern>().ok()?;
    let text: Vec<String> = pattern
        .get_selection()
        .ok()?
        .iter()
        .filter_map(|range| range.get_text(MAX_FIELD_TEXT).ok())
        .filter(|text| !text.is_empty())
        .collect();
    non_empty(text.join("\n"))
}

/// Native and web text fields are Edit controls; other editors expose a writable value.
fn is_text_field(element: &UIElement) -> bool {
    if element.get_control_type().is_ok_and(|control| control == ControlType::Edit) {
        return true;
    }
    element.get_pattern::<UIValuePattern>().ok().and_then(|pattern| pattern.is_readonly().ok()) == Some(false)
}

fn field_text(element: &UIElement) -> Option<String> {
    if let Some(value) = element.get_pattern::<UIValuePattern>().ok().and_then(|pattern| pattern.get_value().ok()) {
        if let Some(value) = non_empty(value) {
            return Some(value);
        }
    }
    let pattern = element.get_pattern::<UITextPattern>().ok()?;
    non_empty(pattern.get_document_range().ok()?.get_text(MAX_FIELD_TEXT).ok()?)
}

/// Walks the control view depth first, prefetching each element's name, value, and password flag
/// in the same cross-process call that returns it.
fn window_text(automation: &UIAutomation, window: &UIElement) -> (Option<String>, bool) {
    let mut collector = TextCollector::start();
    let (Ok(walker), Ok(cache)) = (automation.get_control_view_walker(), automation.create_cache_request()) else {
        return collector.finish();
    };
    for property in [UIProperty::Name, UIProperty::ValueValue, UIProperty::IsPassword] {
        let _ = cache.add_property(property);
    }

    fn visit(walker: &uiautomation::UITreeWalker, cache: &uiautomation::core::UICacheRequest, element: UIElement, depth: usize, collector: &mut TextCollector) {
        if !collector.visit(depth) {
            return;
        }
        let is_password = matches!(element.get_cached_property_value(UIProperty::IsPassword).and_then(|value| value.get_value()), Ok(Value::BOOL(true)));
        if !is_password {
            if let Ok(name) = element.get_cached_name() {
                collector.add(name);
            }
            if let Ok(value) = element.get_cached_property_value(UIProperty::ValueValue).and_then(|value| value.get_string()) {
                collector.add(value);
            }
        }
        let mut child = walker.get_first_child_build_cache(&element, cache).ok();
        while let Some(current) = child {
            visit(walker, cache, current.clone(), depth + 1, collector);
            if collector.truncated {
                return;
            }
            child = walker.get_next_sibling_build_cache(&current, cache).ok();
        }
    }

    if let Ok(root) = window.build_updated_cache(&cache) {
        visit(&walker, &cache, root, 0, &mut collector);
    }
    collector.finish()
}

pub fn screenshot(target: &Target, _frame: Option<Rect>) -> Option<image::RgbaImage> {
    let id = target.window as u32;
    let window = xcap::Window::all().ok()?.into_iter().find(|window| window.id().ok() == Some(id))?;
    window.capture_image().ok()
}

pub fn is_open(target: &Target) -> bool {
    unsafe { IsWindow(Some(hwnd(target))).as_bool() }
}

pub fn activate(target: &Target) {
    let window = hwnd(target);
    unsafe {
        if IsIconic(window).as_bool() {
            let _ = ShowWindow(window, SW_RESTORE);
        }
        let _ = SetForegroundWindow(window);
    }
}

pub fn send_paste_shortcut() {
    let key = |key: VIRTUAL_KEY, flags: KEYBD_EVENT_FLAGS| INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 { ki: KEYBDINPUT { wVk: key, wScan: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 } },
    };
    let inputs = [
        key(VK_CONTROL, KEYBD_EVENT_FLAGS(0)),
        key(VK_V, KEYBD_EVENT_FLAGS(0)),
        key(VK_V, KEYEVENTF_KEYUP),
        key(VK_CONTROL, KEYEVENTF_KEYUP),
    ];
    unsafe { SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) };
}

pub fn clipboard_change_token() -> Option<u64> {
    Some(unsafe { GetClipboardSequenceNumber() } as u64)
}

pub fn capabilities() -> Vec<Capability> {
    ["focused-context", "window-screenshot", "automatic-insertion"]
        .into_iter()
        .map(|id| Capability { id, available: true })
        .collect()
}

fn window_title(window: HWND) -> Option<String> {
    let mut buffer = [0u16; 512];
    let length = unsafe { GetWindowTextW(window, &mut buffer) };
    (length > 0).then(|| String::from_utf16_lossy(&buffer[..length as usize])).and_then(non_empty)
}

/// The visible frame, without the invisible resize borders `GetWindowRect` includes.
fn visible_frame(window: HWND) -> Option<Rect> {
    let mut rect = RECT::default();
    unsafe {
        DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &mut rect as *mut RECT as *mut c_void, std::mem::size_of::<RECT>() as u32)
            .ok()?;
    }
    let width = u32::try_from(rect.right - rect.left).ok()?;
    let height = u32::try_from(rect.bottom - rect.top).ok()?;
    Some(Rect { x: rect.left, y: rect.top, width, height })
}

fn process_path(pid: u32) -> Option<String> {
    unsafe {
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buffer = [0u16; 1024];
        let mut size = buffer.len() as u32;
        let result = QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(buffer.as_mut_ptr()), &mut size);
        let _ = CloseHandle(process);
        result.ok()?;
        Some(String::from_utf16_lossy(&buffer[..size as usize]))
    }
}

/// The executable's `FileDescription`, such as "Google Chrome" for chrome.exe.
fn file_description(path: &str) -> Option<String> {
    let wide = |value: &str| value.encode_utf16().chain(std::iter::once(0)).collect::<Vec<u16>>();
    let path = wide(path);
    unsafe {
        let size = GetFileVersionInfoSizeW(PCWSTR(path.as_ptr()), None);
        if size == 0 {
            return None;
        }
        let mut data = vec![0u8; size as usize];
        GetFileVersionInfoW(PCWSTR(path.as_ptr()), None, size, data.as_mut_ptr() as *mut c_void).ok()?;

        let mut translation: *mut c_void = std::ptr::null_mut();
        let mut length = 0u32;
        let query = wide("\\VarFileInfo\\Translation");
        if !VerQueryValueW(data.as_ptr() as *const c_void, PCWSTR(query.as_ptr()), &mut translation, &mut length).as_bool() || length < 4 {
            return None;
        }
        let language = *(translation as *const u16);
        let code_page = *(translation as *const u16).add(1);

        let query = wide(&format!("\\StringFileInfo\\{language:04x}{code_page:04x}\\FileDescription"));
        let mut value: *mut c_void = std::ptr::null_mut();
        if !VerQueryValueW(data.as_ptr() as *const c_void, PCWSTR(query.as_ptr()), &mut value, &mut length).as_bool() || length == 0 {
            return None;
        }
        let text = std::slice::from_raw_parts(value as *const u16, length as usize);
        let end = text.iter().position(|&unit| unit == 0).unwrap_or(text.len());
        non_empty(String::from_utf16_lossy(&text[..end]).trim().to_owned())
    }
}
