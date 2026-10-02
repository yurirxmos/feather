//! PKCE and token helpers shared by the ChatGPT and Feather Plus sign-ins.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use sha2::{Digest, Sha256};

/// `length` random bytes as lowercase hex.
pub fn random_string(length: usize) -> String {
    let mut bytes = vec![0u8; length];
    getrandom::getrandom(&mut bytes).expect("the operating system's random source is unavailable");
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub fn code_challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

/// Reads the ChatGPT account ID from an OpenAI access or ID token.
pub fn chatgpt_account_id(token: &str) -> Option<String> {
    let mut parts = token.split('.');
    let payload = match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some(_), Some(payload), Some(_), None) => payload,
        _ => return None,
    };
    let json: serde_json::Value = serde_json::from_slice(&URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?).ok()?;
    json.get("chatgpt_account_id")
        .or_else(|| json.pointer("/https:~1~1api.openai.com~1auth/chatgpt_account_id"))
        .or_else(|| json.pointer("/organizations/0/id"))
        .and_then(|value| value.as_str())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn challenge_matches_rfc_7636_example() {
        assert_eq!(
            code_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
    }

    #[test]
    fn random_strings_are_hex_of_the_requested_length() {
        let value = random_string(32);
        assert_eq!(value.len(), 64);
        assert!(value.chars().all(|character| character.is_ascii_hexdigit()));
    }

    #[test]
    fn reads_the_account_id_from_the_auth_claim() {
        let payload = URL_SAFE_NO_PAD.encode(r#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct"}}"#);
        assert_eq!(chatgpt_account_id(&format!("h.{payload}.s")).as_deref(), Some("acct"));
        assert_eq!(chatgpt_account_id("not-a-jwt"), None);
    }
}
