//! Pure decisions for one prompt invocation, mirroring `PromptTurn` in the macOS app.

use super::prompt::Exchange;

/// How long "Copied to clipboard." stays up; copying never closes the panel.
pub const COPIED_NOTICE_DURATION: std::time::Duration = std::time::Duration::from_secs(2);

/// How long a panel hidden by the shortcut or a click elsewhere can be picked up again.
pub const RESUME_WINDOW: std::time::Duration = std::time::Duration::from_secs(60);

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Submission {
    Generate(String),
    Insert,
    /// Only an answer came back, so there is nothing to insert; Enter copies the answer.
    Copy,
    None,
}

/// How Insert delivers the reply.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InsertRoute {
    /// Bring the target app back and paste into its focused field.
    Paste,
    /// There is no app to paste into, such as when the shortcut was pressed over the desktop.
    CopyWithoutTarget,
    /// Pasting needs a permission Feather does not have, or this session cannot do it.
    CopyWithoutPermission,
    /// The focused field takes a password; a reply never goes into one.
    CopyIntoSecureField,
    /// The target app closed after the shortcut, so a paste would land in whatever app is in front.
    TargetClosed,
}

/// Whether showing the panel resumes the hidden session, adding a new capture to it, instead of
/// saving it to recent conversations and starting fresh. Only the same app, soon after, resumes,
/// so one app's context and conversation never shape a reply meant for another.
pub fn resumes_suspended_session(same_app: bool, suspended_for: std::time::Duration) -> bool {
    same_app && suspended_for < RESUME_WINDOW
}

pub fn insert_route(has_target: bool, target_is_open: bool, can_paste: bool, focused_field_is_secure: bool) -> InsertRoute {
    if !has_target {
        InsertRoute::CopyWithoutTarget
    } else if !target_is_open {
        InsertRoute::TargetClosed
    } else if !can_paste {
        InsertRoute::CopyWithoutPermission
    } else if focused_field_is_secure {
        InsertRoute::CopyIntoSecureField
    } else {
        InsertRoute::Paste
    }
}

/// Adds lines from a new capture that the earlier captures did not have.
pub fn merge_window_text(new_text: Option<String>, existing: Option<String>) -> Option<String> {
    let new_text = match new_text {
        Some(text) if !text.is_empty() => text,
        _ => return existing,
    };
    let existing = match existing {
        Some(text) if !text.is_empty() => text,
        _ => return Some(new_text),
    };
    let existing_lines: std::collections::HashSet<&str> = existing.split('\n').collect();
    let additions: Vec<&str> = new_text.split('\n').filter(|line| !existing_lines.contains(line)).collect();
    if additions.is_empty() {
        Some(existing)
    } else {
        Some(format!("{existing}\n{}", additions.join("\n")))
    }
}

pub fn submission(instruction: &str, result: &str, answer: &str, is_generating: bool) -> Submission {
    let trimmed = instruction.trim();
    if !trimmed.is_empty() {
        return Submission::Generate(trimmed.to_owned());
    }
    if is_generating {
        return Submission::None;
    }
    if !result.is_empty() {
        return Submission::Insert;
    }
    if !answer.is_empty() {
        return Submission::Copy;
    }
    Submission::None
}

/// The text Ctrl+Enter copies: the suggestion, or the answer when no suggestion came back.
pub fn copyable_text<'a>(result: &'a str, answer: &'a str) -> &'a str {
    if result.is_empty() {
        answer
    } else {
        result
    }
}

const QUESTION_WORDS: [&str; 15] = [
    "what", "why", "how", "who", "which", "where", "qual", "quais", "quem", "onde", "quanto", "quanta", "quantos", "quantas",
    "pq",
];
const QUESTION_PHRASES: [&str; 3] = ["o que", "por que", "por quê"];

/// Whether an instruction reads as a question. Only Feather Plus answers questions, so the other
/// connections point to it when one is asked. Ambiguous openers such as "como" or "when" are left
/// out so ordinary messages don't get the pointer.
pub fn looks_like_question(instruction: &str) -> bool {
    let text = instruction.trim().to_lowercase();
    if text.ends_with('?') || text.starts_with('¿') {
        return true;
    }
    let words: Vec<&str> = text.split_whitespace().map(|word| word.trim_matches(|c: char| c.is_ascii_punctuation())).collect();
    // "what's" opens a question as much as "what".
    let Some(first) = words.first().and_then(|word| word.split(['\'', '’']).next()) else {
        return false;
    };
    if QUESTION_WORDS.contains(&first) {
        return true;
    }
    words.len() > 1 && QUESTION_PHRASES.contains(&format!("{first} {}", words[1]).as_str())
}

pub fn history(history: &[Exchange], last_instruction: &str, result: &str, is_generating: bool) -> Vec<Exchange> {
    let mut history = history.to_vec();
    if !result.is_empty() && !is_generating {
        history.push(Exchange { instruction: last_instruction.to_owned(), result: result.to_owned() });
    }
    history
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_new_instruction_generates_and_an_empty_one_inserts_the_result() {
        assert_eq!(submission("  shorter ", "Text", "", false), Submission::Generate("shorter".into()));
        assert_eq!(submission(" ", "Text", "", false), Submission::Insert);
        assert_eq!(submission("", "Text", "", true), Submission::None);
        assert_eq!(submission("", "", "", false), Submission::None);
    }

    #[test]
    fn an_answer_without_a_suggestion_is_copied() {
        assert_eq!(submission("", "", "Paris.", false), Submission::Copy);
        assert_eq!(submission("", "Text", "Paris.", false), Submission::Insert);
        assert_eq!(submission("", "", "Paris.", true), Submission::None);
        assert_eq!(copyable_text("", "Paris."), "Paris.");
        assert_eq!(copyable_text("Text", "Paris."), "Text");
    }

    #[test]
    fn questions_are_recognized_without_catching_ordinary_messages() {
        for question in ["qual a capital da frança", "o que é vacilão", "what's the deadline", "tá atrasado?", "Por que não veio?"] {
            assert!(looks_like_question(question), "{question}");
        }
        for message in ["fale que ele é um vacilão", "como combinado, segue o arquivo", "when you get home call me", ""] {
            assert!(!looks_like_question(message), "{message}");
        }
    }

    #[test]
    fn a_finished_result_joins_the_history() {
        let updated = history(&[], "Reply", "Sure!", false);
        assert_eq!(updated, vec![Exchange { instruction: "Reply".into(), result: "Sure!".into() }]);
        assert!(history(&[], "Reply", "Sure!", true).is_empty());
    }

    #[test]
    fn only_the_same_app_soon_after_resumes_a_hidden_session() {
        use std::time::Duration;
        assert!(resumes_suspended_session(true, Duration::from_secs(5)));
        assert!(!resumes_suspended_session(false, Duration::from_secs(5)));
        assert!(!resumes_suspended_session(true, RESUME_WINDOW));
    }

    #[test]
    fn insert_pastes_only_into_an_open_app_with_permission_and_a_normal_field() {
        assert_eq!(insert_route(true, true, true, false), InsertRoute::Paste);
        assert_eq!(insert_route(false, true, true, false), InsertRoute::CopyWithoutTarget);
        assert_eq!(insert_route(true, false, false, false), InsertRoute::TargetClosed);
        assert_eq!(insert_route(true, true, false, false), InsertRoute::CopyWithoutPermission);
        assert_eq!(insert_route(true, true, true, true), InsertRoute::CopyIntoSecureField);
    }

    #[test]
    fn recapture_adds_only_new_lines() {
        let merged = merge_window_text(Some("b\nc".into()), Some("a\nb".into()));
        assert_eq!(merged.as_deref(), Some("a\nb\nc"));
        assert_eq!(merge_window_text(None, Some("a".into())).as_deref(), Some("a"));
        assert_eq!(merge_window_text(Some("a".into()), None).as_deref(), Some("a"));
    }
}
