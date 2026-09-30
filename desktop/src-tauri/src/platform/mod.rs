use serde::Serialize;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Capability {
    id: &'static str,
    title: &'static str,
    available: bool,
    detail: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProbeStatus {
    platform: &'static str,
    shortcut: &'static str,
    capabilities: Vec<Capability>,
}

pub fn probe_status() -> ProbeStatus {
    ProbeStatus {
        platform: platform_name(),
        shortcut: "Ctrl+Shift+Space",
        capabilities: vec![
            Capability {
                id: "global-shortcut",
                title: "Global shortcut",
                available: true,
                detail: "The prototype registers Ctrl+Shift+Space while it is running.",
            },
            Capability {
                id: "tray",
                title: "Tray integration",
                available: true,
                detail: "Use the tray menu to show, hide, or quit Feather. Linux click behavior depends on the desktop environment.",
            },
            Capability {
                id: "focused-context",
                title: "Focused-window context",
                available: false,
                detail: "Accessibility adapters have not been implemented or verified yet.",
            },
            Capability {
                id: "window-screenshot",
                title: "Active-window screenshot",
                available: false,
                detail: "Capture is intentionally disabled until platform permissions are verified.",
            },
            Capability {
                id: "automatic-insertion",
                title: "Automatic insertion",
                available: false,
                detail: "Text insertion must be validated per platform and desktop session.",
            },
        ],
    }
}

fn platform_name() -> &'static str {
    if cfg!(target_os = "windows") {
        "Windows"
    } else if cfg!(target_os = "linux") {
        "Linux"
    } else {
        "Unsupported development platform"
    }
}
