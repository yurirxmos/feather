//! Keeps Settings > Replies the same on every computer signed in to the account, mirroring
//! `ReplySettingsSync` in the macOS app. Signing in takes the account's settings, or saves this
//! computer's when the account has none. Each change is saved a moment after it is made, and the
//! account's are taken again at launch, when Settings opens, and at most once a minute when the
//! panel opens.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use tauri::{AppHandle, Emitter, Manager};

use crate::core::error::endpoint;
use crate::core::reply_settings::{self, ReplySettings, SyncAction};
use crate::credentials;
use crate::providers::stream::CLIENT;
use crate::settings::{key, SettingsStore};

const PATH: &str = "/v1/reply-settings";
/// Waits for typing to pause, so the instructions are saved once rather than per keystroke.
const UPLOAD_DELAY: Duration = Duration::from_millis(1500);
const PANEL_PULL_INTERVAL: Duration = Duration::from_secs(60);
const TIMEOUT: Duration = Duration::from_secs(15);

/// Moves on with every change, sign-in, and sign-out, so a delayed save or a pull that started
/// before gives way to what came after it.
static GENERATION: AtomicU64 = AtomicU64::new(0);
static PULLING: AtomicBool = AtomicBool::new(false);
static LAST_PULL: Mutex<Option<Instant>> = Mutex::new(None);

/// The settings in Settings > Replies.
pub fn is_reply_setting(name: &str) -> bool {
    matches!(name, key::CUSTOM_INSTRUCTIONS | key::INCLUDE_SCREENSHOT | key::REPLY_TONE | key::REPLY_LENGTH | key::REPLY_LANGUAGE)
}

/// A change in Settings > Replies, saved to the account once typing pauses. Changes made signed out
/// stay on this computer; signing in brings the account's.
pub fn changed(app: &AppHandle) {
    if credentials::plus_token().is_none() {
        return;
    }
    let _ = app.state::<SettingsStore>().set_flag(key::REPLY_SETTINGS_CHANGE_PENDING, true);
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(UPLOAD_DELAY).await;
        if GENERATION.load(Ordering::SeqCst) == generation {
            let settings = app.state::<SettingsStore>().reply_settings();
            upload(&app, settings).await;
        }
    });
}

/// Takes the account's settings. From the panel (`throttled`), at most once a minute.
pub fn pull(app: &AppHandle, throttled: bool) {
    if credentials::plus_token().is_none() {
        return;
    }
    {
        let mut last = LAST_PULL.lock().expect("pull lock");
        if throttled && last.is_some_and(|at| at.elapsed() < PANEL_PULL_INTERVAL) {
            return;
        }
        if PULLING.swap(true, Ordering::SeqCst) {
            return;
        }
        *last = Some(Instant::now());
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        fetch_and_merge(&app).await;
        PULLING.store(false, Ordering::SeqCst);
    });
}

/// A new sign-in: the account's settings win over this computer's.
pub fn signed_in(app: &AppHandle) {
    GENERATION.fetch_add(1, Ordering::SeqCst);
    let _ = app.state::<SettingsStore>().set_flag(key::REPLY_SETTINGS_CHANGE_PENDING, false);
    let app = app.clone();
    // Not through `pull`: one still running for an earlier account gives way to this one.
    tauri::async_runtime::spawn(async move { fetch_and_merge(&app).await });
}

/// Settings stay as they are; there is just nothing to save them to.
pub fn signed_out(app: &AppHandle) {
    GENERATION.fetch_add(1, Ordering::SeqCst);
    let _ = app.state::<SettingsStore>().set_flag(key::REPLY_SETTINGS_CHANGE_PENDING, false);
}

async fn fetch_and_merge(app: &AppHandle) {
    let generation = GENERATION.load(Ordering::SeqCst);
    let Some(token) = credentials::plus_token() else { return };
    let store = app.state::<SettingsStore>();
    let Ok(url) = endpoint(&store.current().plus_base_url, PATH) else { return };
    // Offline or failing, the settings stay as they are; the next pull tries again.
    let Ok(response) = CLIENT.get(url).bearer_auth(token).timeout(TIMEOUT).send().await else { return };
    if !response.status().is_success() {
        return;
    }
    let Ok(bytes) = response.bytes().await else { return };
    let Ok(remote) = reply_settings::decode(&bytes) else { return };
    if GENERATION.load(Ordering::SeqCst) != generation {
        return;
    }
    let pending = store.flag(key::REPLY_SETTINGS_CHANGE_PENDING).unwrap_or(false);
    match reply_settings::sync_action(store.reply_settings(), remote, pending) {
        SyncAction::None => {}
        SyncAction::Apply(settings) => {
            if store.store_reply_settings(&settings).is_ok() {
                let _ = app.emit("settings-changed", ());
            }
        }
        SyncAction::Upload(settings) => upload(app, settings).await,
    }
}

async fn upload(app: &AppHandle, settings: ReplySettings) {
    let Some(token) = credentials::plus_token() else { return };
    let store = app.state::<SettingsStore>();
    let Ok(url) = endpoint(&store.current().plus_base_url, PATH) else { return };
    // A failed save stays pending, so the next pull saves it instead of replacing it.
    let Ok(response) = CLIENT.put(url).bearer_auth(token).json(&settings).timeout(TIMEOUT).send().await else { return };
    // A change made while this one was on its way is still pending.
    if response.status().is_success() && store.reply_settings() == settings {
        let _ = store.set_flag(key::REPLY_SETTINGS_CHANGE_PENDING, false);
    }
}
