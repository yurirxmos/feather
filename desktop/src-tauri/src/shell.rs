//! The app around the panel: tray menu, global shortcut, Settings window, and updates. Mirrors
//! `AppDelegate` in the macOS app.

use std::sync::Mutex;

use tauri::image::Image;
use tauri::menu::{IconMenuItem, IconMenuItemBuilder, MenuBuilder};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager};
use serde_json::Value;
use tauri_plugin_autostart::ManagerExt as _;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
use tauri_plugin_updater::UpdaterExt;

use crate::controller::PromptController;
use crate::credentials;
use crate::i18n::t;
use crate::settings::{key, onboarding_completed, Connection, SettingsStore};

pub const SETTINGS_LABEL: &str = "settings";

/// The tray item whose title shows the current shortcut, and whether that shortcut is registered.
#[derive(Default)]
pub struct ShellState {
    open_item: Mutex<Option<IconMenuItem<tauri::Wry>>>,
    pub hotkey_registered: Mutex<bool>,
}

pub fn has_credentials(app: &AppHandle) -> bool {
    match app.state::<SettingsStore>().current().connection {
        Connection::OpenCodeGo => credentials::api_key().is_some(),
        Connection::ChatGpt => credentials::chatgpt_credentials().is_some(),
        Connection::FeatherPlus => credentials::plus_token().is_some(),
    }
}

/// Whether the first-run welcome guide is still pending. It runs once on every install.
pub fn needs_onboarding(app: &AppHandle) -> bool {
    !onboarding_completed(app.state::<SettingsStore>().current().onboarding_completed)
}

/// Feather starts at login unless the user turns it off. The default is applied once per install,
/// so turning it off in Settings or the system's startup apps sticks. Debug builds leave startup
/// alone. Mirrors `enableLaunchAtLoginByDefault` in the macOS app.
pub fn enable_launch_at_login_by_default(app: &AppHandle) {
    let store = app.state::<SettingsStore>();
    if cfg!(debug_assertions) || store.flag(key::LAUNCH_AT_LOGIN_DEFAULT_APPLIED).unwrap_or(false) {
        return;
    }
    let autolaunch = app.autolaunch();
    if autolaunch.is_enabled().unwrap_or(false) || autolaunch.enable().is_ok() {
        let _ = store.set(key::LAUNCH_AT_LOGIN_DEFAULT_APPLIED, Value::Bool(true));
    }
}

pub fn show_settings(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(SETTINGS_LABEL) {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// The command-line option that opens the prompt in the running Feather.
pub const PROMPT_FLAG: &str = "--prompt";

pub fn open_prompt(app: &AppHandle) {
    if !has_credentials(app) {
        show_settings(app);
        return;
    }
    app.state::<PromptController>().toggle();
}

pub fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    app.manage(ShellState::default());
    // Icons beside every item, the same glyphs as the macOS menu bar menu.
    let item = |id: &str, text: String, icon: &[u8]| -> tauri::Result<IconMenuItem<tauri::Wry>> {
        IconMenuItemBuilder::with_id(id, text).icon(Image::from_bytes(icon)?).build(app)
    };
    let open = item("open", open_title(app), include_bytes!("../icons/menu/open.png"))?;
    let settings = item("settings", t("Settings…"), include_bytes!("../icons/menu/settings.png"))?;
    let updates = item("updates", t("Check for Updates…"), include_bytes!("../icons/menu/updates.png"))?;
    let quit = item("quit", t("Quit"), include_bytes!("../icons/menu/quit.png"))?;
    let menu = MenuBuilder::new(app).item(&open).separator().item(&settings).item(&updates).separator().item(&quit).build()?;
    *app.state::<ShellState>().open_item.lock().expect("shell lock") = Some(open);

    let mut tray = TrayIconBuilder::with_id("feather").tooltip("Feather").menu(&menu).on_menu_event(|app, event| {
        match event.id().as_ref() {
            "open" => open_prompt(app),
            "settings" => show_settings(app),
            "updates" => check_for_updates(app.clone(), true),
            "quit" => app.exit(0),
            _ => {}
        }
    });
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.build(app)?;
    Ok(())
}

fn open_title(app: &AppHandle) -> String {
    let label = app.state::<SettingsStore>().current().hotkey.label();
    t("Open Feather ({shortcut})").replace("{shortcut}", label)
}

/// Registers the shortcut from Settings, replacing any earlier one.
pub fn register_hotkey(app: &AppHandle) {
    let shortcuts = app.global_shortcut();
    let _ = shortcuts.unregister_all();
    let accelerator = app.state::<SettingsStore>().current().hotkey.accelerator();
    let registered = shortcuts
        .on_shortcut(accelerator, |app, _, event| {
            if event.state == ShortcutState::Pressed {
                open_prompt(app);
            }
        })
        .is_ok();
    if !registered {
        eprintln!("Feather: could not register {accelerator}; another app may own it.");
    }
    let state = app.state::<ShellState>();
    *state.hotkey_registered.lock().expect("shell lock") = registered;
    if let Some(item) = state.open_item.lock().expect("shell lock").as_ref() {
        let _ = item.set_text(open_title(app));
    }
    let _ = app.emit("settings-changed", ());
}

/// Checks for an update and offers to install it. A background check stays silent unless it
/// finds one; a check the user asked for also reports that Feather is up to date or failed.
pub fn check_for_updates(app: AppHandle, interactive: bool) {
    tauri::async_runtime::spawn(async move {
        let result = match app.updater() {
            Ok(updater) => updater.check().await,
            Err(error) => Err(error),
        };
        match result {
            Ok(Some(update)) => {
                let message = t("Feather {version} is available. Install it now? Feather restarts when it finishes.")
                    .replace("{version}", &update.version);
                let app_for_install = app.clone();
                app.dialog()
                    .message(message)
                    .title("Feather")
                    .buttons(MessageDialogButtons::OkCancelCustom(t("Install"), t("Later")))
                    .show(move |install| {
                        if !install {
                            return;
                        }
                        tauri::async_runtime::spawn(async move {
                            match update.download_and_install(|_, _| {}, || {}).await {
                                Ok(()) => app_for_install.restart(),
                                Err(error) => {
                                    app_for_install
                                        .dialog()
                                        .message(t("The update could not be installed: {error}").replace("{error}", &error.to_string()))
                                        .kind(MessageDialogKind::Error)
                                        .title("Feather")
                                        .show(|_| {});
                                }
                            }
                        });
                    });
            }
            Ok(None) if interactive => {
                app.dialog().message(t("Feather is up to date.")).title("Feather").show(|_| {});
            }
            Err(error) if interactive => {
                app.dialog()
                    .message(t("Feather could not check for updates: {error}").replace("{error}", &error.to_string()))
                    .kind(MessageDialogKind::Error)
                    .title("Feather")
                    .show(|_| {});
            }
            _ => {}
        }
    });
}
