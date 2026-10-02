//! The IPC boundary. Credentials and captured content stay on this side: the webview only gets
//! masked keys, connection states, and what the panel renders.

use std::sync::{Arc, Mutex};

use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_opener::OpenerExt;
use tokio::sync::Notify;

use crate::auth;
use crate::controller::{PanelState, PromptController};
use crate::core::plus::PlusAccount;
use crate::credentials;
use crate::i18n;
use crate::platform::{self, Capability};
use crate::providers::catalog::{self, Model, CHATGPT_MODELS};
use crate::settings::{key, HotkeyPreset, Settings, SettingsStore};
use crate::shell::{self, ShellState};

/// Cancels the pending browser sign-in, if any.
#[derive(Default)]
pub struct SignIn(Mutex<Option<Arc<Notify>>>);

impl SignIn {
    fn begin(&self) -> Arc<Notify> {
        let notify = Arc::new(Notify::new());
        if let Some(previous) = self.0.lock().expect("sign-in lock").replace(notify.clone()) {
            previous.notify_one();
        }
        notify
    }
}

const CANCELLED: &str = "cancelled";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HotkeyOption {
    id: HotkeyPreset,
    label: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppInfo {
    locale: &'static str,
    platform: &'static str,
    version: String,
    hotkeys: Vec<HotkeyOption>,
    chatgpt_models: Vec<Model>,
}

#[tauri::command]
pub fn app_info(app: AppHandle) -> AppInfo {
    AppInfo {
        locale: i18n::locale(),
        platform: if cfg!(windows) { "windows" } else if cfg!(target_os = "linux") { "linux" } else { "other" },
        version: app.package_info().version.to_string(),
        hotkeys: HotkeyPreset::ALL.iter().map(|&id| HotkeyOption { id, label: id.label() }).collect(),
        chatgpt_models: CHATGPT_MODELS.to_vec(),
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsView {
    #[serde(flatten)]
    settings: Settings,
    hotkey_registered: bool,
}

fn settings_view(app: &AppHandle, settings: Settings) -> SettingsView {
    let hotkey_registered = *app.state::<ShellState>().hotkey_registered.lock().expect("shell lock");
    SettingsView { settings, hotkey_registered }
}

#[tauri::command]
pub fn get_settings(app: AppHandle, store: State<'_, SettingsStore>) -> SettingsView {
    settings_view(&app, store.current())
}

#[tauri::command]
pub fn set_setting(app: AppHandle, store: State<'_, SettingsStore>, name: String, value: Value) -> Result<SettingsView, String> {
    let settings = store.set(&name, value)?;
    if name == key::HOTKEY {
        shell::register_hotkey(&app);
    } else {
        let _ = app.emit("settings-changed", ());
    }
    Ok(settings_view(&app, settings))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CredentialStatus {
    api_key: Option<String>,
    chatgpt_connected: bool,
    plus_signed_in: bool,
}

#[tauri::command]
pub fn credential_status() -> CredentialStatus {
    CredentialStatus {
        api_key: credentials::api_key().map(|key| credentials::masked(&key)),
        chatgpt_connected: credentials::chatgpt_credentials().is_some(),
        plus_signed_in: credentials::plus_token().is_some(),
    }
}

#[tauri::command]
pub fn save_api_key(api_key: String) -> Result<CredentialStatus, String> {
    credentials::set_api_key(&api_key)?;
    Ok(credential_status())
}

#[tauri::command]
pub async fn opencode_models() -> Result<Vec<String>, String> {
    let api_key = credentials::api_key().ok_or_else(|| i18n::t("Add an API key in Settings."))?;
    catalog::fetch_opencode_models(&api_key).await.map_err(|error| error.message())
}

async fn cancellable<T>(sign_in: &SignIn, future: impl std::future::Future<Output = Result<T, String>>) -> Result<T, String> {
    let cancel = sign_in.begin();
    tokio::select! {
        result = future => result,
        _ = cancel.notified() => Err(CANCELLED.to_owned()),
    }
}

fn open_in_browser(app: &AppHandle) -> impl FnOnce(&str) + '_ {
    move |url| {
        let _ = app.opener().open_url(url, None::<&str>);
    }
}

#[tauri::command]
pub async fn sign_in_chatgpt(app: AppHandle, sign_in: State<'_, SignIn>) -> Result<CredentialStatus, String> {
    cancellable(&sign_in, auth::chatgpt::sign_in(open_in_browser(&app))).await?;
    Ok(credential_status())
}

#[tauri::command]
pub fn disconnect_chatgpt() -> CredentialStatus {
    credentials::delete_chatgpt_credentials();
    credential_status()
}

#[tauri::command]
pub async fn sign_in_plus(app: AppHandle, store: State<'_, SettingsStore>, sign_in: State<'_, SignIn>) -> Result<CredentialStatus, String> {
    let base = store.current().plus_base_url;
    cancellable(&sign_in, async { auth::plus::sign_in(&base, open_in_browser(&app)).await.map_err(|error| error.message()) }).await?;
    Ok(credential_status())
}

#[tauri::command]
pub fn cancel_sign_in(sign_in: State<'_, SignIn>) {
    if let Some(notify) = sign_in.0.lock().expect("sign-in lock").take() {
        notify.notify_one();
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlusAccountError {
    unauthorized: bool,
    message: String,
}

#[tauri::command]
pub async fn plus_account(store: State<'_, SettingsStore>) -> Result<Option<PlusAccount>, PlusAccountError> {
    let Some(token) = credentials::plus_token() else { return Ok(None) };
    match auth::plus::account(&store.current().plus_base_url, &token).await {
        Ok(account) => Ok(Some(account)),
        Err(error) => {
            let unauthorized = error == auth::plus::PlusError::Unauthorized;
            if unauthorized {
                credentials::delete_plus_token();
            }
            Err(PlusAccountError { unauthorized, message: error.message() })
        }
    }
}

#[tauri::command]
pub fn plus_sign_out(store: State<'_, SettingsStore>) -> CredentialStatus {
    auth::plus::sign_out(&store.current().plus_base_url);
    credential_status()
}

#[tauri::command]
pub fn open_plus_account_page(app: AppHandle, store: State<'_, SettingsStore>) -> Result<(), String> {
    let url = crate::core::plus::account_url(&store.current().plus_base_url).map_err(|error| error.message())?;
    app.opener().open_url(url, None::<&str>).map_err(|error| error.to_string())
}

#[tauri::command]
pub fn capabilities() -> Vec<Capability> {
    platform::capabilities()
}

#[tauri::command]
pub fn check_for_updates(app: AppHandle) {
    shell::check_for_updates(app, true);
}

#[tauri::command]
pub fn quit(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
pub fn prompt_state(controller: State<'_, PromptController>) -> PanelState {
    controller.state()
}

#[tauri::command]
pub fn prompt_submit(controller: State<'_, PromptController>, instruction: String) {
    controller.submit(&instruction);
}

#[tauri::command]
pub fn prompt_regenerate(controller: State<'_, PromptController>) {
    controller.regenerate();
}

#[tauri::command]
pub fn prompt_cancel_generation(controller: State<'_, PromptController>) {
    controller.cancel_generation();
}

#[tauri::command]
pub fn prompt_copy(controller: State<'_, PromptController>) {
    controller.copy_result();
}

#[tauri::command]
pub fn prompt_toggle_option(controller: State<'_, PromptController>, option: String) {
    controller.toggle_option(&option);
}

/// Escape hides the panel and keeps the session for a recapture.
#[tauri::command]
pub fn prompt_dismiss(controller: State<'_, PromptController>) {
    controller.suspend_for_recapture();
}

#[tauri::command]
pub fn panel_resize(controller: State<'_, PromptController>, height: f64) {
    controller.resize_panel(height);
}
