use crate::i18n::t;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LlmError {
    MissingApiKey,
    MissingModel,
    InvalidBaseUrl,
    Http { status: u16, message: Option<String> },
    Api(String),
    Refused,
    TimedOut,
    /// The request never reached the provider.
    Network,
}

impl LlmError {
    pub fn message(&self) -> String {
        match self {
            LlmError::MissingApiKey => t("Add an API key in Settings."),
            LlmError::MissingModel => t("Set a model in Settings."),
            LlmError::InvalidBaseUrl => t("The base URL in Settings is not valid."),
            LlmError::Http { status, message: Some(message) } => format!("{status}: {message}"),
            LlmError::Http { status, message: None } => {
                t("Request failed with status {status}.").replace("{status}", &status.to_string())
            }
            LlmError::Api(message) => message.clone(),
            LlmError::Refused => t("The model declined this request."),
            LlmError::TimedOut => {
                t("The model took more than 1 minute to respond. Try again or choose a faster model in Settings.")
            }
            LlmError::Network => t("Feather could not reach the provider. Check your connection and try again."),
        }
    }
}

/// Parses a user-entered base URL and appends `path`, tolerating a trailing slash.
pub fn endpoint(base: &str, path: &str) -> Result<reqwest::Url, LlmError> {
    let trimmed = base.trim().trim_end_matches('/');
    let url = reqwest::Url::parse(&format!("{trimmed}{path}")).map_err(|_| LlmError::InvalidBaseUrl)?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err(LlmError::InvalidBaseUrl);
    }
    Ok(url)
}

/// Reads `error.message`, `error`, or `message` from a JSON error body, or returns the raw text.
pub fn error_message(body: &[u8]) -> Option<String> {
    match serde_json::from_slice::<serde_json::Value>(body) {
        Ok(json) => json
            .pointer("/error/message")
            .and_then(|value| value.as_str())
            .or_else(|| json.get("error").and_then(|value| value.as_str()))
            .or_else(|| json.get("message").and_then(|value| value.as_str()))
            .map(str::to_owned),
        Err(_) => {
            let text = String::from_utf8_lossy(body).trim().to_owned();
            (!text.is_empty()).then_some(text)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoint_tolerates_trailing_slashes_and_rejects_other_schemes() {
        assert_eq!(endpoint("http://localhost:11434/v1/ ", "/models").unwrap().as_str(), "http://localhost:11434/v1/models");
        assert_eq!(endpoint("ftp://example.com", "/models"), Err(LlmError::InvalidBaseUrl));
        assert_eq!(endpoint("not a url", "/models"), Err(LlmError::InvalidBaseUrl));
    }

    #[test]
    fn reads_nested_and_flat_error_messages() {
        assert_eq!(error_message(br#"{"error":{"message":"Bad key"}}"#).as_deref(), Some("Bad key"));
        assert_eq!(error_message(br#"{"error":"Nope"}"#).as_deref(), Some("Nope"));
        assert_eq!(error_message(b"plain").as_deref(), Some("plain"));
        assert_eq!(error_message(b""), None);
    }
}
