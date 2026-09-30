use keyring::{Entry, Error};

const SERVICE: &str = "com.feather.desktop";
const OPENCODE_GO_ACCOUNT: &str = "opencode-go-api-key";

fn opencode_entry() -> Result<Entry, String> {
    Entry::new(SERVICE, OPENCODE_GO_ACCOUNT).map_err(|_| {
        "Secure credential storage is unavailable. Check that your system keychain is running.".to_owned()
    })
}

pub fn has_opencode_api_key() -> Result<bool, String> {
    match opencode_entry()?.get_password() {
        Ok(key) => Ok(!key.trim().is_empty()),
        Err(Error::NoEntry) => Ok(false),
        Err(_) => Err("Feather could not read the OpenCode Go API key from secure storage.".to_owned()),
    }
}

pub fn save_opencode_api_key(api_key: &str) -> Result<(), String> {
    let api_key = api_key.trim();
    if api_key.is_empty() {
        return Err("Enter an OpenCode Go API key.".to_owned());
    }
    opencode_entry()?
        .set_password(api_key)
        .map_err(|_| "Feather could not save the OpenCode Go API key to secure storage.".to_owned())
}

pub fn delete_opencode_api_key() -> Result<(), String> {
    match opencode_entry()?.delete_credential() {
        Ok(()) | Err(Error::NoEntry) => Ok(()),
        Err(_) => Err("Feather could not remove the OpenCode Go API key from secure storage.".to_owned()),
    }
}
