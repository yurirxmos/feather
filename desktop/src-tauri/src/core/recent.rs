//! The last few panel conversations, newest first, and how ↑ and ↓ move through them. Mirrors
//! `RecentConversations` in the macOS app. A saved conversation holds only what the user typed and
//! what Feather replied; screen context is never saved.

use serde::{Deserialize, Serialize};

use super::prompt::Exchange;

pub const LIMIT: usize = 5;

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedConversation {
    /// Earlier turns, as sent back to the model when the conversation is refined.
    pub history: Vec<Exchange>,
    pub last_instruction: String,
    pub answer: String,
    pub result: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Direction {
    /// ↑: one conversation further back.
    Older,
    /// ↓: one conversation closer to the current one.
    Newer,
}

/// The conversation worth saving from a panel, or `None` when it produced nothing.
pub fn conversation(history: &[Exchange], last_instruction: &str, answer: &str, result: &str) -> Option<SavedConversation> {
    if result.is_empty() && answer.is_empty() {
        return None;
    }
    Some(SavedConversation {
        history: history.to_vec(),
        last_instruction: last_instruction.to_owned(),
        answer: answer.to_owned(),
        result: result.to_owned(),
    })
}

/// Puts `conversation` first. A conversation brought back with ↑ and then changed replaces the one
/// it came from, and one that was only viewed keeps its place.
pub fn saving(conversation: SavedConversation, restored_from: Option<&SavedConversation>, list: &[SavedConversation]) -> Vec<SavedConversation> {
    if Some(&conversation) == restored_from {
        return list.to_vec();
    }
    let mut list = list.to_vec();
    if let Some(index) = restored_from.and_then(|original| list.iter().position(|saved| saved == original)) {
        list.remove(index);
    }
    list.retain(|saved| *saved != conversation);
    list.insert(0, conversation);
    list.truncate(LIMIT);
    list
}

/// The index shown after a key press: `None` is the current conversation, 0 the newest saved one.
pub fn browse(index: Option<usize>, direction: Direction, count: usize) -> Option<usize> {
    match direction {
        Direction::Older if count == 0 => index,
        Direction::Older => Some(index.map_or(0, |index| (index + 1).min(count - 1))),
        Direction::Newer => index.and_then(|index| index.checked_sub(1)),
    }
}

/// Reads the saved list, ignoring a missing or unreadable file.
pub fn decode(data: Option<&[u8]>) -> Vec<SavedConversation> {
    let mut list: Vec<SavedConversation> = data.and_then(|data| serde_json::from_slice(data).ok()).unwrap_or_default();
    list.truncate(LIMIT);
    list
}

pub fn encode(list: &[SavedConversation]) -> Vec<u8> {
    serde_json::to_vec(&list[..list.len().min(LIMIT)]).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn saved(result: &str) -> SavedConversation {
        SavedConversation { last_instruction: "Reply".into(), result: result.into(), ..Default::default() }
    }

    #[test]
    fn only_conversations_with_a_reply_are_saved() {
        assert!(conversation(&[], "Reply", "", "").is_none());
        assert!(conversation(&[], "Why?", "Because.", "").is_some());
    }

    #[test]
    fn saving_puts_the_newest_first_and_keeps_five() {
        let mut list = Vec::new();
        for number in 1..=7 {
            list = saving(saved(&number.to_string()), None, &list);
        }
        let results: Vec<&str> = list.iter().map(|saved| saved.result.as_str()).collect();
        assert_eq!(results, ["7", "6", "5", "4", "3"]);
    }

    #[test]
    fn a_viewed_conversation_keeps_its_place() {
        let list = vec![saved("b"), saved("a")];
        assert_eq!(saving(saved("a"), Some(&saved("a")), &list), list);
    }

    #[test]
    fn a_refined_conversation_replaces_the_original() {
        let list = vec![saved("b"), saved("a")];
        let refined = saving(saved("a, shorter"), Some(&saved("a")), &list);
        let results: Vec<&str> = refined.iter().map(|saved| saved.result.as_str()).collect();
        assert_eq!(results, ["a, shorter", "b"]);
    }

    #[test]
    fn browsing_stops_at_both_ends() {
        assert_eq!(browse(None, Direction::Older, 3), Some(0));
        assert_eq!(browse(Some(1), Direction::Older, 3), Some(2));
        assert_eq!(browse(Some(2), Direction::Older, 3), Some(2));
        assert_eq!(browse(None, Direction::Older, 0), None);
        assert_eq!(browse(Some(2), Direction::Newer, 3), Some(1));
        assert_eq!(browse(Some(0), Direction::Newer, 3), None);
        assert_eq!(browse(None, Direction::Newer, 3), None);
    }

    #[test]
    fn decoding_survives_bad_data_and_round_trips() {
        assert!(decode(None).is_empty());
        assert!(decode(Some(b"nope")).is_empty());
        let list = vec![SavedConversation {
            history: vec![Exchange { instruction: "Reply".into(), result: "Hi".into() }],
            last_instruction: "Shorter".into(),
            answer: String::new(),
            result: "Hey".into(),
        }];
        assert_eq!(decode(Some(&encode(&list))), list);
    }
}
