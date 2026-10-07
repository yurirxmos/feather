//! The Style choices in Settings > Replies, mirroring `ReplyStyle` in the macOS app. They reach the
//! model as writing preferences, ahead of the user's own instructions, so those can refine them.

use serde::{Deserialize, Serialize};

/// The tone replies are written in. `Natural` follows the conversation on screen.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Tone {
    #[default]
    Natural,
    Friendly,
    Professional,
    Casual,
}

/// How long replies are. `MatchRequest` leaves it to the instruction.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Length {
    #[default]
    MatchRequest,
    Short,
    Detailed,
}

/// The language replies are written in. `Conversation` matches the conversation on screen.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Language {
    #[default]
    Conversation,
    English,
    Portuguese,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ReplyStyle {
    pub tone: Tone,
    pub length: Length,
    pub language: Language,
}

impl ReplyStyle {
    /// The writing preferences for the system prompt: one line per choice that isn't the default,
    /// then the custom instructions.
    pub fn writing_preferences(&self, custom_instructions: &str) -> String {
        let tone = match self.tone {
            Tone::Natural => None,
            Tone::Friendly => Some("Write in a warm, friendly tone."),
            Tone::Professional => Some("Write in a professional, polished tone."),
            Tone::Casual => Some("Write in a casual, relaxed tone."),
        };
        let length = match self.length {
            Length::MatchRequest => None,
            Length::Short => Some("Keep replies short and to the point."),
            Length::Detailed => Some("Write detailed, complete replies."),
        };
        let language = match self.language {
            Language::Conversation => None,
            Language::English => Some("Write in English, whatever language the conversation is in."),
            Language::Portuguese => Some("Write in Brazilian Portuguese, whatever language the conversation is in."),
        };
        let custom = Some(custom_instructions.trim()).filter(|custom| !custom.is_empty());
        [tone, length, language, custom].into_iter().flatten().collect::<Vec<_>>().join("\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_standard_style_adds_nothing() {
        assert_eq!(ReplyStyle::default().writing_preferences(""), "");
        assert_eq!(ReplyStyle::default().writing_preferences("  No emojis.  "), "No emojis.");
    }

    #[test]
    fn choices_come_before_custom_instructions() {
        let style = ReplyStyle { tone: Tone::Professional, length: Length::Short, language: Language::Portuguese };
        assert_eq!(
            style.writing_preferences("No emojis."),
            "Write in a professional, polished tone.\nKeep replies short and to the point.\nWrite in Brazilian Portuguese, whatever language the conversation is in.\nNo emojis."
        );
    }
}
