//! Strips the wrapping a chat model sometimes puts around the text despite the prompt, such as
//! "Here is a comment:" and `---` before it and "Hope this helps!" after it, so only the text is
//! inserted. It only removes what is clearly wrapping: a closing remark goes only when the text
//! was also introduced or set off by separators, because a real message can end with "Let me
//! know". Mirrors `ReplyCleanup` in the macOS app's `FeatherCore`.

/// How an introduction opens, lowercased; it must end there or before a non-letter.
const INTRODUCTIONS: &[&str] = &[
    "here's", "here is", "here are", "sure", "of course", "certainly", "absolutely", "below", "this is", "aqui está",
    "aqui estão", "aqui vai", "aqui vão", "segue", "seguem", "claro", "com certeza", "certo", "perfeito", "abaixo",
    "este é", "esta é", "eis",
];

/// How a closing remark opens, lowercased.
const CLOSINGS: &[&str] = &[
    "espero que", "hope this", "hope that", "hope it", "let me know", "feel free", "se quiser", "se precisar",
    "caso queira", "caso precise", "quer que eu", "posso ajustar", "posso mudar", "posso fazer", "if you like",
    "if you want", "if you need", "if you'd like", "i can adjust", "i can also adjust", "i can make", "i can change",
    "would you like", "fique à vontade",
];

pub fn unwrap(text: &str) -> String {
    let trimmed = text.trim();
    let mut lines: Vec<&str> = trimmed.split('\n').collect();

    if let Some(first) = lines.iter().position(|line| is_separator(line)) {
        let last = lines.iter().rposition(|line| is_separator(line)).unwrap_or(first);
        let before = joined(&lines[..first]);
        let body = if last > first { &lines[first + 1..last] } else { &lines[first + 1..] };
        let after = if last > first { joined(&lines[last + 1..]) } else { String::new() };
        if (before.is_empty() || is_introduction(&before, true)) && is_short_remark(&after) && !joined(body).is_empty() {
            return unquoted(&joined(body));
        }
        return unquoted(trimmed);
    }

    let Some(first_line) = lines.first() else { return String::new() };
    if !is_introduction(first_line, false) {
        return unquoted(trimmed);
    }
    lines.remove(0);
    // The text itself has not arrived yet.
    if joined(&lines).is_empty() {
        return String::new();
    }
    if let Some(index) = lines.iter().rposition(|line| !line.trim().is_empty()) {
        if is_closing_remark(lines[index]) && !joined(&lines[..index]).is_empty() {
            lines.truncate(index);
        }
    }
    unquoted(&joined(&lines))
}

fn joined(lines: &[&str]) -> String {
    lines.join("\n").trim().to_owned()
}

/// `---`, `***`, `___`, or a code fence such as ```` ```text ````.
fn is_separator(line: &str) -> bool {
    let line = line.trim();
    if let Some(language) = line.strip_prefix("```") {
        return language.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-');
    }
    line.chars().count() >= 3 && ['-', '*', '_'].iter().any(|&mark| line.chars().all(|c| c == mark))
}

fn opens_with(line: &str, prefixes: &[&str], whole_word: bool) -> bool {
    let lower = line.to_lowercase();
    prefixes.iter().any(|prefix| {
        lower.strip_prefix(prefix).is_some_and(|rest| !whole_word || !rest.starts_with(|c: char| c.is_alphabetic()))
    })
}

/// A short line that announces the text. Before a separator, any short line ending in a colon
/// counts; otherwise it must also open like an introduction, so "Dear team:" stays.
fn is_introduction(text: &str, allows_any_colon_line: bool) -> bool {
    let line = text.trim();
    if line.is_empty() || line.chars().count() > 200 || line.contains("\n\n") {
        return false;
    }
    let opens = opens_with(line, INTRODUCTIONS, true);
    if allows_any_colon_line {
        line.ends_with(':') || opens
    } else {
        opens && line.ends_with(':')
    }
}

fn is_closing_remark(text: &str) -> bool {
    let line = text.trim();
    line.chars().count() <= 160 && opens_with(line, CLOSINGS, false)
}

fn is_short_remark(text: &str) -> bool {
    text.chars().count() <= 200 && !text.contains("\n\n")
}

/// Removes quotes around the whole text when they are not also used inside it.
fn unquoted(text: &str) -> String {
    for (open, close) in [('"', '"'), ('“', '”'), ('«', '»')] {
        if text.chars().count() > 2 && text.starts_with(open) && text.ends_with(close) {
            let inner = &text[open.len_utf8()..text.len() - close.len_utf8()];
            if !inner.contains(open) && !inner.contains(close) {
                return inner.trim().to_owned();
            }
        }
    }
    text.to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    const COMMENT: &str = "Essa publicação resume muito bem a jornada de qualquer programador. A primeira vez que conseguimos fazer algo funcionar é sempre um momento de realização.";

    #[test]
    fn strips_an_introduction_separators_and_a_closing_remark() {
        let wrapped = format!("Aqui está um comentário inteligente e bem elaborado para a publicação de Michael Santos:\n\n---\n\n{COMMENT}\n\n---\n\nEspero que isso ajude!");
        assert_eq!(unwrap(&wrapped), COMMENT);
        assert_eq!(unwrap(&format!("```\n{COMMENT}\n```")), COMMENT);
    }

    #[test]
    fn strips_an_introduction_without_separators() {
        assert_eq!(unwrap(&format!("Here's a reply:\n\n{COMMENT}\n\nHope this helps!")), COMMENT);
        assert_eq!(unwrap(&format!("Claro! Segue a mensagem:\n{COMMENT}")), COMMENT);
    }

    #[test]
    fn hides_an_introduction_until_the_text_arrives() {
        assert_eq!(unwrap("Aqui está um comentário:"), "");
        assert_eq!(unwrap("Aqui está um comentário:\n\n---\n\nEssa publi"), "Essa publi");
    }

    #[test]
    fn keeps_ordinary_messages() {
        assert_eq!(unwrap("Dear team:\n\nThe report is ready."), "Dear team:\n\nThe report is ready.");
        assert_eq!(unwrap("The report is ready.\n\nLet me know if you have questions."), "The report is ready.\n\nLet me know if you have questions.");
        let sections = format!("{COMMENT}\n\n---\n\nSecond part of a longer text that is clearly not a short remark, with enough words.");
        assert_eq!(unwrap(&sections), sections);
        assert_eq!(unwrap("Sure, tomorrow works."), "Sure, tomorrow works.");
        assert_eq!(unwrap("Surely not:\nok"), "Surely not:\nok");
    }

    #[test]
    fn strips_quotes_around_the_whole_text_only() {
        assert_eq!(unwrap("\"Tomorrow at 2 pm works!\""), "Tomorrow at 2 pm works!");
        assert_eq!(unwrap("“Combinado!”"), "Combinado!");
        assert_eq!(unwrap("\"Yes\" is my answer, \"no\" is not"), "\"Yes\" is my answer, \"no\" is not");
    }
}
