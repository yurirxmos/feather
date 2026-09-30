/// Context belongs to one invocation and must never outlive its session.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct CaptureState {
    pub app_name: Option<String>,
    pub window_title: Option<String>,
    pub focused_text: Option<String>,
    pub selected_text: Option<String>,
    pub window_text: Option<String>,
    pub screenshot_jpeg: Option<Vec<u8>>,
}

impl CaptureState {
    pub fn clear(&mut self) {
        *self = Self::default();
    }

    pub fn is_empty(&self) -> bool {
        self.app_name.is_none()
            && self.window_title.is_none()
            && self.focused_text.is_none()
            && self.selected_text.is_none()
            && self.window_text.is_none()
            && self.screenshot_jpeg.is_none()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionState {
    Idle,
    Capturing,
    Editing,
    Generating,
    Ready,
    Failed,
    Closed,
}

/// State machine for one Feather invocation. Provider and platform adapters use
/// this type so closing the panel always discards the captured data.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Session {
    pub state: SessionState,
    pub capture: CaptureState,
    pub instruction: String,
    pub result: String,
    pub error: Option<String>,
}

impl Default for Session {
    fn default() -> Self {
        Self {
            state: SessionState::Idle,
            capture: CaptureState::default(),
            instruction: String::new(),
            result: String::new(),
            error: None,
        }
    }
}

impl Session {
    pub fn begin_capture(&mut self) {
        self.reset();
        self.state = SessionState::Capturing;
    }

    pub fn finish_capture(&mut self, capture: CaptureState) -> bool {
        if self.state != SessionState::Capturing {
            return false;
        }
        self.capture = capture;
        self.state = SessionState::Editing;
        true
    }

    pub fn begin_generation(&mut self, instruction: String) -> bool {
        if self.state != SessionState::Editing && self.state != SessionState::Ready {
            return false;
        }
        let instruction = instruction.trim();
        if instruction.is_empty() {
            return false;
        }
        self.instruction = instruction.to_owned();
        self.error = None;
        self.state = SessionState::Generating;
        true
    }

    pub fn finish_generation(&mut self, result: String) -> bool {
        if self.state != SessionState::Generating {
            return false;
        }
        self.result = result.trim().to_owned();
        self.state = SessionState::Ready;
        true
    }

    pub fn fail_generation(&mut self, error: String) -> bool {
        if self.state != SessionState::Generating {
            return false;
        }
        self.error = Some(error);
        self.state = SessionState::Failed;
        true
    }

    pub fn cancel_generation(&mut self) -> bool {
        if self.state != SessionState::Generating {
            return false;
        }
        self.state = SessionState::Editing;
        true
    }

    pub fn close(&mut self) {
        self.reset();
        self.state = SessionState::Closed;
    }

    fn reset(&mut self) {
        self.capture.clear();
        self.instruction.clear();
        self.result.clear();
        self.error = None;
    }
}

#[cfg(test)]
mod tests {
    use super::{CaptureState, Session, SessionState};

    #[test]
    fn closing_discards_all_captured_content() {
        let mut session = Session::default();
        session.begin_capture();
        assert!(session.finish_capture(CaptureState {
            app_name: Some("Messages".into()),
            focused_text: Some("Private draft".into()),
            screenshot_jpeg: Some(vec![1, 2, 3]),
            ..CaptureState::default()
        }));
        assert!(session.begin_generation("Make this shorter".into()));
        assert!(session.finish_generation("Short version".into()));

        session.close();

        assert_eq!(session.state, SessionState::Closed);
        assert!(session.capture.is_empty());
        assert!(session.instruction.is_empty());
        assert!(session.result.is_empty());
        assert!(session.error.is_none());
    }

    #[test]
    fn late_generation_result_is_ignored_after_cancellation() {
        let mut session = Session::default();
        session.begin_capture();
        assert!(session.finish_capture(CaptureState::default()));
        assert!(session.begin_generation("Write a reply".into()));
        assert!(session.cancel_generation());

        assert!(!session.finish_generation("Late result".into()));
        assert_eq!(session.state, SessionState::Editing);
        assert!(session.result.is_empty());
    }

    #[test]
    fn generation_requires_a_nonempty_instruction() {
        let mut session = Session::default();
        session.begin_capture();
        assert!(session.finish_capture(CaptureState::default()));

        assert!(!session.begin_generation("  \n".into()));
        assert_eq!(session.state, SessionState::Editing);
    }
}
