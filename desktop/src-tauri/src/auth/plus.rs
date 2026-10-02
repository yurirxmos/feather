//! Feather Plus browser sign-in and account requests, matching `PlusAuth` in the macOS app.

use std::time::Duration;

use super::loopback;
use crate::core::{pkce, plus};
use crate::credentials;
use crate::i18n::t;
use crate::providers::stream::CLIENT;

const SIGN_IN_TIMEOUT: Duration = Duration::from_secs(300);

#[derive(Debug, Eq, PartialEq)]
pub enum PlusError {
    /// The stored token was revoked or expired.
    Unauthorized,
    Other(String),
}

impl PlusError {
    pub fn message(&self) -> String {
        match self {
            PlusError::Unauthorized => t("Your session expired. Sign in again."),
            PlusError::Other(message) => message.clone(),
        }
    }
}

fn unreachable() -> PlusError {
    PlusError::Other(t("Couldn't reach Feather Plus. Check your connection."))
}

fn server_error(status: u16) -> PlusError {
    PlusError::Other(t("Feather Plus returned an error ({status}).").replace("{status}", &status.to_string()))
}

/// Runs the browser sign-in and stores the account token. Drop the future to cancel it; the
/// loopback port is released either way.
pub async fn sign_in(base: &str, open_url: impl FnOnce(&str)) -> Result<(), PlusError> {
    let verifier = pkce::random_string(64);
    let state = pkce::random_string(32);
    let listener = loopback::bind(0).await.map_err(|error| PlusError::Other(error.to_string()))?;
    let port = listener.local_addr().map_err(|error| PlusError::Other(error.to_string()))?.port();
    let redirect_uri = plus::redirect_uri(port);
    let url = plus::authorize_url(base, &redirect_uri, &state, &pkce::code_challenge(&verifier))
        .map_err(|error| PlusError::Other(error.message()))?;
    open_url(&url);

    let callback = loopback::receive(listener, SIGN_IN_TIMEOUT, |target| plus::authorization_code(target, &state))
        .await
        .ok_or_else(|| PlusError::Other(t("Sign-in timed out. Try again.")))?;

    let result = exchange(base, &callback.code, &verifier, &redirect_uri).await.and_then(|token| {
        credentials::set_plus_token(&token).map_err(|_| PlusError::Other(t("Couldn't save your session in secure storage.")))
    });
    let page = match &result {
        Ok(()) => loopback::page(&t("Signed in to Feather Plus"), &t("You can close this window and return to Feather."), true),
        Err(error) => loopback::page(&t("Sign-in failed"), &error.message(), false),
    };
    callback.respond(&page).await;
    result
}

async fn exchange(base: &str, code: &str, verifier: &str, redirect_uri: &str) -> Result<String, PlusError> {
    let url = crate::core::error::endpoint(base, "/v1/auth/token").map_err(|error| PlusError::Other(error.message()))?;
    let body = serde_json::json!({ "code": code, "code_verifier": verifier, "redirect_uri": redirect_uri });
    let response = CLIENT.post(url).json(&body).send().await.map_err(|_| unreachable())?;
    let status = response.status().as_u16();
    if !(200..300).contains(&status) {
        return Err(server_error(status));
    }
    let bytes = response.bytes().await.map_err(|_| unreachable())?;
    plus::decode_token(&bytes).map_err(|error| PlusError::Other(error.message()))
}

pub async fn account(base: &str, token: &str) -> Result<plus::PlusAccount, PlusError> {
    let url = crate::core::error::endpoint(base, "/v1/account").map_err(|error| PlusError::Other(error.message()))?;
    let response = CLIENT.get(url).bearer_auth(token).send().await.map_err(|_| unreachable())?;
    let status = response.status().as_u16();
    if status == 401 {
        return Err(PlusError::Unauthorized);
    }
    if !(200..300).contains(&status) {
        return Err(server_error(status));
    }
    let bytes = response.bytes().await.map_err(|_| unreachable())?;
    plus::decode_account(&bytes).map_err(|error| PlusError::Other(error.message()))
}

/// Forgets the token locally right away, then asks the server to revoke it. Revocation is best
/// effort: a token that is no longer stored anywhere is useless even if it survives.
pub fn sign_out(base: &str) {
    let Some(token) = credentials::plus_token() else { return };
    credentials::delete_plus_token();
    let Ok(url) = crate::core::error::endpoint(base, "/v1/auth/revoke") else { return };
    tauri::async_runtime::spawn(async move {
        let _ = CLIENT.post(url).bearer_auth(token).timeout(Duration::from_secs(10)).send().await;
    });
}
