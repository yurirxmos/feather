mod auth;
mod commands;
mod controller;
mod core;
mod credentials;
mod i18n;
mod insert;
// Only the stub for development machines leaves the shared helpers unused.
#[cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]
mod platform;
mod providers;
mod settings;
mod shell;

use tauri::{Manager, RunEvent, WindowEvent};
use tauri_plugin_autostart::MacosLauncher;

use controller::{PromptController, PANEL_LABEL};
use settings::SettingsStore;

pub fn run() {
    tauri::Builder::default()
        // A second launch opens Settings in the running instance instead of starting another one. With
        // `--prompt` it opens the prompt, so a keyboard shortcut set in the desktop's own settings can
        // start Feather where Wayland gives apps no global shortcut of their own.
        .plugin(tauri_plugin_single_instance::init(|app, args, _| {
            if args.iter().any(|arg| arg == shell::PROMPT_FLAG) {
                shell::open_prompt(app);
            } else {
                shell::show_settings(app);
            }
        }))
        // Starts Feather in the tray at login: the registry on Windows, an XDG autostart entry on Linux.
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
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
            shell::enable_launch_at_login_by_default(app.handle());
            shell::register_hotkey(app.handle());
            if shell::needs_onboarding(app.handle()) || !shell::has_credentials(app.handle()) {
                shell::show_settings(app.handle());
            } else if std::env::args().any(|arg| arg == shell::PROMPT_FLAG) {
                shell::open_prompt(app.handle());
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
            commands::save_claude_api_key,
            commands::delete_claude_api_key,
            commands::claude_models,
            commands::chatgpt_models,
            commands::sign_in_chatgpt,
            commands::disconnect_chatgpt,
            commands::sign_in_plus,
            commands::cancel_sign_in,
            commands::plus_account,
            commands::plus_sign_out,
            commands::open_plus_page,
            commands::capabilities,
            commands::send_feedback,
            commands::close_feedback,
            commands::check_for_updates,
            commands::quit,
            commands::prompt_state,
            commands::prompt_browse,
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
