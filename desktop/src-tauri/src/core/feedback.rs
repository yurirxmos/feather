//! Feedback written in the app, sent to `feather-api`, which emails it to the team. It carries only
//! what the user types, plus the app and system versions; never screen context. Mirrors `Feedback`
//! in the macOS app.

use serde_json::{json, Value};

use super::error::{endpoint, LlmError};

/// The longest message the server accepts, in UTF-16 code units as JavaScript counts them.
pub const MAX_MESSAGE_LENGTH: usize = 5_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Outcome {
    Sent,
    /// The server rejected the message or the email address.
    Invalid,
    /// Too much feedback from this network today.
    RateLimited,
    Failed,
}

pub fn url(base: &str) -> Result<String, LlmError> {
    Ok(endpoint(base, "/v1/feedback")?.into())
}

pub fn body(message: &str, email: &str, app_version: &str, platform: &str) -> Value {
    let mut body = json!({ "message": message.trim(), "app_version": app_version, "platform": platform });
    let email = email.trim();
    if !email.is_empty() {
        body["email"] = json!(email);
    }
    body
}

pub fn outcome(status: u16) -> Outcome {
    match status {
        200..=299 => Outcome::Sent,
        400 => Outcome::Invalid,
        429 => Outcome::RateLimited,
        _ => Outcome::Failed,
    }
}

/// Whether the message can be sent: not blank and within the server's limit.
pub fn can_send(message: &str) -> bool {
    let trimmed = message.trim();
    !trimmed.is_empty() && trimmed.encode_utf16().count() <= MAX_MESSAGE_LENGTH
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn body_trims_the_message_and_email() {
        let body = body("  The panel hides behind Slack.\n", " user@example.com ", "0.4.1", "Windows");
        assert_eq!(
            body,
            json!({
                "message": "The panel hides behind Slack.",
                "email": "user@example.com",
                "app_version": "0.4.1",
                "platform": "Windows",
            })
        );
    }

    #[test]
    fn body_leaves_out_a_blank_email() {
        assert!(body("Hi", "  ", "1", "p").get("email").is_none());
    }

    #[test]
    fn url_appends_the_path() {
        assert_eq!(url("http://127.0.0.1:8787/").unwrap(), "http://127.0.0.1:8787/v1/feedback");
        assert!(url("not a url").is_err());
    }

    #[test]
    fn outcome_follows_status() {
        assert_eq!(outcome(204), Outcome::Sent);
        assert_eq!(outcome(400), Outcome::Invalid);
        assert_eq!(outcome(429), Outcome::RateLimited);
        assert_eq!(outcome(502), Outcome::Failed);
    }

    #[test]
    fn can_send_needs_text_within_the_limit() {
        assert!(!can_send(" \n "));
        assert!(can_send("Hi"));
        assert!(can_send(&"x".repeat(MAX_MESSAGE_LENGTH)));
        assert!(!can_send(&"x".repeat(MAX_MESSAGE_LENGTH + 1)));
    }
}
