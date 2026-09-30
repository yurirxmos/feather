mod platform;

use platform::ProbeStatus;
use tauri::WebviewWindow;

#[tauri::command]
fn probe_status() -> ProbeStatus {
    platform::probe_status()
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
        .invoke_handler(tauri::generate_handler![probe_status, toggle_probe_window])
        .run(tauri::generate_context!())
        .expect("Feather desktop failed to run");
}
