//! Non-secret settings, stored as JSON in the app's config directory under the same keys the macOS
//! app uses in `UserDefaults`. Secrets live in `credentials`.

use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::core::plus;
use crate::providers::default_model_for;

pub mod key {
    pub const CONNECTION: &str = "connection";
    pub const MODEL: &str = "model";
    pub const HOTKEY: &str = "hotkey";
    pub const INCLUDE_SCREENSHOT: &str = "includeScreenshot";
    pub const CUSTOM_INSTRUCTIONS: &str = "customInstructions";
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
    #[serde(rename = "chatGPT")]
    ChatGpt,
    #[serde(rename = "featherPlus")]
    FeatherPlus,
}

impl Connection {
    pub const ALL: [Connection; 3] = [Connection::OpenCodeGo, Connection::ChatGpt, Connection::FeatherPlus];
    /// The order Settings lists providers in and Feather falls back through, as
    /// `Settings.providerOrder` in the macOS app.
    pub const ORDER: [Connection; 3] = [Connection::FeatherPlus, Connection::ChatGpt, Connection::OpenCodeGo];
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

/// A resolved settings snapshot.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub connection: Connection,
    pub model: String,
    pub hotkey: HotkeyPreset,
    pub include_screenshot: bool,
    pub custom_instructions: String,
    pub plus_base_url: String,
    /// Whether Settings shows the Feather Plus pane.
    pub plus_enabled: bool,
    /// Whether Feather Plus can be chosen as the provider that generates replies.
    pub plus_provider_enabled: bool,
}

impl Settings {
    pub fn resolve(values: &Map<String, Value>) -> Settings {
        let string = |key: &str| values.get(key).and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
        let flag = |key: &str| values.get(key).and_then(Value::as_bool);

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
            plus_base_url: string(key::PLUS_BASE_URL).unwrap_or(plus::DEFAULT_BASE_URL).to_owned(),
            plus_enabled,
            plus_provider_enabled,
        }
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
            key::MODEL | key::CUSTOM_INSTRUCTIONS if value.is_string() => {}
            key::INCLUDE_SCREENSHOT if value.is_boolean() => {}
            _ => return Err(format!("{name} cannot be changed here.")),
        }
        values.insert(name.to_owned(), value);
        self.save(&values)?;
        Ok(Settings::resolve(&values))
    }

    fn save(&self, values: &Map<String, Value>) -> Result<(), String> {
        let write = || -> std::io::Result<()> {
            if let Some(directory) = self.path.parent() {
                std::fs::create_dir_all(directory)?;
            }
            let temporary = self.path.with_extension("json.tmp");
            std::fs::write(&temporary, serde_json::to_vec_pretty(values)?)?;
            std::fs::rename(temporary, &self.path)
        };
        write().map_err(|error| format!("Settings could not be saved: {error}"))
    }
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
    fn plus_placeholder_models_are_ignored_elsewhere() {
        let settings = resolve(json!({ "connection": "chatGPT", "model": "premium" }));
        assert_eq!(settings.model, crate::providers::catalog::CHATGPT_DEFAULT_MODEL);
        assert_eq!(resolve(json!({ "connection": "featherPlus", "model": "custom" })).model, plus::DEFAULT_MODEL);
    }

    #[test]
    fn switching_providers_keeps_only_custom_models() {
        assert_eq!(model_after_changing_to(Connection::ChatGpt, "my-model"), "my-model");
        assert_eq!(model_after_changing_to(Connection::ChatGpt, crate::providers::OPENCODE_GO_DEFAULT_MODEL), "gpt-5.4-mini");
        assert_eq!(model_after_changing_to(Connection::FeatherPlus, "my-model"), plus::DEFAULT_MODEL);
    }

    #[test]
    fn the_provider_in_use_stays_while_it_is_set_up() {
        let set_up = [Connection::ChatGpt, Connection::OpenCodeGo];
        assert_eq!(connection_after_setup_change(Connection::ChatGpt, &set_up, Some(Connection::OpenCodeGo)), Connection::ChatGpt);
    }

    #[test]
    fn the_first_provider_set_up_is_used() {
        assert_eq!(connection_after_setup_change(Connection::OpenCodeGo, &[Connection::ChatGpt], Some(Connection::ChatGpt)), Connection::ChatGpt);
    }

    #[test]
    fn removing_the_provider_in_use_falls_back_in_order() {
        let both = [Connection::OpenCodeGo, Connection::FeatherPlus];
        assert_eq!(connection_after_setup_change(Connection::ChatGpt, &both, None), Connection::FeatherPlus);
        assert_eq!(connection_after_setup_change(Connection::ChatGpt, &[Connection::OpenCodeGo], None), Connection::OpenCodeGo);
        assert_eq!(connection_after_setup_change(Connection::ChatGpt, &[], None), Connection::ChatGpt);
    }

    #[test]
    fn the_store_persists_and_rejects_unknown_keys() {
        let path = std::env::temp_dir().join(format!("feather-settings-{}.json", crate::core::pkce::random_string(8)));
        let store = SettingsStore::load(path.clone());
        store.set(key::CONNECTION, json!("chatGPT")).unwrap();
        store.set(key::INCLUDE_SCREENSHOT, json!(false)).unwrap();
        assert!(store.set(key::PLUS_BASE_URL, json!("http://evil")).is_err());

        let reloaded = SettingsStore::load(path.clone()).current();
        assert_eq!(reloaded.connection, Connection::ChatGpt);
        assert_eq!(reloaded.model, "gpt-5.4-mini");
        assert!(!reloaded.include_screenshot);
        let _ = std::fs::remove_file(path);
    }
}
