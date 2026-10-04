//! Secrets in the operating system's credential store (Windows Credential Manager, or the Secret
//! Service on Linux), one entry per provider. They never reach the webview.

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

/// Windows Credential Manager rejects blobs over 2560 bytes, and the keyring stores them as UTF-16,
/// so a ChatGPT sign-in (two long tokens) does not fit in one entry. Longer values are split across
/// entries; the main entry then holds this marker and the number of chunks.
const CHUNK_MARKER: &str = "feather-chunks:";
const CHUNK_CHARACTERS: usize = 900;

fn chunk_account(account: &str, index: usize) -> String {
    format!("{account}#{index}")
}

fn split_chunks(value: &str) -> Vec<String> {
    let characters: Vec<char> = value.chars().collect();
    characters.chunks(CHUNK_CHARACTERS).map(|chunk| chunk.iter().collect()).collect()
}

fn chunk_count(stored: &str) -> Option<usize> {
    stored.strip_prefix(CHUNK_MARKER)?.parse().ok()
}

fn read_raw(account: &str) -> Option<String> {
    entry(account).ok()?.get_password().ok()
}

fn read(account: &str) -> Option<String> {
    let stored = read_raw(account)?;
    let value = match chunk_count(&stored) {
        Some(count) => (0..count).map(|index| read_raw(&chunk_account(account, index))).collect::<Option<String>>()?,
        None => stored,
    };
    Some(value).filter(|value| !value.trim().is_empty())
}

fn write(account: &str, value: &str) -> Result<(), String> {
    let failed = || t("Feather could not save the credential to secure storage.");
    let previous = read_raw(account).and_then(|stored| chunk_count(&stored)).unwrap_or(0);
    let chunks = split_chunks(value);
    if chunks.len() <= 1 {
        entry(account)?.set_password(value).map_err(|_| failed())?;
    } else {
        for (index, chunk) in chunks.iter().enumerate() {
            entry(&chunk_account(account, index))?.set_password(chunk).map_err(|_| failed())?;
        }
        entry(account)?.set_password(&format!("{CHUNK_MARKER}{}", chunks.len())).map_err(|_| failed())?;
    }
    // A shorter value than before leaves unused chunks behind.
    for index in chunks.len().max(1)..previous {
        delete_entry(&chunk_account(account, index));
    }
    Ok(())
}

fn delete_entry(account: &str) {
    // A missing entry is already deleted, and a failure leaves nothing more to do.
    if let Ok(entry) = entry(account) {
        let _ = entry.delete_credential();
    }
}

fn delete(account: &str) {
    let count = read_raw(account).and_then(|stored| chunk_count(&stored)).unwrap_or(0);
    for index in 0..count {
        delete_entry(&chunk_account(account, index));
    }
    delete_entry(account);
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
    use super::{chunk_count, masked, split_chunks, CHUNK_CHARACTERS, CHUNK_MARKER};

    #[test]
    fn masks_all_but_the_prefix() {
        assert_eq!(masked(" sk-abcdefghij "), "sk-abcdefg...");
        assert_eq!(masked("  "), "");
    }

    #[test]
    fn long_values_split_into_chunks_that_rejoin() {
        let value = "a".repeat(CHUNK_CHARACTERS * 2 + 5);
        let chunks = split_chunks(&value);
        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks.concat(), value);
        assert_eq!(split_chunks("short").len(), 1);
    }

    #[test]
    fn only_the_marker_counts_as_chunked() {
        assert_eq!(chunk_count(&format!("{CHUNK_MARKER}3")), Some(3));
        assert_eq!(chunk_count("sk-plain-key"), None);
    }
}
