//! Secrets in the operating system's credential store (Windows Credential Manager, or the Secret
//! Service on Linux), one entry per provider. They never reach the webview.

use keyring::Entry;
use crate::i18n::t;

const SERVICE: &str = "com.feather.desktop";
const OPENCODE_GO_ACCOUNT: &str = "opencode-go-api-key";
const CLAUDE_ACCOUNT: &str = "claude-api-key";
const OPENAI_ACCOUNT: &str = "openai-api-key";
/// The ChatGPT account session from before the OpenAI API key replaced it; only ever deleted.
const LEGACY_CHATGPT_ACCOUNT: &str = "chatgpt";
const FEATHER_PLUS_ACCOUNT: &str = "feather-plus";

fn entry(account: &str) -> Result<Entry, String> {
    Entry::new(SERVICE, account).map_err(|_| t("Secure credential storage is unavailable. Check that your system keyring is running."))
}

/// Windows Credential Manager rejects blobs over 2560 bytes, and the keyring stores them as UTF-16,
/// so a long token does not fit in one entry. Longer values are split across
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

pub fn claude_api_key() -> Option<String> {
    read(CLAUDE_ACCOUNT).map(|key| key.trim().to_owned())
}

pub fn set_claude_api_key(key: &str) -> Result<(), String> {
    let key = key.trim();
    if key.is_empty() {
        return Err(t("Enter an API key."));
    }
    write(CLAUDE_ACCOUNT, key)
}

pub fn delete_claude_api_key() {
    delete(CLAUDE_ACCOUNT);
}

pub fn openai_api_key() -> Option<String> {
    read(OPENAI_ACCOUNT).map(|key| key.trim().to_owned())
}

pub fn set_openai_api_key(key: &str) -> Result<(), String> {
    let key = key.trim();
    if key.is_empty() {
        return Err(t("Enter an API key."));
    }
    write(OPENAI_ACCOUNT, key)
}

pub fn delete_openai_api_key() {
    delete(OPENAI_ACCOUNT);
}

/// The ChatGPT account sign-in became an OpenAI API key; its leftover session is deleted at launch.
pub fn delete_legacy_chatgpt_session() {
    delete(LEGACY_CHATGPT_ACCOUNT);
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
