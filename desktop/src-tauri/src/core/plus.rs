//! Client side of Feather Plus, the hosted plans served by `feather-api`. Mirrors `FeatherPlus`
//! in the macOS app.
//!
//! Sign-in is an OAuth-style authorization code flow with PKCE over a loopback redirect: the
//! browser returns a short-lived code to `http://127.0.0.1:<port>/callback`, and the app exchanges
//! it for a long-lived account token stored in the system credential store.

use serde::Serialize;
use serde_json::Value;

use super::error::{endpoint, LlmError};

/// Every build talks to production; set the `plusBaseURL` setting to use `wrangler dev`
/// (`http://127.0.0.1:8787`) in `feather-api` instead.
pub const DEFAULT_BASE_URL: &str = "https://feather-api.rxmos.dev";
pub const CALLBACK_PATH: &str = "/callback";

// Feather Plus rolls out in two stages: accounts (sign-in, plan, usage), then generating through
// it. Both are on; whether new subscriptions can start is decided on the server (feather-web's
// /admin), so the app never needs a release to open or close sales.
pub const ACCOUNTS_LAUNCHED: bool = true;
pub const PROVIDER_LAUNCHED: bool = true;

/// The placeholder model sent to Feather Plus; the server picks the real one.
pub const DEFAULT_MODEL: &str = "fast";
/// Model names only Feather Plus used. `premium` was a tier that plans no longer have.
pub fn is_plus_model(model: &str) -> bool {
    matches!(model, "fast" | "premium")
}

pub fn redirect_uri(port: u16) -> String {
    format!("http://127.0.0.1:{port}{CALLBACK_PATH}")
}

pub fn authorize_url(base: &str, redirect_uri: &str, state: &str, code_challenge: &str) -> Result<String, LlmError> {
    let mut url = endpoint(base, "/auth/authorize")?;
    url.query_pairs_mut()
        .append_pair("response_type", "code")
        .append_pair("redirect_uri", redirect_uri)
        .append_pair("state", state)
        .append_pair("code_challenge", code_challenge)
        .append_pair("code_challenge_method", "S256");
    Ok(url.into())
}

/// The page where a signed-in user picks, changes, or cancels a plan.
pub fn account_url(base: &str) -> Result<String, LlmError> {
    Ok(endpoint(base, "/account")?.into())
}

/// Extracts the authorization code from a loopback request target such as
/// `/callback?code=…&state=…`. Returns `None` for other paths or a mismatched state.
pub fn authorization_code(target: &str, expected_state: &str) -> Option<String> {
    let url = reqwest::Url::parse(&format!("http://127.0.0.1{target}")).ok()?;
    if url.path() != CALLBACK_PATH {
        return None;
    }
    let query = |name: &str| url.query_pairs().find(|(key, _)| key == name).map(|(_, value)| value.into_owned());
    if query("state")?.as_str() != expected_state {
        return None;
    }
    query("code").filter(|code| !code.is_empty())
}

pub fn decode_token(body: &[u8]) -> Result<String, LlmError> {
    let json: Value = serde_json::from_slice(body).map_err(|_| LlmError::Api("The server returned an unreadable token.".into()))?;
    json.get("token")
        .and_then(Value::as_str)
        .filter(|token| !token.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| LlmError::Api("The server returned an empty token.".into()))
}

/// Model cost spent and allowed this month, in millionths of a US dollar. Shown as a share used,
/// never as money.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Usage {
    pub used: u64,
    pub limit: u64,
    /// The share of the allowance spent, as a whole percentage from 0 to 100.
    pub percent_used: u64,
}

impl Usage {
    pub fn new(used: u64, limit: u64) -> Self {
        let percent_used = ((used as f64 / limit.max(1) as f64) * 100.0).round().min(100.0) as u64;
        Self { used, limit, percent_used }
    }
}

/// The signed-in account as reported by `GET /v1/account`.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlusAccount {
    pub email: String,
    /// `monthly` or `yearly`; `None` when the account has no active subscription or the server sent
    /// a plan this version does not know.
    pub plan: Option<String>,
    /// The server sends one entry while a plan is active.
    pub usage: Vec<Usage>,
    /// When the current quota period resets, as an ISO 8601 date.
    pub period_end: Option<String>,
}

pub fn decode_account(body: &[u8]) -> Result<PlusAccount, LlmError> {
    let unreadable = || LlmError::Api("Feather Plus returned an unreadable account.".into());
    let json: Value = serde_json::from_slice(body).map_err(|_| unreadable())?;
    let email = json.get("email").and_then(Value::as_str).ok_or_else(unreadable)?.to_owned();
    let plan = json
        .get("plan")
        .and_then(Value::as_str)
        .filter(|plan| matches!(*plan, "monthly" | "yearly"))
        .map(str::to_owned);
    // Malformed usage rows are skipped instead of failing the whole account.
    let usage = json
        .get("usage")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|row| Some(Usage::new(row.get("used")?.as_u64()?, row.get("limit")?.as_u64()?)))
        .take(1)
        .collect();
    let period_end = json.get("period_end").and_then(Value::as_str).map(str::to_owned);
    Ok(PlusAccount { email, plan, usage, period_end })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authorize_url_carries_the_pkce_parameters() {
        let url = authorize_url("https://api.example.com/", "http://127.0.0.1:5000/callback", "st", "ch").unwrap();
        assert!(url.starts_with("https://api.example.com/auth/authorize?response_type=code"));
        assert!(url.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A5000%2Fcallback"));
        assert!(url.contains("code_challenge_method=S256"));
    }

    #[test]
    fn accepts_only_the_callback_with_the_expected_state() {
        assert_eq!(authorization_code("/callback?code=abc&state=st", "st").as_deref(), Some("abc"));
        assert_eq!(authorization_code("/callback?code=abc&state=other", "st"), None);
        assert_eq!(authorization_code("/favicon.ico", "st"), None);
        assert_eq!(authorization_code("/callback?code=&state=st", "st"), None);
    }

    #[test]
    fn decodes_accounts_leniently() {
        let account = decode_account(
            br#"{"email":"a@b.c","plan":"yearly","usage":[{"used":250000,"limit":1000000},{"used":1,"limit":2}],"period_end":"2026-11-01T00:00:00.000Z"}"#,
        )
        .unwrap();
        assert_eq!(account.plan.as_deref(), Some("yearly"));
        assert_eq!(account.usage, vec![Usage { used: 250_000, limit: 1_000_000, percent_used: 25 }]);

        let unknown = decode_account(br#"{"email":"a@b.c","plan":"enterprise","usage":[{"used":"x"}]}"#).unwrap();
        assert_eq!(unknown.plan, None);
        assert!(unknown.usage.is_empty());
    }

    #[test]
    fn usage_is_shown_as_a_share_of_the_allowance() {
        assert_eq!(Usage::new(1_200_000, 1_000_000).percent_used, 100);
        assert_eq!(Usage::new(5, 0).percent_used, 100);
        assert_eq!(Usage::new(0, 1_000_000).percent_used, 0);
    }
}
