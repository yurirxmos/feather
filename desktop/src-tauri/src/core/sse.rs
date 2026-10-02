#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SseEvent {
    pub event: Option<String>,
    pub data: String,
}

/// Incremental server-sent events parser. Feed it arbitrary chunks, split anywhere; it emits one
/// event per completed `data:` line, tagged with the preceding `event:` name.
#[derive(Default)]
pub struct SseParser {
    buffer: String,
    event_name: Option<String>,
    data_lines: Vec<String>,
}

impl SseParser {
    pub fn push(&mut self, chunk: &str) -> Vec<SseEvent> {
        self.buffer.push_str(chunk);
        let mut events = Vec::new();
        while let Some(newline) = self.buffer.find(['\n', '\r']) {
            let line = self.buffer[..newline].to_owned();
            let mut end = newline + 1;
            if self.buffer[newline..].starts_with("\r\n") {
                end += 1;
            }
            self.buffer.drain(..end);
            if let Some(event) = self.consume(&line) {
                events.push(event);
            }
        }
        events
    }

    /// Emits any event left open when the stream ends without a trailing blank line.
    pub fn finish(&mut self) -> Vec<SseEvent> {
        let mut events = Vec::new();
        if !self.buffer.is_empty() {
            let line = std::mem::take(&mut self.buffer);
            if let Some(event) = self.consume(&line) {
                events.push(event);
            }
        }
        if let Some(event) = self.dispatch() {
            events.push(event);
        }
        events
    }

    fn consume(&mut self, line: &str) -> Option<SseEvent> {
        if line.is_empty() {
            return self.dispatch();
        }
        if line.starts_with(':') {
            return None;
        }
        let (field, value) = match line.split_once(':') {
            Some((field, value)) => (field, value.strip_prefix(' ').unwrap_or(value)),
            None => (line, ""),
        };
        match field {
            "event" => self.event_name = Some(value.to_owned()),
            "data" => {
                self.data_lines.push(value.to_owned());
                // Every provider Feather talks to sends one JSON object per `data:` line, so
                // dispatching eagerly is safe and does not wait for the blank line.
                return self.dispatch();
            }
            _ => {}
        }
        None
    }

    fn dispatch(&mut self) -> Option<SseEvent> {
        let event_name = self.event_name.take();
        if self.data_lines.is_empty() {
            return None;
        }
        let data = std::mem::take(&mut self.data_lines).join("\n");
        Some(SseEvent { event: event_name, data })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_event_and_data_split_across_chunks() {
        let mut parser = SseParser::default();
        assert!(parser.push("event: response.output_text.delta\nda").is_empty());
        let events = parser.push("ta: {\"delta\":\"Hi\"}\r\n\r\n");

        assert_eq!(
            events,
            vec![SseEvent { event: Some("response.output_text.delta".into()), data: "{\"delta\":\"Hi\"}".into() }]
        );
    }

    #[test]
    fn ignores_comments_and_flushes_on_finish() {
        let mut parser = SseParser::default();
        assert!(parser.push(": keep-alive\n").is_empty());
        assert!(parser.push("data: [DONE]").is_empty());
        assert_eq!(parser.finish(), vec![SseEvent { event: None, data: "[DONE]".into() }]);
    }
}
