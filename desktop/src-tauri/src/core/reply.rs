//! Splits an assistant-mode response into the answer shown to the user and the suggestion that is
//! inserted. Mirrors `AssistantReply` in the macOS app's `FeatherCore`.

use super::cleanup;
use super::prompt::Mode;

pub const ANSWER_OPEN: &str = "<answer>";
pub const ANSWER_CLOSE: &str = "</answer>";

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Reply {
    /// What Feather says to the user. Empty unless the instruction asked a question.
    pub answer: String,
    /// The text to insert into the focused field.
    pub suggestion: String,
}

impl Reply {
    /// Reads a complete or still-streaming response. Type assist has no answer, so the whole text
    /// is the suggestion.
    pub fn parse(text: &str, mode: Mode) -> Reply {
        if mode == Mode::TypeAssist {
            return Reply { answer: String::new(), suggestion: cleanup::unwrap(text) };
        }
        let text = text.trim_start();
        let Some(rest) = text.strip_prefix(ANSWER_OPEN) else {
            // A half-streamed opening tag is not text yet.
            if !text.is_empty() && ANSWER_OPEN.starts_with(text) {
                return Reply::default();
            }
            return Reply { answer: String::new(), suggestion: cleanup::unwrap(text) };
        };
        match rest.find(ANSWER_CLOSE) {
            Some(end) => Reply {
                answer: rest[..end].trim().to_owned(),
                suggestion: cleanup::unwrap(&rest[end + ANSWER_CLOSE.len()..]),
            },
            None => {
                // Still inside the answer; hide a half-streamed closing tag.
                let partial = (1..ANSWER_CLOSE.len()).rev().find(|&length| rest.ends_with(&ANSWER_CLOSE[..length])).unwrap_or(0);
                Reply { answer: rest[..rest.len() - partial].trim().to_owned(), suggestion: String::new() }
            }
        }
    }

    /// The response as the model wrote it, so follow-ups keep the format.
    pub fn raw(&self) -> String {
        if self.answer.is_empty() {
            return self.suggestion.clone();
        }
        format!("{ANSWER_OPEN}{}{ANSWER_CLOSE}\n\n{}", self.answer, self.suggestion)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn type_assist_has_no_answer() {
        let reply = Reply::parse("  <answer>x</answer> text ", Mode::TypeAssist);
        assert_eq!(reply, Reply { answer: String::new(), suggestion: "<answer>x</answer> text".into() });
    }

    #[test]
    fn assistant_splits_the_answer_from_the_suggestion() {
        let reply = Reply::parse("<answer>Paris.</answer>\n\nIt is Paris!", Mode::Assistant);
        assert_eq!(reply, Reply { answer: "Paris.".into(), suggestion: "It is Paris!".into() });
        assert_eq!(reply.raw(), "<answer>Paris.</answer>\n\nIt is Paris!");
    }

    #[test]
    fn assistant_without_an_answer_is_all_suggestion() {
        let reply = Reply::parse("Sure, tomorrow works.", Mode::Assistant);
        assert_eq!(reply, Reply { answer: String::new(), suggestion: "Sure, tomorrow works.".into() });
        assert_eq!(reply.raw(), "Sure, tomorrow works.");
    }

    #[test]
    fn replies_are_cleaned_in_both_modes() {
        let wrapped = "Aqui está:\n\n---\n\nCombinado!\n\n---";
        assert_eq!(Reply::parse(wrapped, Mode::TypeAssist).suggestion, "Combinado!");
        assert_eq!(Reply::parse(wrapped, Mode::Assistant).suggestion, "Combinado!");
        assert_eq!(Reply::parse(&format!("<answer>Sim.</answer>\n\n{wrapped}"), Mode::Assistant).suggestion, "Combinado!");
    }

    #[test]
    fn streaming_never_shows_a_half_written_tag() {
        assert_eq!(Reply::parse("<ans", Mode::Assistant), Reply::default());
        assert_eq!(Reply::parse("<answer>Par", Mode::Assistant), Reply { answer: "Par".into(), suggestion: String::new() });
        assert_eq!(Reply::parse("<answer>Paris.</ans", Mode::Assistant).answer, "Paris.");
        let partial = Reply::parse("<answer>Paris.</answer>\n\nIt is", Mode::Assistant);
        assert_eq!(partial, Reply { answer: "Paris.".into(), suggestion: "It is".into() });
    }
}
