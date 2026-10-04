//! Which display server a Linux session runs on. It decides what Feather can do: on X11 an app can
//! read and type into another, on Wayland it needs the desktop's portals and accessibility service.

use std::sync::OnceLock;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Session {
    X11,
    Wayland,
    Unknown,
}

impl Session {
    pub fn name(self) -> &'static str {
        match self {
            Session::X11 => "x11",
            Session::Wayland => "wayland",
            Session::Unknown => "unknown",
        }
    }
}

/// `XDG_SESSION_TYPE` is authoritative when it is set. Without it, a Wayland socket wins over
/// `DISPLAY`, because XWayland sets `DISPLAY` inside Wayland sessions too.
pub fn detect(session_type: Option<&str>, wayland_display: Option<&str>, display: Option<&str>) -> Session {
    match session_type.map(str::to_ascii_lowercase).as_deref() {
        Some("wayland") => return Session::Wayland,
        Some("x11") => return Session::X11,
        _ => {}
    }
    let set = |value: Option<&str>| value.is_some_and(|value| !value.is_empty());
    if set(wayland_display) {
        Session::Wayland
    } else if set(display) {
        Session::X11
    } else {
        Session::Unknown
    }
}

/// The current session, read once.
pub fn current() -> Session {
    static SESSION: OnceLock<Session> = OnceLock::new();
    *SESSION.get_or_init(|| {
        let var = |name: &str| std::env::var(name).ok();
        detect(var("XDG_SESSION_TYPE").as_deref(), var("WAYLAND_DISPLAY").as_deref(), var("DISPLAY").as_deref())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_session_type_wins_when_it_is_set() {
        assert_eq!(detect(Some("wayland"), None, Some(":0")), Session::Wayland);
        assert_eq!(detect(Some("X11"), Some("wayland-0"), None), Session::X11);
    }

    #[test]
    fn a_wayland_socket_beats_the_display_xwayland_sets() {
        assert_eq!(detect(None, Some("wayland-0"), Some(":0")), Session::Wayland);
        assert_eq!(detect(Some("tty"), Some("wayland-0"), Some(":0")), Session::Wayland);
    }

    #[test]
    fn a_display_alone_means_x11_and_nothing_means_unknown() {
        assert_eq!(detect(None, None, Some(":0")), Session::X11);
        assert_eq!(detect(None, Some(""), Some("")), Session::Unknown);
        assert_eq!(detect(None, None, None), Session::Unknown);
    }
}
