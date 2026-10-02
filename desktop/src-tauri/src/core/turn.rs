//! Pure decisions for one prompt invocation, mirroring `PromptTurn` in the macOS app.

use super::prompt::Exchange;

pub const CLOSING_COUNTDOWN_SECONDS: [u32; 3] = [3, 2, 1];

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Submission {
    Generate(String),
    Insert,
    None,
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

pub fn submission(instruction: &str, result: &str, is_generating: bool) -> Submission {
    let trimmed = instruction.trim();
    if !trimmed.is_empty() {
        return Submission::Generate(trimmed.to_owned());
    }
    if !result.is_empty() && !is_generating {
        return Submission::Insert;
    }
    Submission::None
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
        assert_eq!(submission("  shorter ", "Text", false), Submission::Generate("shorter".into()));
        assert_eq!(submission(" ", "Text", false), Submission::Insert);
        assert_eq!(submission("", "Text", true), Submission::None);
        assert_eq!(submission("", "", false), Submission::None);
    }

    #[test]
    fn a_finished_result_joins_the_history() {
        let updated = history(&[], "Reply", "Sure!", false);
        assert_eq!(updated, vec![Exchange { instruction: "Reply".into(), result: "Sure!".into() }]);
        assert!(history(&[], "Reply", "Sure!", true).is_empty());
    }

    #[test]
    fn recapture_adds_only_new_lines() {
        let merged = merge_window_text(Some("b\nc".into()), Some("a\nb".into()));
        assert_eq!(merged.as_deref(), Some("a\nb\nc"));
        assert_eq!(merge_window_text(None, Some("a".into())).as_deref(), Some("a"));
        assert_eq!(merge_window_text(Some("a".into()), None).as_deref(), Some("a"));
    }
}
