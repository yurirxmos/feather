mod auth;
mod commands;
mod controller;
mod core;
mod credentials;
mod i18n;
mod insert;
// Only the stub for development machines leaves the shared helpers unused.
#[cfg_attr(not(windows), allow(dead_code))]
mod platform;
mod providers;
mod settings;
mod shell;

use tauri::{Manager, RunEvent, WindowEvent};

use controller::{PromptController, PANEL_LABEL};
use settings::SettingsStore;

pub fn run() {
    tauri::Builder::default()
        // A second launch opens Settings in the running instance instead of starting another one.
        .plugin(tauri_plugin_single_instance::init(|app, _, _| shell::show_settings(app)))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let settings_path = app.path().app_config_dir()?.join("settings.json");
            app.manage(SettingsStore::load(settings_path));
            app.manage(PromptController::new(app.handle().clone()));
            app.manage(commands::SignIn::default());
            platform::prepare();
            shell::build_tray(app.handle())?;
            shell::register_hotkey(app.handle());
            if !shell::has_credentials(app.handle()) {
                shell::show_settings(app.handle());
            }
            shell::check_for_updates(app.handle().clone(), false);
            Ok(())
        })
        .on_window_event(|window, event| match (window.label(), event) {
            (PANEL_LABEL, WindowEvent::Focused(false)) => {
                if window.is_visible().unwrap_or(false) {
                    window.state::<PromptController>().suspend_for_recapture();
                }
            }
            // Settings hides instead of closing, so Feather keeps running in the tray.
            (shell::SETTINGS_LABEL, WindowEvent::CloseRequested { api, .. }) => {
                api.prevent_close();
                let _ = window.hide();
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            commands::app_info,
            commands::get_settings,
            commands::set_setting,
            commands::credential_status,
            commands::save_api_key,
            commands::delete_api_key,
            commands::opencode_models,
            commands::sign_in_chatgpt,
            commands::disconnect_chatgpt,
            commands::sign_in_plus,
            commands::cancel_sign_in,
            commands::plus_account,
            commands::plus_sign_out,
            commands::open_plus_account_page,
            commands::capabilities,
            commands::check_for_updates,
            commands::quit,
            commands::prompt_state,
            commands::prompt_submit,
            commands::prompt_regenerate,
            commands::prompt_cancel_generation,
            commands::prompt_copy,
            commands::prompt_toggle_option,
            commands::prompt_dismiss,
            commands::panel_resize,
        ])
        .build(tauri::generate_context!())
        .expect("Feather failed to start")
        .run(|_, event| {
            // Feather lives in the tray; closing its last window must not quit it.
            if let RunEvent::ExitRequested { api, code: None, .. } = event {
                api.prevent_exit();
            }
        });
}
