//! Non-secret settings, stored as JSON in the app's config directory under the same keys the macOS
//! app uses in `UserDefaults`. Secrets live in `credentials`.

use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::core::plus;
use crate::core::reply_style::{Language, Length, ReplyStyle, Tone};
use crate::providers::default_model_for;

pub mod key {
    pub const CONNECTION: &str = "connection";
    pub const MODEL: &str = "model";
    pub const HOTKEY: &str = "hotkey";
    pub const INCLUDE_SCREENSHOT: &str = "includeScreenshot";
    pub const CUSTOM_INSTRUCTIONS: &str = "customInstructions";
    /// The Style choices in Settings > Replies; see `ReplyStyle`.
    pub const REPLY_TONE: &str = "replyTone";
    pub const REPLY_LENGTH: &str = "replyLength";
    pub const REPLY_LANGUAGE: &str = "replyLanguage";
    /// Whether the first-run welcome guide has been finished or dismissed. Absent until the guide has
    /// run once; `onboarding_completed` treats an absent value as not done.
    pub const ONBOARDING_COMPLETED: &str = "onboardingCompleted";
    /// Whether Feather has turned on starting at login, which it does once per install so that
    /// turning it off later sticks. Not shown in Settings.
    pub const LAUNCH_AT_LOGIN_DEFAULT_APPLIED: &str = "launchAtLoginDefaultApplied";
    /// Development override for the Feather Plus server. Not shown in Settings.
    pub const PLUS_BASE_URL: &str = "plusBaseURL";
    /// Shows Feather Plus in release builds before launch. Not shown in Settings.
    pub const PLUS_ENABLED: &str = "plusEnabled";
    /// Lets Feather Plus generate replies before that stage launches. Not shown in Settings.
    pub const PLUS_PROVIDER_ENABLED: &str = "plusProviderEnabled";
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum Connection {
    #[serde(rename = "openCodeGo")]
    OpenCodeGo,
    /// "chatGPT" was the ChatGPT account sign-in, which an OpenAI API key replaced, so a stored
    /// "chatGPT" now means OpenAI, which asks for a key until one is added.
    #[serde(rename = "openAI", alias = "chatGPT")]
    OpenAi,
    #[serde(rename = "claude")]
    Claude,
    #[serde(rename = "featherPlus")]
    FeatherPlus,
}

impl Connection {
    pub const ALL: [Connection; 4] = [Connection::OpenCodeGo, Connection::OpenAi, Connection::Claude, Connection::FeatherPlus];
    /// The order Settings lists providers in and Feather falls back through, as
    /// `Settings.providerOrder` in the macOS app.
    pub const ORDER: [Connection; 4] = [Connection::FeatherPlus, Connection::OpenAi, Connection::Claude, Connection::OpenCodeGo];
}

/// The provider to use after the set of providers that are set up changes. The one in use stays
/// while it is still set up; otherwise the one just set up (`preferred`), else the first one set up.
/// With none set up, nothing changes and Settings asks for attention. Mirrors
/// `Settings.connection(current:setUp:preferring:)` in the macOS app.
pub fn connection_after_setup_change(current: Connection, set_up: &[Connection], preferred: Option<Connection>) -> Connection {
    if set_up.contains(&current) {
        return current;
    }
    if let Some(preferred) = preferred.filter(|preferred| set_up.contains(preferred)) {
        return preferred;
    }
    Connection::ORDER.into_iter().find(|candidate| set_up.contains(candidate)).unwrap_or(current)
}

/// Shortcuts that do not collide with Windows or common Linux desktop bindings. macOS's ⌥ Space
/// would open the window menu on Windows.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum HotkeyPreset {
    ControlShiftSpace,
    ControlAltSpace,
    AltShiftSpace,
    ControlAltEnter,
}

impl HotkeyPreset {
    pub const ALL: [HotkeyPreset; 4] =
        [HotkeyPreset::ControlShiftSpace, HotkeyPreset::ControlAltSpace, HotkeyPreset::AltShiftSpace, HotkeyPreset::ControlAltEnter];

    /// The accelerator string `tauri-plugin-global-shortcut` parses.
    pub fn accelerator(self) -> &'static str {
        match self {
            HotkeyPreset::ControlShiftSpace => "Control+Shift+Space",
            HotkeyPreset::ControlAltSpace => "Control+Alt+Space",
            HotkeyPreset::AltShiftSpace => "Alt+Shift+Space",
            HotkeyPreset::ControlAltEnter => "Control+Alt+Enter",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            HotkeyPreset::ControlShiftSpace => "Ctrl+Shift+Space",
            HotkeyPreset::ControlAltSpace => "Ctrl+Alt+Space",
            HotkeyPreset::AltShiftSpace => "Alt+Shift+Space",
            HotkeyPreset::ControlAltEnter => "Ctrl+Alt+Enter",
        }
    }
}

/// Whether the welcome guide counts as done. An unset value is not done, so every install sees the
/// guide once, including ones that already have credentials. Mirrors
/// `Settings.onboardingCompleted(stored:)` in the macOS app.
pub fn onboarding_completed(stored: Option<bool>) -> bool {
    stored.unwrap_or(false)
}

/// A resolved settings snapshot.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub connection: Connection,
    pub model: String,
    pub hotkey: HotkeyPreset,
    pub include_screenshot: bool,
    pub custom_instructions: String,
    pub reply_tone: Tone,
    pub reply_length: Length,
    pub reply_language: Language,
    pub plus_base_url: String,
    /// Whether Settings shows the Feather Plus pane.
    pub plus_enabled: bool,
    /// Whether Feather Plus can be chosen as the provider that generates replies.
    pub plus_provider_enabled: bool,
    /// The stored welcome guide state, `None` until the guide is finished or dismissed.
    pub onboarding_completed: Option<bool>,
}

impl Settings {
    pub fn resolve(values: &Map<String, Value>) -> Settings {
        let string = |key: &str| values.get(key).and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
        let flag = |key: &str| values.get(key).and_then(Value::as_bool);
        // An unknown stored choice falls back to the default.
        fn choice<T: serde::de::DeserializeOwned + Default>(values: &Map<String, Value>, key: &str) -> T {
            values.get(key).and_then(|value| serde_json::from_value(value.clone()).ok()).unwrap_or_default()
        }

        let plus_enabled = cfg!(debug_assertions) || plus::ACCOUNTS_LAUNCHED || flag(key::PLUS_ENABLED).unwrap_or(false);
        let plus_provider_enabled =
            plus_enabled && (plus::PROVIDER_LAUNCHED || flag(key::PLUS_PROVIDER_ENABLED).unwrap_or(false));

        let mut connection = values
            .get(key::CONNECTION)
            .and_then(|value| serde_json::from_value(value.clone()).ok())
            .unwrap_or(Connection::OpenCodeGo);
        // A stored Feather Plus choice is ignored while that stage is off.
        if connection == Connection::FeatherPlus && !plus_provider_enabled {
            connection = Connection::OpenCodeGo;
        }
        let mut model = string(key::MODEL);
        // Feather Plus picks its own model, and its placeholder names mean nothing elsewhere.
        if connection == Connection::FeatherPlus || model.is_some_and(plus::is_plus_model) {
            model = None;
        }

        Settings {
            connection,
            model: model.unwrap_or(default_model_for(connection)).to_owned(),
            hotkey: values
                .get(key::HOTKEY)
                .and_then(|value| serde_json::from_value(value.clone()).ok())
                .unwrap_or(HotkeyPreset::ControlShiftSpace),
            include_screenshot: flag(key::INCLUDE_SCREENSHOT).unwrap_or(true),
            custom_instructions: string(key::CUSTOM_INSTRUCTIONS).unwrap_or_default().to_owned(),
            reply_tone: choice(values, key::REPLY_TONE),
            reply_length: choice(values, key::REPLY_LENGTH),
            reply_language: choice(values, key::REPLY_LANGUAGE),
            plus_base_url: string(key::PLUS_BASE_URL).unwrap_or(plus::DEFAULT_BASE_URL).to_owned(),
            plus_enabled,
            plus_provider_enabled,
            onboarding_completed: flag(key::ONBOARDING_COMPLETED),
        }
    }
}

impl Settings {
    pub fn reply_style(&self) -> ReplyStyle {
        ReplyStyle { tone: self.reply_tone, length: self.reply_length, language: self.reply_language }
    }
}

/// Feather Plus always uses its own model, and its placeholder names mean nothing to other
/// providers, so no model survives a switch to or from it. Other custom models are kept.
pub fn model_after_changing_to(connection: Connection, model: &str) -> String {
    if connection == Connection::FeatherPlus
        || plus::is_plus_model(model)
        || Connection::ALL.iter().any(|candidate| default_model_for(*candidate) == model)
    {
        return default_model_for(connection).to_owned();
    }
    model.to_owned()
}

pub struct SettingsStore {
    path: PathBuf,
    values: Mutex<Map<String, Value>>,
}

impl SettingsStore {
    pub fn load(path: PathBuf) -> Self {
        let values = std::fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Map<String, Value>>(&bytes).ok())
            .unwrap_or_default();
        Self { path, values: Mutex::new(values) }
    }

    pub fn current(&self) -> Settings {
        Settings::resolve(&self.values.lock().expect("settings lock"))
    }

    /// A stored flag that `Settings` does not expose, such as `LAUNCH_AT_LOGIN_DEFAULT_APPLIED`.
    pub fn flag(&self, name: &str) -> Option<bool> {
        self.values.lock().expect("settings lock").get(name).and_then(Value::as_bool)
    }

    /// Changes one user-editable setting. Switching providers also resets a model that only made
    /// sense for the previous one.
    pub fn set(&self, name: &str, value: Value) -> Result<Settings, String> {
        let mut values = self.values.lock().expect("settings lock");
        match name {
            key::CONNECTION => {
                let connection: Connection = serde_json::from_value(value.clone()).map_err(|_| "Unknown provider.".to_owned())?;
                let model = Settings::resolve(&values).model;
                values.insert(key::MODEL.into(), Value::String(model_after_changing_to(connection, &model)));
            }
            key::HOTKEY => {
                serde_json::from_value::<HotkeyPreset>(value.clone()).map_err(|_| "Unknown shortcut.".to_owned())?;
            }
            key::REPLY_TONE => {
                serde_json::from_value::<Tone>(value.clone()).map_err(|_| "Unknown tone.".to_owned())?;
            }
            key::REPLY_LENGTH => {
                serde_json::from_value::<Length>(value.clone()).map_err(|_| "Unknown length.".to_owned())?;
            }
            key::REPLY_LANGUAGE => {
                serde_json::from_value::<Language>(value.clone()).map_err(|_| "Unknown language.".to_owned())?;
            }
            key::MODEL | key::CUSTOM_INSTRUCTIONS if value.is_string() => {}
            key::INCLUDE_SCREENSHOT | key::ONBOARDING_COMPLETED | key::LAUNCH_AT_LOGIN_DEFAULT_APPLIED if value.is_boolean() => {}
            _ => return Err(format!("{name} cannot be changed here.")),
        }
        values.insert(name.to_owned(), value);
        self.save(&values)?;
        Ok(Settings::resolve(&values))
    }

    fn save(&self, values: &Map<String, Value>) -> Result<(), String> {
        serde_json::to_vec_pretty(values)
            .map_err(std::io::Error::from)
            .and_then(|data| write_atomically(&self.path, &data))
            .map_err(|error| format!("Settings could not be saved: {error}"))
    }
}

/// Writes through a temporary file, so a crash never leaves half a file behind.
pub fn write_atomically(path: &std::path::Path, data: &[u8]) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let temporary = path.with_extension("json.tmp");
    std::fs::write(&temporary, data)?;
    std::fs::rename(&temporary, path)
}


#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn resolve(value: Value) -> Settings {
        Settings::resolve(value.as_object().unwrap())
    }

    #[test]
    fn defaults_match_the_macos_app() {
        let settings = resolve(json!({}));
        assert_eq!(settings.connection, Connection::OpenCodeGo);
        assert_eq!(settings.model, crate::providers::OPENCODE_GO_DEFAULT_MODEL);
        assert!(settings.include_screenshot);
        assert_eq!(settings.hotkey, HotkeyPreset::ControlShiftSpace);
    }

    #[test]
    fn reply_style_reads_stored_choices_and_ignores_unknown_ones() {
        assert_eq!(resolve(json!({})).reply_style(), ReplyStyle::default());
        let settings = resolve(json!({ "replyTone": "casual", "replyLength": "detailed", "replyLanguage": "klingon" }));
        assert_eq!(settings.reply_style(), ReplyStyle { tone: Tone::Casual, length: Length::Detailed, language: Language::Conversation });
    }

    #[test]
    fn onboarding_runs_once_for_every_install() {
        assert!(!onboarding_completed(None));
        assert!(!onboarding_completed(Some(false)));
        assert!(onboarding_completed(Some(true)));
    }

    #[test]
    fn plus_placeholder_models_are_ignored_elsewhere() {
        let settings = resolve(json!({ "connection": "openAI", "model": "premium" }));
        assert_eq!(settings.model, crate::providers::OPENAI_DEFAULT_MODEL);
        let tester = json!({ "connection": "featherPlus", "model": "custom", "plusProviderEnabled": true });
        assert_eq!(resolve(tester).model, plus::DEFAULT_MODEL);
    }

    #[test]
    fn the_chatgpt_sign_in_choice_becomes_openai() {
        assert_eq!(resolve(json!({ "connection": "chatGPT" })).connection, Connection::OpenAi);
        assert_eq!(serde_json::to_value(Connection::OpenAi).unwrap(), json!("openAI"));
    }

    #[test]
    fn a_stored_plus_choice_is_kept_now_that_plus_launched() {
        const { assert!(plus::PROVIDER_LAUNCHED) };
        assert_eq!(resolve(json!({ "connection": "featherPlus" })).connection, Connection::FeatherPlus);
    }

    #[test]
    fn switching_providers_keeps_only_custom_models() {
        assert_eq!(model_after_changing_to(Connection::OpenAi, "my-model"), "my-model");
        assert_eq!(model_after_changing_to(Connection::OpenAi, crate::providers::OPENCODE_GO_DEFAULT_MODEL), "gpt-5.4-mini");
        assert_eq!(model_after_changing_to(Connection::FeatherPlus, "my-model"), plus::DEFAULT_MODEL);
    }

    #[test]
    fn the_provider_in_use_stays_while_it_is_set_up() {
        let set_up = [Connection::OpenAi, Connection::OpenCodeGo];
        assert_eq!(connection_after_setup_change(Connection::OpenAi, &set_up, Some(Connection::OpenCodeGo)), Connection::OpenAi);
    }

    #[test]
    fn the_first_provider_set_up_is_used() {
        assert_eq!(connection_after_setup_change(Connection::OpenCodeGo, &[Connection::OpenAi], Some(Connection::OpenAi)), Connection::OpenAi);
    }

    #[test]
    fn removing_the_provider_in_use_falls_back_in_order() {
        let both = [Connection::OpenCodeGo, Connection::FeatherPlus];
        assert_eq!(connection_after_setup_change(Connection::OpenAi, &both, None), Connection::FeatherPlus);
        assert_eq!(connection_after_setup_change(Connection::OpenAi, &[Connection::OpenCodeGo], None), Connection::OpenCodeGo);
        assert_eq!(connection_after_setup_change(Connection::OpenAi, &[], None), Connection::OpenAi);
    }

    #[test]
    fn the_store_persists_and_rejects_unknown_keys() {
        let path = std::env::temp_dir().join(format!("feather-settings-{}.json", crate::core::pkce::random_string(8)));
        let store = SettingsStore::load(path.clone());
        store.set(key::CONNECTION, json!("openAI")).unwrap();
        store.set(key::INCLUDE_SCREENSHOT, json!(false)).unwrap();
        assert!(store.set(key::PLUS_BASE_URL, json!("http://evil")).is_err());

        let reloaded = SettingsStore::load(path.clone()).current();
        assert_eq!(reloaded.connection, Connection::OpenAi);
        assert_eq!(reloaded.model, "gpt-5.4-mini");
        assert!(!reloaded.include_screenshot);
        let _ = std::fs::remove_file(path);
    }
}
