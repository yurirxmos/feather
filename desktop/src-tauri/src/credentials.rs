//! Secrets in the operating system's credential store (Windows Credential Manager), one entry per provider. They never reach the webview.

use keyring::Entry;
use serde::{Deserialize, Serialize};

use crate::i18n::t;

const SERVICE: &str = "com.feather.desktop";
const OPENCODE_GO_ACCOUNT: &str = "opencode-go-api-key";
const CHATGPT_ACCOUNT: &str = "chatgpt";
const FEATHER_PLUS_ACCOUNT: &str = "feather-plus";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatGptCredentials {
    pub access_token: String,
    pub refresh_token: String,
    /// Seconds since the Unix epoch.
    pub expires_at: u64,
    pub account_id: Option<String>,
}

fn entry(account: &str) -> Result<Entry, String> {
    Entry::new(SERVICE, account).map_err(|_| t("Secure credential storage is unavailable. Check that your system keyring is running."))
}

fn read(account: &str) -> Option<String> {
    entry(account).ok()?.get_password().ok().filter(|value| !value.trim().is_empty())
}

fn write(account: &str, value: &str) -> Result<(), String> {
    entry(account)?.set_password(value).map_err(|_| t("Feather could not save the credential to secure storage."))
}

fn delete(account: &str) {
    // A missing entry is already deleted, and a failure leaves nothing more to do.
    if let Ok(entry) = entry(account) {
        let _ = entry.delete_credential();
    }
}

pub fn api_key() -> Option<String> {
    read(OPENCODE_GO_ACCOUNT).map(|key| key.trim().to_owned())
}

pub fn set_api_key(key: &str) -> Result<(), String> {
    let key = key.trim();
    if key.is_empty() {
        return Err(t("Enter an API key."));
    }
    write(OPENCODE_GO_ACCOUNT, key)
}

pub fn delete_api_key() {
    delete(OPENCODE_GO_ACCOUNT);
}

pub fn chatgpt_credentials() -> Option<ChatGptCredentials> {
    serde_json::from_str(&read(CHATGPT_ACCOUNT)?).ok()
}

pub fn set_chatgpt_credentials(credentials: &ChatGptCredentials) -> Result<(), String> {
    write(CHATGPT_ACCOUNT, &serde_json::to_string(credentials).map_err(|error| error.to_string())?)
}

pub fn delete_chatgpt_credentials() {
    delete(CHATGPT_ACCOUNT);
}

pub fn plus_token() -> Option<String> {
    read(FEATHER_PLUS_ACCOUNT)
}

pub fn set_plus_token(token: &str) -> Result<(), String> {
    write(FEATHER_PLUS_ACCOUNT, token)
}

pub fn delete_plus_token() {
    delete(FEATHER_PLUS_ACCOUNT);
}

/// Shows the start of a key so the user can recognize it without revealing it.
pub fn masked(key: &str) -> String {
    let trimmed = key.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    format!("{}...", trimmed.chars().take(10).collect::<String>())
}

#[cfg(test)]
mod tests {
    use super::masked;

    #[test]
    fn masks_all_but_the_prefix() {
        assert_eq!(masked(" sk-abcdefghij "), "sk-abcdefg...");
        assert_eq!(masked("  "), "");
    }
}
