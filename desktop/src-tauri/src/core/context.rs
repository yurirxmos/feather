/// What was on screen when the shortcut was pressed. Captured once per invocation and discarded
/// when the prompt panel closes.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ScreenContext {
    pub app_name: Option<String>,
    /// The executable or window class, the closest desktop equivalent of a macOS bundle ID.
    pub app_id: Option<String>,
    pub window_title: Option<String>,
    pub focused_text: Option<String>,
    pub selected_text: Option<String>,
    pub window_text: Option<String>,
    pub window_text_was_truncated: bool,
    /// The shortcut was pressed while typing in a field, such as a message or email body.
    pub focus_is_in_text_field: bool,
    pub screenshot_jpeg: Option<Vec<u8>>,
}

/// Which parts of the captured context the user allowed to be sent.
#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextOptions {
    pub include_app: bool,
    pub include_focused_text: bool,
    pub include_selection: bool,
    pub include_window_text: bool,
    pub include_window: bool,
}

impl Default for ContextOptions {
    fn default() -> Self {
        Self {
            include_app: true,
            include_focused_text: true,
            include_selection: true,
            include_window_text: true,
            include_window: true,
        }
    }
}
