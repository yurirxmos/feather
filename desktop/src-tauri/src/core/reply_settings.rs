//! Everything in Settings > Replies. Signed in to a Feather account, they are saved to it, plan or
//! not, so every computer signed in to the same account replies the same way
//! (`/v1/reply-settings` on feather-api). Mirrors `ReplySettings` in the macOS app.
//!
//! The choices keep their stored ids as strings, so one a newer app added survives a round trip
//! through this one; `Settings::resolve` falls back to the default for ids it doesn't know.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ReplySettings {
    pub custom_instructions: String,
    pub include_screenshot: bool,
    pub reply_tone: String,
    pub reply_length: String,
    pub reply_language: String,
}

/// What to do once the account's settings arrive.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SyncAction {
    /// Both already match.
    None,
    /// Take the account's settings.
    Apply(ReplySettings),
    /// Save this computer's settings to the account.
    Upload(ReplySettings),
}

/// The account's settings win, except when this computer has a change it hasn't saved yet (made
/// offline, say) or the account has none: then this computer's are saved.
pub fn sync_action(local: ReplySettings, remote: Option<ReplySettings>, local_change_pending: bool) -> SyncAction {
    match remote {
        Some(remote) if !local_change_pending => {
            if remote == local {
                SyncAction::None
            } else {
                SyncAction::Apply(remote)
            }
        }
        _ => SyncAction::Upload(local),
    }
}

/// The account's settings from `GET /v1/reply-settings`: `Ok(None)` when it has none saved yet.
pub fn decode(body: &[u8]) -> Result<Option<ReplySettings>, serde_json::Error> {
    #[derive(Deserialize)]
    struct Response {
        settings: Option<ReplySettings>,
    }
    serde_json::from_slice::<Response>(body).map(|response| response.settings)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> ReplySettings {
        ReplySettings {
            custom_instructions: "Do not use emojis.".into(),
            include_screenshot: false,
            reply_tone: "friendly".into(),
            reply_length: "short".into(),
            reply_language: "portuguese".into(),
        }
    }

    fn defaults() -> ReplySettings {
        ReplySettings {
            custom_instructions: String::new(),
            include_screenshot: true,
            reply_tone: "natural".into(),
            reply_length: "matchRequest".into(),
            reply_language: "conversation".into(),
        }
    }

    #[test]
    fn uses_the_server_field_names() {
        let json = serde_json::to_value(sample()).unwrap();
        assert_eq!(
            json,
            serde_json::json!({
                "custom_instructions": "Do not use emojis.",
                "include_screenshot": false,
                "reply_tone": "friendly",
                "reply_length": "short",
                "reply_language": "portuguese",
            })
        );
    }

    #[test]
    fn decodes_the_accounts_settings_or_none() {
        let saved = br#"{"settings":{"custom_instructions":"Do not use emojis.","include_screenshot":false,"reply_tone":"friendly","reply_length":"short","reply_language":"portuguese"},"updated_at":"2026-10-10T12:00:00.000Z"}"#;
        assert_eq!(decode(saved).unwrap(), Some(sample()));
        assert_eq!(decode(br#"{"settings":null,"updated_at":null}"#).unwrap(), None);
        assert!(decode(br#"{"settings":{"reply_tone":"casual"}}"#).is_err());
    }

    #[test]
    fn the_account_wins_unless_a_change_is_pending_or_it_has_none() {
        assert_eq!(sync_action(defaults(), Some(sample()), false), SyncAction::Apply(sample()));
        assert_eq!(sync_action(defaults(), Some(sample()), true), SyncAction::Upload(defaults()));
        assert_eq!(sync_action(defaults(), None, false), SyncAction::Upload(defaults()));
        assert_eq!(sync_action(sample(), Some(sample()), false), SyncAction::None);
    }
}
