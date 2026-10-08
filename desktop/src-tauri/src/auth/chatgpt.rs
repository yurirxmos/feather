//! ChatGPT sign-in through the Codex OAuth client, matching `ChatGPTAuth` in the macOS app.

use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;

use super::loopback;
use crate::core::pkce;
use crate::credentials::{self, ChatGptCredentials};
use crate::i18n::t;
use crate::providers::stream::CLIENT;

const CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
const ISSUER: &str = "https://auth.openai.com";
/// The redirect URI registered for this client, so the port is fixed.
const CALLBACK_PORT: u16 = 1455;

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: String,
    id_token: Option<String>,
    expires_in: Option<u64>,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|duration| duration.as_secs()).unwrap_or(0)
}

/// Runs the browser sign-in and stores the credentials. Drop the future to cancel it; the port is
/// released either way.
pub async fn sign_in(open_url: impl FnOnce(&str)) -> Result<(), String> {
    let verifier = pkce::random_string(64);
    let state = pkce::random_string(32);
    let redirect_uri = format!("http://localhost:{CALLBACK_PORT}/auth/callback");
    let listener = loopback::bind(CALLBACK_PORT)
        .await
        .map_err(|_| t("Port 1455 is in use. Close other apps signing in to ChatGPT and try again."))?;

    let mut url = reqwest::Url::parse(&format!("{ISSUER}/oauth/authorize")).expect("valid issuer");
    url.query_pairs_mut()
        .append_pair("response_type", "code")
        .append_pair("client_id", CLIENT_ID)
        .append_pair("redirect_uri", &redirect_uri)
        .append_pair("scope", "openid profile email offline_access")
        .append_pair("code_challenge", &pkce::code_challenge(&verifier))
        .append_pair("code_challenge_method", "S256")
        .append_pair("id_token_add_organizations", "true")
        .append_pair("codex_cli_simplified_flow", "true")
        .append_pair("state", &state)
        .append_pair("originator", "opencode");
    open_url(url.as_str());

    let callback = loopback::receive(listener, loopback::SIGN_IN_TIMEOUT, |target| {
        let url = reqwest::Url::parse(&format!("http://localhost{target}")).ok()?;
        if url.path() != "/auth/callback" {
            return None;
        }
        let query = |name: &str| url.query_pairs().find(|(key, _)| key == name).map(|(_, value)| value.into_owned());
        (query("state")? == state).then(|| query("code")).flatten().filter(|code| !code.is_empty())
    })
    .await
    .ok_or_else(|| t("ChatGPT login timed out."))?;

    let result = exchange(&[
        ("grant_type", "authorization_code"),
        ("code", &callback.code),
        ("redirect_uri", &redirect_uri),
        ("client_id", CLIENT_ID),
        ("code_verifier", &verifier),
    ])
    .await
    .map_err(|status| t("ChatGPT token exchange failed ({status}).").replace("{status}", &status.to_string()))
    .and_then(|tokens| {
        let account_id = tokens
            .id_token
            .as_deref()
            .and_then(pkce::chatgpt_account_id)
            .or_else(|| pkce::chatgpt_account_id(&tokens.access_token));
        credentials::set_chatgpt_credentials(&ChatGptCredentials {
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_at: now() + tokens.expires_in.unwrap_or(3600),
            account_id,
        })
    });

    let page = match &result {
        Ok(()) => loopback::page(&t("Connected to ChatGPT"), &t("You can close this window and return to Feather."), true),
        Err(message) => loopback::page(&t("ChatGPT connection failed"), message, false),
    };
    callback.respond(&page).await;
    result
}

/// Returns stored credentials, refreshing them when they expire within a minute.
pub async fn valid_credentials() -> Result<ChatGptCredentials, String> {
    let credentials = credentials::chatgpt_credentials().ok_or_else(|| t("Sign in with ChatGPT in Settings."))?;
    if credentials.expires_at > now() + 60 {
        return Ok(credentials);
    }
    let tokens = exchange(&[
        ("grant_type", "refresh_token"),
        ("refresh_token", &credentials.refresh_token),
        ("client_id", CLIENT_ID),
    ])
    .await
    .map_err(|status| t("ChatGPT session refresh failed ({status}).").replace("{status}", &status.to_string()))?;
    let refreshed = ChatGptCredentials {
        account_id: tokens.id_token.as_deref().and_then(pkce::chatgpt_account_id).or(credentials.account_id),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_at: now() + tokens.expires_in.unwrap_or(3600),
    };
    credentials::set_chatgpt_credentials(&refreshed)?;
    Ok(refreshed)
}

/// Posts a form to the token endpoint; the error is the HTTP status, or 0 when unreachable.
async fn exchange(form: &[(&str, &str)]) -> Result<TokenResponse, u16> {
    let response = CLIENT.post(format!("{ISSUER}/oauth/token")).form(form).send().await.map_err(|_| 0u16)?;
    let status = response.status();
    if !status.is_success() {
        return Err(status.as_u16());
    }
    response.json().await.map_err(|_| status.as_u16())
}
