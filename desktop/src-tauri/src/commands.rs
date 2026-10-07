//! The IPC boundary. Credentials and captured content stay on this side: the webview only gets
//! masked keys, connection states, and what the panel renders.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_autostart::ManagerExt as _;
use tauri_plugin_opener::OpenerExt;
use tokio::sync::Notify;

use crate::auth;
use crate::controller::{PanelState, PromptController};
use crate::core::feedback::{self, Outcome};
use crate::core::plus::PlusAccount;
use crate::core::recent::Direction;
use crate::credentials;
use crate::i18n;
use crate::platform::{self, Capability};
use crate::providers::catalog::{self, ChatGptModel, Model, CHATGPT_MODELS};
use crate::providers::stream::CLIENT;
use crate::settings::{connection_after_setup_change, key, Connection, HotkeyPreset, Settings, SettingsStore};
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
    /// On Linux, the display server: `x11`, `wayland`, or `unknown`.
    session: Option<&'static str>,
    version: String,
    hotkeys: Vec<HotkeyOption>,
    chatgpt_models: Vec<Model>,
}

#[tauri::command]
pub fn app_info(app: AppHandle) -> AppInfo {
    AppInfo {
        locale: i18n::locale(),
        platform: platform::name(),
        session: platform::session_name(),
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
    /// Whether the system starts Feather at login. The system holds this, not the settings file, so
    /// it stays right when the user removes the entry elsewhere.
    launch_at_login: bool,
}

fn settings_view(app: &AppHandle, settings: Settings) -> SettingsView {
    let hotkey_registered = *app.state::<ShellState>().hotkey_registered.lock().expect("shell lock");
    let launch_at_login = app.autolaunch().is_enabled().unwrap_or(false);
    SettingsView { settings, hotkey_registered, launch_at_login }
}

/// The setting name the webview uses for starting at login, which `set_setting` routes to the
/// system instead of the settings file, as `SMAppService` does in the macOS app.
const LAUNCH_AT_LOGIN: &str = "launchAtLogin";

#[tauri::command]
pub fn get_settings(app: AppHandle, store: State<'_, SettingsStore>) -> SettingsView {
    settings_view(&app, store.current())
}

#[tauri::command]
pub fn set_setting(app: AppHandle, store: State<'_, SettingsStore>, name: String, value: Value) -> Result<SettingsView, String> {
    if name == LAUNCH_AT_LOGIN {
        let enabled = value.as_bool().ok_or_else(|| format!("{name} must be true or false."))?;
        let autolaunch = app.autolaunch();
        let result = if enabled { autolaunch.enable() } else { autolaunch.disable() };
        result.map_err(|error| i18n::t("Feather could not change whether it starts at login: {error}").replace("{error}", &error.to_string()))?;
        return Ok(settings_view(&app, store.current()));
    }
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

/// Set while switching Feather Plus accounts, so Feather Plus is in use again once the new
/// account signs in.
static SWITCHING_PLUS_ACCOUNTS: AtomicBool = AtomicBool::new(false);

/// The providers that have credentials. Feather Plus counts once signed in, plan or not.
fn providers_set_up(settings: &Settings) -> Vec<Connection> {
    let mut set_up = Vec::new();
    if credentials::api_key().is_some() {
        set_up.push(Connection::OpenCodeGo);
    }
    if credentials::chatgpt_credentials().is_some() {
        set_up.push(Connection::ChatGpt);
    }
    if settings.plus_provider_enabled && credentials::plus_token().is_some() {
        set_up.push(Connection::FeatherPlus);
    }
    set_up
}

/// After credentials change, keeps the provider in use or moves to one that is set up, and tells
/// the windows when that changes the settings.
fn credentials_changed(app: &AppHandle, store: &SettingsStore, preferred: Option<Connection>) {
    let settings = store.current();
    let set_up = providers_set_up(&settings);
    let mut next = connection_after_setup_change(settings.connection, &set_up, preferred);
    if set_up.contains(&Connection::FeatherPlus) && SWITCHING_PLUS_ACCOUNTS.swap(false, Ordering::Relaxed) {
        next = Connection::FeatherPlus;
    }
    if next != settings.connection && store.set(key::CONNECTION, serde_json::to_value(next).expect("connection")).is_ok() {
        let _ = app.emit("settings-changed", ());
    }
}

#[tauri::command]
pub fn save_api_key(app: AppHandle, store: State<'_, SettingsStore>, api_key: String) -> Result<CredentialStatus, String> {
    credentials::set_api_key(&api_key)?;
    credentials_changed(&app, &store, Some(Connection::OpenCodeGo));
    Ok(credential_status())
}

#[tauri::command]
pub fn delete_api_key(app: AppHandle, store: State<'_, SettingsStore>) -> CredentialStatus {
    credentials::delete_api_key();
    credentials_changed(&app, &store, None);
    credential_status()
}

#[tauri::command]
pub async fn opencode_models() -> Result<Vec<String>, String> {
    let api_key = credentials::api_key().ok_or_else(|| i18n::t("Add an API key in Settings."))?;
    catalog::fetch_opencode_models(&api_key).await.map_err(|error| error.message())
}

/// Loads the models the ChatGPT account can use and, when ChatGPT is in use, moves a selection the
/// account lacks to one it has, so a reply never asks for a model the account cannot run.
async fn load_chatgpt_models(app: &AppHandle, store: &SettingsStore) -> Result<Vec<ChatGptModel>, String> {
    let credentials = auth::chatgpt::valid_credentials().await?;
    let models = catalog::fetch_chatgpt_models(&credentials.access_token, credentials.account_id.as_deref())
        .await
        .map_err(|error| error.message())?;
    let settings = store.current();
    if settings.connection == Connection::ChatGpt {
        if let Some(model) = catalog::chatgpt_model_for_account(&models, &settings.model) {
            if model != settings.model && store.set(key::MODEL, Value::String(model)).is_ok() {
                let _ = app.emit("settings-changed", ());
            }
        }
    }
    Ok(models)
}

#[tauri::command]
pub async fn chatgpt_models(app: AppHandle, store: State<'_, SettingsStore>) -> Result<Vec<ChatGptModel>, String> {
    load_chatgpt_models(&app, &store).await
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
pub async fn sign_in_chatgpt(app: AppHandle, store: State<'_, SettingsStore>, sign_in: State<'_, SignIn>) -> Result<CredentialStatus, String> {
    cancellable(&sign_in, auth::chatgpt::sign_in(open_in_browser(&app))).await?;
    credentials_changed(&app, &store, Some(Connection::ChatGpt));
    // Best effort: Settings loads the list again, and the built-in one covers a failure.
    let _ = load_chatgpt_models(&app, &store).await;
    Ok(credential_status())
}

#[tauri::command]
pub fn disconnect_chatgpt(app: AppHandle, store: State<'_, SettingsStore>) -> CredentialStatus {
    credentials::delete_chatgpt_credentials();
    credentials_changed(&app, &store, None);
    credential_status()
}

#[tauri::command]
pub async fn sign_in_plus(app: AppHandle, store: State<'_, SettingsStore>, sign_in: State<'_, SignIn>) -> Result<CredentialStatus, String> {
    let base = store.current().plus_base_url;
    cancellable(&sign_in, async { auth::plus::sign_in(&base, open_in_browser(&app)).await.map_err(|error| error.message()) }).await?;
    credentials_changed(&app, &store, Some(Connection::FeatherPlus));
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
pub async fn plus_account(app: AppHandle, store: State<'_, SettingsStore>) -> Result<Option<PlusAccount>, PlusAccountError> {
    let Some(token) = credentials::plus_token() else { return Ok(None) };
    match auth::plus::account(&store.current().plus_base_url, &token).await {
        Ok(account) => Ok(Some(account)),
        Err(error) => {
            let unauthorized = error == auth::plus::PlusError::Unauthorized;
            if unauthorized {
                credentials::delete_plus_token();
                credentials_changed(&app, &store, None);
            }
            Err(PlusAccountError { unauthorized, message: error.message() })
        }
    }
}

#[tauri::command]
pub fn plus_sign_out(app: AppHandle, store: State<'_, SettingsStore>) -> CredentialStatus {
    SWITCHING_PLUS_ACCOUNTS.store(store.current().connection == Connection::FeatherPlus, Ordering::Relaxed);
    auth::plus::sign_out(&store.current().plus_base_url);
    credentials_changed(&app, &store, None);
    credential_status()
}

/// Opens the website's plans (`pricing`) or account page (`account`), signed in to the app's
/// account when there is one.
#[tauri::command]
pub async fn open_plus_page(app: AppHandle, store: State<'_, SettingsStore>, page: String) -> Result<(), String> {
    let base = store.current().plus_base_url;
    let path = if page == "pricing" { crate::core::plus::PRICING_PATH } else { crate::core::plus::ACCOUNT_PATH };
    let code = auth::plus::web_code(&base).await;
    let url = crate::core::plus::website_url(&base, path, code.as_deref()).map_err(|error| error.message())?;
    app.opener().open_url(url, None::<&str>).map_err(|error| error.to_string())
}

#[tauri::command]
pub fn capabilities() -> Vec<Capability> {
    platform::capabilities()
}

/// Sends feedback through `feather-api`. Fails with a message to show under the form.
#[tauri::command]
pub async fn send_feedback(app: AppHandle, store: State<'_, SettingsStore>, message: String, email: String) -> Result<(), String> {
    if !feedback::can_send(&message) {
        return Err(i18n::t("Keep your message under 5,000 characters."));
    }
    let platform = match (platform::name(), platform::session_name()) {
        ("windows", _) => "Windows".to_owned(),
        ("linux", Some(session)) => format!("Linux ({session})"),
        ("linux", None) => "Linux".to_owned(),
        (other, _) => other.to_owned(),
    };
    let version = app.package_info().version.to_string();
    let body = feedback::body(&message, &email, &version, &platform);
    let outcome = match feedback::url(&store.current().plus_base_url) {
        Ok(url) => match CLIENT.post(url).json(&body).timeout(Duration::from_secs(20)).send().await {
            Ok(response) => feedback::outcome(response.status().as_u16()),
            Err(_) => Outcome::Failed,
        },
        Err(_) => Outcome::Failed,
    };
    match outcome {
        Outcome::Sent => Ok(()),
        Outcome::Invalid => Err(i18n::t("Check the email address, or leave it empty.")),
        Outcome::RateLimited => Err(i18n::t("You've sent a lot of feedback today. Try again tomorrow.")),
        Outcome::Failed => Err(i18n::t("Couldn't send your feedback. Check your connection and try again.")),
    }
}

#[tauri::command]
pub fn close_feedback(app: AppHandle) {
    shell::close_feedback(&app);
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
pub fn prompt_browse(controller: State<'_, PromptController>, direction: Direction) {
    controller.browse(direction);
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
