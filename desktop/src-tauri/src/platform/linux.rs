//! Linux adapter. On X11 it uses EWMH properties for the active window, `GetImage` for screenshots,
//! XTest for pasting, and AT-SPI for text. Wayland does not let one app look at or type into
//! another, so there it reads the focused app and its text through AT-SPI, which is a D-Bus service
//! and works on both, and leaves the reply on the clipboard for the user to paste.

use std::future::Future;
use std::time::Duration;

use atspi::proxy::accessible::{AccessibleProxy, ObjectRefExt};
use atspi::proxy::proxy_ext::ProxyExt;
use atspi::zbus::{self, names::BusName};
use atspi::{AccessibilityConnection, Interface, MatchType, ObjectMatchRule, ObjectRefOwned, Role, SortOrder, State};
use image::RgbaImage;
use x11rb::connection::Connection;
use x11rb::protocol::xproto::{AtomEnum, ClientMessageEvent, ConnectionExt as _, EventMask, ImageFormat, Window};
use x11rb::protocol::xtest::ConnectionExt as _;
use x11rb::rust_connection::RustConnection;
use x11rb::CURRENT_TIME;

use super::session::{self, Session};
use super::{non_empty, Capability, Rect, Snapshot, Target, TextCollector, MAX_FIELD_TEXT};

/// `GetImage` reads the screen, so it must run before the panel covers the window.
pub const CAPTURES_SCREENSHOT_BEFORE_PANEL: bool = true;

/// The longest any single accessibility call may take, so a hung app cannot freeze the shortcut.
const CALL_TIMEOUT: Duration = Duration::from_millis(300);

const KEYSYM_CONTROL_L: u32 = 0xffe3;
const KEYSYM_V: u32 = 0x0076;
const KEY_PRESS: u8 = 2;
const KEY_RELEASE: u8 = 3;

pub fn is_x11_session() -> bool {
    session::current() == Session::X11
}

fn is_wayland_session() -> bool {
    session::current() == Session::Wayland
}

/// Asks toolkits to expose their accessibility trees, as a screen reader would. GTK, Qt, and
/// Chromium watch this flag and only build the tree when it is on.
pub fn prepare() {
    if is_x11_session() || is_wayland_session() {
        tauri::async_runtime::spawn(async {
            let _ = atspi::connection::set_session_accessibility(true).await;
        });
    }
}

struct X11 {
    connection: RustConnection,
    root: Window,
}

impl X11 {
    fn connect() -> Option<Self> {
        if !is_x11_session() {
            return None;
        }
        let (connection, screen) = x11rb::connect(None).ok()?;
        let root = connection.setup().roots.get(screen)?.root;
        Some(Self { connection, root })
    }

    fn atom(&self, name: &str) -> Option<u32> {
        Some(self.connection.intern_atom(false, name.as_bytes()).ok()?.reply().ok()?.atom)
    }

    fn property(&self, window: Window, name: &str, kind: impl Into<u32>) -> Option<Vec<u8>> {
        let atom = self.atom(name)?;
        let reply = self.connection.get_property(false, window, atom, kind.into(), 0, 1 << 16).ok()?.reply().ok()?;
        (!reply.value.is_empty()).then_some(reply.value)
    }

    fn property_u32(&self, window: Window, name: &str, kind: AtomEnum) -> Option<u32> {
        let value = self.property(window, name, kind)?;
        Some(u32::from_ne_bytes(value.get(..4)?.try_into().ok()?))
    }

    fn active_window(&self) -> Option<Window> {
        self.property_u32(self.root, "_NET_ACTIVE_WINDOW", AtomEnum::WINDOW).filter(|&window| window != 0)
    }

    fn title(&self, window: Window) -> Option<String> {
        let utf8 = self.atom("UTF8_STRING")?;
        self.property(window, "_NET_WM_NAME", utf8)
            .or_else(|| self.property(window, "WM_NAME", AtomEnum::STRING))
            .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
            .and_then(non_empty)
    }

    /// `WM_CLASS` holds the instance and class names, such as `firefox` and `Firefox`.
    fn class(&self, window: Window) -> Option<(String, String)> {
        let value = self.property(window, "WM_CLASS", AtomEnum::STRING)?;
        let mut parts = value.split(|&byte| byte == 0).filter(|part| !part.is_empty());
        let instance = String::from_utf8_lossy(parts.next()?).into_owned();
        let class = parts.next().map(|part| String::from_utf8_lossy(part).into_owned()).unwrap_or_else(|| instance.clone());
        Some((instance, class))
    }

    fn frame(&self, window: Window) -> Option<Rect> {
        let geometry = self.connection.get_geometry(window).ok()?.reply().ok()?;
        let origin = self.connection.translate_coordinates(window, self.root, 0, 0).ok()?.reply().ok()?;
        Some(Rect { x: origin.dst_x.into(), y: origin.dst_y.into(), width: geometry.width.into(), height: geometry.height.into() })
    }

    fn keycode(&self, keysym: u32) -> Option<u8> {
        let setup = self.connection.setup();
        let count = setup.max_keycode - setup.min_keycode + 1;
        let mapping = self.connection.get_keyboard_mapping(setup.min_keycode, count).ok()?.reply().ok()?;
        let per_keycode = usize::from(mapping.keysyms_per_keycode).max(1);
        let index = mapping.keysyms.iter().position(|&candidate| candidate == keysym)?;
        Some(setup.min_keycode + (index / per_keycode) as u8)
    }
}

pub fn foreground_target() -> Option<Target> {
    if is_wayland_session() {
        return tauri::async_runtime::block_on(active_application());
    }
    let x11 = X11::connect()?;
    let window = x11.active_window()?;
    let pid = x11.property_u32(window, "_NET_WM_PID", AtomEnum::CARDINAL).unwrap_or(0);
    let class = x11.class(window);
    Some(Target {
        window: window.into(),
        pid,
        app_name: class.as_ref().map(|(_, class)| class.clone()),
        app_id: class.map(|(instance, _)| instance),
    })
}

pub fn capture(target: &Target) -> Snapshot {
    let mut snapshot = Snapshot::default();
    if let Some(x11) = X11::connect() {
        snapshot.window_title = x11.title(target.window as Window);
        snapshot.window_frame = x11.frame(target.window as Window);
    }
    if target.pid != 0 {
        let pid = target.pid;
        let text = tauri::async_runtime::block_on(async move { accessibility_text(pid).await });
        // X11 reads the title from the window manager; Wayland has no such thing.
        snapshot.window_title = snapshot.window_title.or(text.title);
        snapshot.focused_text = text.focused;
        snapshot.selected_text = text.selected;
        snapshot.window_text = text.window;
        snapshot.window_text_was_truncated = text.truncated;
    }
    snapshot
}

#[derive(Default)]
struct AccessibilityText {
    title: Option<String>,
    focused: Option<String>,
    selected: Option<String>,
    window: Option<String>,
    truncated: bool,
}

async fn call<T, E>(future: impl Future<Output = Result<T, E>>) -> Option<T> {
    tokio::time::timeout(CALL_TIMEOUT, future).await.ok()?.ok()
}

async fn accessibility_text(pid: u32) -> AccessibilityText {
    let mut result = AccessibilityText::default();
    let Some(connection) = call(AccessibilityConnection::new()).await else {
        return result;
    };
    let bus = connection.connection();
    let Some(window) = active_frame(bus, pid).await else {
        return result;
    };
    result.title = call(window.name()).await.and_then(non_empty);

    // The selected text and field draft are the most useful context. Read them before traversing
    // the potentially large window tree.
    if let Some(focused) = focused_element(bus, &window).await {
        if call(focused.get_role()).await != Some(Role::PasswordText) {
            let (text, selected) = text_and_selection(&focused).await;
            result.focused = text;
            result.selected = selected;
        }
    }

    let mut collector = TextCollector::start();
    collect(bus, window, 0, &mut collector).await;
    (result.window, result.truncated) = collector.finish();
    result
}

/// The accessibility registry, whose children are every application that exposes a tree.
async fn registry<'a>(bus: &'a zbus::Connection) -> Option<AccessibleProxy<'a>> {
    AccessibleProxy::builder(bus)
        .destination("org.a11y.atspi.Registry")
        .ok()?
        .path("/org/a11y/atspi/accessible/root")
        .ok()?
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await
        .ok()
}

/// Wayland gives no window id to ask for, so the app in front is the one whose window reports the
/// `Active` state through accessibility. There is no window to activate or photograph afterwards.
async fn active_application() -> Option<Target> {
    let connection = call(AccessibilityConnection::new()).await?;
    let bus = connection.connection();
    let registry = registry(bus).await?;
    let dbus = zbus::fdo::DBusProxy::new(bus).await.ok()?;

    for application in call(registry.get_children()).await? {
        let Some(name) = application.name().map(|name| BusName::from(name.clone())) else {
            continue;
        };
        let Some(proxy) = owned_proxy(bus, &application).await else { continue };
        for frame in call(proxy.get_children()).await.unwrap_or_default() {
            let Some(frame) = owned_proxy(bus, &frame).await else { continue };
            if !call(frame.get_state()).await.is_some_and(|state| state.contains(State::Active)) {
                continue;
            }
            let pid = call(dbus.get_connection_unix_process_id(name)).await?;
            let app_name = call(proxy.name()).await.and_then(non_empty);
            return Some(Target { window: 0, pid, app_name: app_name.clone(), app_id: app_name });
        }
    }
    None
}

/// The application's active top-level window.
async fn active_frame<'a>(bus: &'a zbus::Connection, pid: u32) -> Option<AccessibleProxy<'a>> {
    let registry = registry(bus).await?;
    let dbus = zbus::fdo::DBusProxy::new(bus).await.ok()?;

    for application in call(registry.get_children()).await? {
        let Some(name) = application.name().map(|name| BusName::from(name.clone())) else {
            continue;
        };
        if call(dbus.get_connection_unix_process_id(name)).await != Some(pid) {
            continue;
        }
        let application = owned_proxy(bus, &application).await?;
        let frames = call(application.get_children()).await.unwrap_or_default();
        let mut first = None;
        for frame in frames {
            let Some(proxy) = owned_proxy(bus, &frame).await else { continue };
            if call(proxy.get_state()).await.is_some_and(|state| state.contains(State::Active)) {
                return Some(proxy);
            }
            first.get_or_insert(proxy);
        }
        return first;
    }
    None
}

/// Asks the window's `Collection` interface for the focused descendant, which avoids walking a
/// large tree. Toolkits without it fall back to the walk in `collect`, which cannot find focus.
async fn focused_element<'a>(bus: &'a zbus::Connection, window: &AccessibleProxy<'a>) -> Option<AccessibleProxy<'a>> {
    let collection = call(window.proxies()).await?.collection().await.ok()?;
    let rule = ObjectMatchRule::builder().states([State::Focused], MatchType::All).build();
    let matches = call(collection.get_matches(rule, SortOrder::Canonical, 1, true)).await?;
    owned_proxy(bus, matches.first()?).await
}

async fn text_and_selection(element: &AccessibleProxy<'_>) -> (Option<String>, Option<String>) {
    let Some(proxies) = call(element.proxies()).await else {
        return (None, None);
    };
    let Ok(text) = proxies.text().await else {
        return (None, None);
    };
    let count = call(text.character_count()).await.unwrap_or(0);
    let full = call(text.get_text((count - MAX_FIELD_TEXT).max(0), count)).await.and_then(non_empty);
    let mut selected = Vec::new();
    for index in 0..call(text.get_n_selections()).await.unwrap_or(0).min(8) {
        if let Some((start, end)) = call(text.get_selection(index)).await.filter(|(start, end)| end > start) {
            if let Some(part) = call(text.get_text(start, end)).await.and_then(non_empty) {
                selected.push(part);
            }
        }
    }
    (full, non_empty(selected.join("\n")))
}

async fn collect<'a>(bus: &'a zbus::Connection, element: AccessibleProxy<'a>, depth: usize, collector: &mut TextCollector) {
    if !collector.visit(depth) {
        return;
    }
    if call(element.get_role()).await == Some(Role::PasswordText) {
        return;
    }
    if let Some(name) = call(element.name()).await {
        collector.add(name);
    }
    let interfaces = call(element.get_interfaces()).await;
    if interfaces.is_some_and(|interfaces| interfaces.contains(Interface::Text)) {
        if let Some(text) = call(element.proxies()).await {
            if let Ok(text) = text.text().await {
                let count = call(text.character_count()).await.unwrap_or(0).min(MAX_FIELD_TEXT);
                if let Some(value) = call(text.get_text(0, count)).await {
                    collector.add(value);
                }
            }
        }
    }
    for child in call(element.get_children()).await.unwrap_or_default() {
        if collector.truncated {
            return;
        }
        if let Some(child) = owned_proxy(bus, &child).await {
            Box::pin(collect(bus, child, depth + 1, collector)).await;
        }
    }
}

async fn owned_proxy<'a>(bus: &'a zbus::Connection, object: &ObjectRefOwned) -> Option<AccessibleProxy<'a>> {
    if object.is_null() {
        return None;
    }
    call(object.clone().into_accessible_proxy(bus)).await
}

/// Reads the window's pixels from the screen, which requires it to be visible and unobscured.
pub fn screenshot(target: &Target, frame: Option<Rect>) -> Option<RgbaImage> {
    let x11 = X11::connect()?;
    let frame = frame.or_else(|| x11.frame(target.window as Window))?;
    let screen = x11.connection.setup().roots.first()?;
    let x = frame.x.max(0);
    let y = frame.y.max(0);
    let width = (frame.x + frame.width as i32).min(screen.width_in_pixels.into()) - x;
    let height = (frame.y + frame.height as i32).min(screen.height_in_pixels.into()) - y;
    if width < 50 || height < 50 {
        return None;
    }
    let reply = x11
        .connection
        .get_image(ImageFormat::Z_PIXMAP, x11.root, x as i16, y as i16, width as u16, height as u16, !0)
        .ok()?
        .reply()
        .ok()?;
    let (width, height) = (width as u32, height as u32);
    let bytes_per_pixel = reply.data.len() / (width * height) as usize;
    if bytes_per_pixel != 4 {
        return None;
    }
    // 24- and 32-bit visuals store pixels as little-endian BGRX.
    let rgba = reply.data.as_chunks::<4>().0.iter().flat_map(|pixel| [pixel[2], pixel[1], pixel[0], 255]).collect();
    RgbaImage::from_raw(width, height, rgba)
}

pub fn activate(target: &Target) {
    let Some(x11) = X11::connect() else { return };
    let Some(atom) = x11.atom("_NET_ACTIVE_WINDOW") else { return };
    // Source indication 2 tells the window manager the request comes from a pager-like tool, which
    // it honors without focus-stealing prevention.
    let event = ClientMessageEvent::new(32, target.window as Window, atom, [2u32, CURRENT_TIME, 0, 0, 0]);
    let _ = x11.connection.send_event(
        false,
        x11.root,
        EventMask::SUBSTRUCTURE_REDIRECT | EventMask::SUBSTRUCTURE_NOTIFY,
        event,
    );
    let _ = x11.connection.flush();
}

pub fn send_paste_shortcut() {
    let Some(x11) = X11::connect() else { return };
    let (Some(control), Some(v)) = (x11.keycode(KEYSYM_CONTROL_L), x11.keycode(KEYSYM_V)) else { return };
    for (kind, keycode) in [(KEY_PRESS, control), (KEY_PRESS, v), (KEY_RELEASE, v), (KEY_RELEASE, control)] {
        let _ = x11.connection.xtest_fake_input(kind, keycode, CURRENT_TIME, x11.root, 0, 0, 0);
    }
    let _ = x11.connection.flush();
}

/// X11 has no clipboard change counter; the caller compares contents instead.
pub fn clipboard_change_token() -> Option<u64> {
    None
}

pub fn capabilities() -> Vec<Capability> {
    let x11 = is_x11_session();
    vec![
        Capability { id: "x11-session", available: x11 },
        // Accessibility is a D-Bus service, so it works on Wayland too.
        Capability { id: "focused-context", available: x11 || is_wayland_session() },
        Capability { id: "window-screenshot", available: x11 },
        Capability { id: "automatic-insertion", available: x11 },
    ]
}
