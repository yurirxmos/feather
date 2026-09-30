mod core;
mod credentials;
mod platform;
mod providers;

use platform::ProbeStatus;
use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WebviewWindow,
};

#[tauri::command]
fn probe_status() -> ProbeStatus {
    platform::probe_status()
}

#[tauri::command]
fn has_opencode_api_key() -> Result<bool, String> {
    credentials::has_opencode_api_key()
}

#[tauri::command]
fn save_opencode_api_key(api_key: String) -> Result<(), String> {
    credentials::save_opencode_api_key(&api_key)
}

#[tauri::command]
fn delete_opencode_api_key() -> Result<(), String> {
    credentials::delete_opencode_api_key()
}

#[tauri::command]
async fn generate_opencode(instruction: String) -> Result<String, String> {
    let api_key = credentials::opencode_api_key()?;
    providers::opencode_go::generate(&api_key, &instruction).await
}

#[tauri::command]
fn toggle_probe_window(window: WebviewWindow) -> Result<(), String> {
    if window.is_visible().map_err(|error| error.to_string())? {
        window.hide().map_err(|error| error.to_string())?;
    } else {
        window.show().map_err(|error| error.to_string())?;
        window.set_focus().map_err(|error| error.to_string())?;
    }
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let toggle = MenuItemBuilder::with_id("toggle", "Show or hide Feather").build(app)?;
            let quit = MenuItemBuilder::with_id("quit", "Quit Feather").build(app)?;
            let menu = MenuBuilder::new(app).items(&[&toggle, &quit]).build()?;

            TrayIconBuilder::new()
                .tooltip("Feather desktop probe")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "toggle" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = toggle_window(&window);
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        if let Some(window) = tray.app_handle().get_webview_window("main") {
                            let _ = window.unminimize();
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            probe_status,
            toggle_probe_window,
            has_opencode_api_key,
            save_opencode_api_key,
            delete_opencode_api_key,
            generate_opencode
        ])
        .run(tauri::generate_context!())
        .expect("Feather desktop failed to run");
}

fn toggle_window(window: &WebviewWindow) -> Result<(), String> {
    if window.is_visible().map_err(|error| error.to_string())? {
        window.hide().map_err(|error| error.to_string())?;
    } else {
        window.show().map_err(|error| error.to_string())?;
        window.set_focus().map_err(|error| error.to_string())?;
    }
    Ok(())
}
