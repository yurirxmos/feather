//! Owns the prompt panel for one shortcut invocation: captures context, streams the reply, and
//! inserts or copies it. Mirrors `PromptController` in the macOS app. The webview only renders
//! `PanelState` and sends intents; captured content and screenshots stay in Rust.

use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use tauri::async_runtime::JoinHandle;
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewWindow};
use tokio::sync::watch;

use crate::auth;
use crate::core::context::{ContextOptions, ScreenContext};
use crate::core::error::LlmError;
use crate::core::placement::{self, Anchor};
use crate::core::prompt::{self, Exchange, Mode, RequestInput};
use crate::core::recent::{self, Direction, SavedConversation};
use crate::core::reply::Reply;
use crate::core::turn::{self, Submission, CLOSING_COUNTDOWN_SECONDS};
use crate::core::pkce;
use crate::credentials;
use crate::i18n::t;
use crate::insert;
use crate::platform::{self, Rect, Target};
use crate::providers::{stream, Provider};
use crate::settings::{write_atomically, Connection, SettingsStore};
use crate::shell::SETTINGS_LABEL;

pub const PANEL_LABEL: &str = "panel";
const PANEL_WIDTH: f64 = 600.0;
const PANEL_INSET: f64 = 18.0;
/// Every published delta re-renders the panel; a few updates per second still read as typing.
const STREAM_PUBLISH_INTERVAL: Duration = Duration::from_millis(80);

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CaptureStatus {
    ReadingScreen,
    CapturingWindow,
}

/// What `PanelView` renders. Holds no captured text beyond the selection preview.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelState {
    app_name: Option<String>,
    selected_preview: Option<String>,
    has_focused_text: bool,
    has_window_text: bool,
    window_text_was_truncated: bool,
    options: ContextOptions,
    is_capturing: bool,
    capture_status: Option<CaptureStatus>,
    /// The text to insert.
    result: String,
    streaming_result: String,
    /// What Feather says to the user, in assistant mode only.
    answer: String,
    streaming_answer: String,
    is_generating: bool,
    /// Milliseconds since the Unix epoch.
    generation_started_at: Option<u64>,
    error_message: Option<String>,
    notice: Option<String>,
    /// Bumped on every show so the view re-focuses its text field.
    focus_token: u64,
    /// An instruction to put back in the field, such as after cancelling.
    restore_instruction: Option<String>,
    /// Changes whenever `restore_instruction` is set, so the view applies it once.
    restore_token: u64,
    /// Set while ↑ and ↓ show a recent conversation.
    browsing: Option<Browsing>,
    /// The last instruction was a question on a connection that only assists typing.
    suggests_plus: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Browsing {
    /// 1 is the newest saved conversation.
    position: usize,
    count: usize,
    instruction: String,
}

#[derive(Default)]
struct Session {
    context: ScreenContext,
    options: ContextOptions,
    result: String,
    streaming_result: String,
    answer: String,
    streaming_answer: String,
    is_generating: bool,
    generation_started_at: Option<u64>,
    error_message: Option<String>,
    notice: Option<String>,
    is_capturing: bool,
    capture_status: Option<CaptureStatus>,
    focus_token: u64,
    restore_instruction: Option<String>,
    restore_token: u64,
    history: Vec<Exchange>,
    last_instruction: String,
    /// The turn state before the running generation, restored when it is cancelled.
    turn_before_generation: Option<(Vec<Exchange>, String)>,
    /// Which recent conversation ↑ brought back: `None` is this panel's own, 0 the newest saved one.
    browsing_index: Option<usize>,
    browsing_count: usize,
    /// This panel's own conversation, put back when ↓ returns to it.
    own_conversation: Option<SavedConversation>,
    /// The saved conversation shown or refined here, replaced when this one is saved.
    restored_from: Option<SavedConversation>,
    session_id: String,
    is_suspended_for_recapture: bool,
    /// The last instruction was a question on a connection that only assists typing.
    suggests_plus: bool,
}

impl Session {
    fn reset(&mut self, include_window: bool) {
        let focus_token = self.focus_token;
        let restore_token = self.restore_token;
        *self = Session {
            options: ContextOptions { include_window, ..ContextOptions::default() },
            session_id: pkce::random_string(16),
            focus_token,
            restore_token,
            ..Session::default()
        };
    }

    fn conversation(&self) -> Option<SavedConversation> {
        recent::conversation(&self.history, &self.last_instruction, &self.answer, &self.result)
    }

    /// The last response as the model wrote it, so a refinement keeps its format.
    fn raw_result(&self) -> String {
        Reply { answer: self.answer.clone(), suggestion: self.result.clone() }.raw()
    }

    /// Undoes the running generation's turn and puts its instruction back for editing.
    fn roll_back_generation(&mut self) {
        if !self.is_generating {
            return;
        }
        let instruction = std::mem::take(&mut self.last_instruction);
        if let Some((history, last_instruction)) = self.turn_before_generation.take() {
            self.history = history;
            self.last_instruction = last_instruction;
        }
        self.streaming_result.clear();
        self.streaming_answer.clear();
        self.generation_started_at = None;
        self.is_generating = false;
        self.restore_instruction = Some(instruction);
        self.restore_token += 1;
    }

    fn state(&self) -> PanelState {
        let context = &self.context;
        PanelState {
            app_name: context.app_name.clone(),
            selected_preview: context.selected_text.as_ref().map(|text| text.replace('\n', " ").chars().take(240).collect()),
            has_focused_text: context.focused_text.is_some(),
            has_window_text: context.window_text.is_some(),
            window_text_was_truncated: context.window_text_was_truncated,
            options: self.options,
            is_capturing: self.is_capturing,
            capture_status: self.capture_status,
            result: self.result.clone(),
            streaming_result: self.streaming_result.clone(),
            answer: self.answer.clone(),
            streaming_answer: self.streaming_answer.clone(),
            is_generating: self.is_generating,
            generation_started_at: self.generation_started_at,
            error_message: self.error_message.clone(),
            notice: self.notice.clone(),
            focus_token: self.focus_token,
            restore_instruction: self.restore_instruction.clone(),
            restore_token: self.restore_token,
            browsing: self.browsing_index.map(|index| Browsing {
                position: index + 1,
                count: self.browsing_count,
                instruction: self.last_instruction.clone(),
            }),
            suggests_plus: self.suggests_plus,
        }
    }
}

#[derive(Default)]
struct Inner {
    session: Session,
    target: Option<Target>,
    /// Whether Feather's own Settings window, such as the welcome guide's practice box, had focus
    /// when the shortcut was pressed. Replies go straight into its field instead of being pasted.
    own_window: bool,
    /// Bumped whenever the panel hides, so late capture results are dropped.
    epoch: u64,
    is_presenting: bool,
    anchor: Option<Anchor>,
    capture_task: Option<JoinHandle<()>>,
    screenshot_task: Option<JoinHandle<()>>,
    generation_task: Option<JoinHandle<()>>,
    closing_task: Option<JoinHandle<()>>,
    /// True once the text capture of this show has finished; generation waits for it.
    captured: Option<watch::Sender<bool>>,
    /// The last few conversations, newest first, and the file that keeps them on this computer.
    recent: Vec<SavedConversation>,
    recent_path: Option<PathBuf>,
}

impl Inner {
    /// Keeps the finished conversation on this computer for ↑. Screen context is not part of it.
    fn save_conversation(&mut self) {
        if self.session.is_generating {
            return;
        }
        let Some(conversation) = self.session.conversation() else { return };
        let updated = recent::saving(conversation, self.session.restored_from.as_ref(), &self.recent);
        if updated == self.recent {
            return;
        }
        self.recent = updated;
        if let Some(path) = &self.recent_path {
            if let Err(error) = write_atomically(path, &recent::encode(&self.recent)) {
                eprintln!("Feather could not save recent conversations: {error}");
            }
        }
    }

    /// Stops capturing; `everything` also stops the generation and the closing countdown.
    fn abort_tasks(&mut self, everything: bool) {
        for task in [self.capture_task.take(), self.screenshot_task.take()].into_iter().flatten() {
            task.abort();
        }
        if everything {
            for task in [self.generation_task.take(), self.closing_task.take()].into_iter().flatten() {
                task.abort();
            }
        }
        if let Some(captured) = self.captured.take() {
            let _ = captured.send(true);
        }
    }
}

#[derive(Clone)]
pub struct PromptController {
    app: AppHandle,
    inner: Arc<Mutex<Inner>>,
}

impl PromptController {
    pub fn new(app: AppHandle) -> Self {
        let recent_path = app.path().app_data_dir().ok().map(|dir| dir.join("recent-conversations.json"));
        let recent = recent::decode(recent_path.as_ref().and_then(|path| std::fs::read(path).ok()).as_deref());
        let inner = Inner { recent, recent_path, ..Inner::default() };
        Self { app, inner: Arc::new(Mutex::new(inner)) }
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn panel(&self) -> Option<WebviewWindow> {
        self.app.get_webview_window(PANEL_LABEL)
    }

    fn settings(&self) -> crate::settings::Settings {
        self.app.state::<SettingsStore>().current()
    }

    fn publish(&self, inner: &Inner) {
        let _ = self.app.emit_to(PANEL_LABEL, "prompt-state", inner.session.state());
    }

    pub fn state(&self) -> PanelState {
        self.lock().session.state()
    }

    pub fn toggle(&self) {
        let visible = self.panel().and_then(|panel| panel.is_visible().ok()).unwrap_or(false);
        if visible || self.lock().is_presenting {
            self.suspend_for_recapture();
        } else {
            self.show();
        }
    }

    // MARK: Showing

    fn show(&self) {
        // Remember the target before the panel takes keyboard focus.
        let target = platform::foreground_target();
        let own_window = target.is_none()
            && self.app.get_webview_window(SETTINGS_LABEL).and_then(|window| window.is_focused().ok()).unwrap_or(false);
        let settings = self.settings();
        let provider = self.provider_for_preconnect(settings.connection, &settings.plus_base_url);
        {
            let mut inner = self.lock();
            if inner.session.is_suspended_for_recapture {
                inner.session.options.include_window = settings.include_screenshot;
            } else {
                inner.save_conversation();
                inner.session.reset(settings.include_screenshot);
            }
            inner.target = target;
            inner.own_window = own_window;
            inner.is_presenting = true;
        }
        // Connecting can take seconds on a cold or flaky network; do it while the user types.
        if let Some(provider) = provider {
            tauri::async_runtime::spawn(async move { stream::preconnect(&provider).await });
        }
        self.start_capture(settings.include_screenshot);
    }

    /// Hides the panel without discarding the session, so the user can scroll and capture again.
    /// A running generation keeps going, so clicking away to reread the conversation loses nothing.
    pub fn suspend_for_recapture(&self) {
        let mut inner = self.lock();
        inner.abort_tasks(false);
        inner.epoch += 1;
        inner.session.is_capturing = false;
        inner.session.capture_status = None;
        inner.session.is_suspended_for_recapture = true;
        inner.is_presenting = false;
        drop(inner);
        if let Some(panel) = self.panel() {
            let _ = panel.hide();
        }
    }

    /// Closes the panel and discards everything captured for this invocation.
    pub fn close(&self) {
        let mut inner = self.lock();
        inner.abort_tasks(true);
        inner.epoch += 1;
        inner.is_presenting = false;
        inner.target = None;
        inner.own_window = false;
        inner.save_conversation();
        inner.session.reset(false);
        self.publish(&inner);
        drop(inner);
        if let Some(panel) = self.panel() {
            let _ = panel.hide();
        }
    }

    fn start_capture(&self, include_screenshot: bool) {
        let mut inner = self.lock();
        let Some(target) = inner.target.clone() else {
            drop(inner);
            self.position_panel(None);
            self.present_panel();
            return;
        };
        let epoch = inner.epoch;
        inner.session.context.app_name = target.app_name.clone();
        inner.session.context.app_id = target.app_id.clone();
        inner.session.is_capturing = true;
        inner.session.capture_status = Some(CaptureStatus::ReadingScreen);
        let (captured, _) = watch::channel(false);
        inner.captured = Some(captured);
        drop(inner);

        let controller = self.clone();
        let task = tauri::async_runtime::spawn(async move {
            let shot_first = include_screenshot && platform::CAPTURES_SCREENSHOT_BEFORE_PANEL;
            let capture_target = target.clone();
            let Ok((snapshot, early_screenshot)) = tauri::async_runtime::spawn_blocking(move || {
                let screenshot = shot_first.then(|| platform::screenshot_jpeg(&capture_target, None)).flatten();
                (platform::capture(&capture_target), screenshot)
            })
            .await
            else {
                return;
            };

            {
                let mut inner = controller.lock();
                if inner.epoch != epoch {
                    return;
                }
                let context = &mut inner.session.context;
                context.window_title = snapshot.window_title.clone().or(context.window_title.take());
                context.focused_text = snapshot.focused_text.clone().or(context.focused_text.take());
                context.selected_text = snapshot.selected_text.clone().or(context.selected_text.take());
                context.window_text = turn::merge_window_text(snapshot.window_text.clone(), context.window_text.take());
                context.window_text_was_truncated |= snapshot.window_text_was_truncated;
                if let Some(captured) = inner.captured.take() {
                    let _ = captured.send(true);
                }
            }
            controller.position_panel(snapshot.window_frame);
            controller.present_panel();

            let mut inner = controller.lock();
            if inner.epoch != epoch {
                return;
            }
            if !include_screenshot || shot_first {
                if early_screenshot.is_some() {
                    inner.session.context.screenshot_jpeg = early_screenshot;
                }
                inner.session.is_capturing = false;
                inner.session.capture_status = None;
                controller.publish(&inner);
                return;
            }
            // A screenshot improves visual context but must not delay a submitted prompt, so it
            // runs after the text capture that generation waits for.
            inner.session.capture_status = Some(CaptureStatus::CapturingWindow);
            controller.publish(&inner);
            let frame = snapshot.window_frame;
            let screenshot_controller = controller.clone();
            inner.screenshot_task = Some(tauri::async_runtime::spawn(async move {
                let jpeg = tauri::async_runtime::spawn_blocking(move || platform::screenshot_jpeg(&target, frame)).await.ok().flatten();
                let mut inner = screenshot_controller.lock();
                if inner.epoch != epoch {
                    return;
                }
                inner.session.context.screenshot_jpeg = jpeg;
                inner.session.is_capturing = false;
                inner.session.capture_status = None;
                screenshot_controller.publish(&inner);
            }));
        });
        self.lock().capture_task = Some(task);
    }

    /// Places the panel at the bottom of the target window's monitor, or the one under the
    /// pointer when the window is unknown.
    fn position_panel(&self, window_frame: Option<Rect>) {
        let Some(panel) = self.panel() else { return };
        let point = match window_frame {
            Some(frame) => (f64::from(frame.x) + f64::from(frame.width) / 2.0, f64::from(frame.y) + f64::from(frame.height) / 2.0),
            None => self.app.cursor_position().map(|position| (position.x, position.y)).unwrap_or((0.0, 0.0)),
        };
        let monitor = self
            .app
            .monitor_from_point(point.0, point.1)
            .ok()
            .flatten()
            .or_else(|| self.app.primary_monitor().ok().flatten());
        let Some(monitor) = monitor else { return };
        let scale = monitor.scale_factor();
        let area = monitor.work_area();
        let work_area = Rect { x: area.position.x, y: area.position.y, width: area.size.width, height: area.size.height };
        let width = (PANEL_WIDTH * scale).round() as u32;
        let anchor = placement::anchor(width, window_frame, work_area, (PANEL_INSET * scale).round() as i32);
        self.lock().anchor = Some(anchor);
        let height = panel.outer_size().map(|size| size.height).unwrap_or(80);
        let _ = panel.set_position(PhysicalPosition::new(anchor.x, anchor.bottom - height as i32));
    }

    /// Resizes the panel to its content, growing upward from the anchored bottom edge.
    pub fn resize_panel(&self, height: f64) {
        let Some(panel) = self.panel() else { return };
        let scale = panel.scale_factor().unwrap_or(1.0);
        let size = PhysicalSize::new((PANEL_WIDTH * scale).round() as u32, (height.max(40.0) * scale).round() as u32);
        let _ = panel.set_size(size);
        let anchor = self.lock().anchor;
        if let Some(anchor) = anchor {
            let _ = panel.set_position(PhysicalPosition::new(anchor.x, anchor.bottom - size.height as i32));
        }
    }

    fn present_panel(&self) {
        let mut inner = self.lock();
        if !inner.is_presenting {
            return;
        }
        inner.is_presenting = false;
        inner.session.is_suspended_for_recapture = false;
        inner.session.focus_token += 1;
        self.publish(&inner);
        drop(inner);
        if let Some(panel) = self.panel() {
            let _ = panel.show();
            let _ = panel.set_focus();
        }
    }

    // MARK: Actions

    pub fn submit(&self, instruction: &str) {
        let submission = {
            let inner = self.lock();
            turn::submission(instruction, &inner.session.result, &inner.session.answer, inner.session.is_generating)
        };
        match submission {
            Submission::Generate(text) => self.generate(text),
            Submission::Insert => self.insert(),
            Submission::Copy => self.copy_result(),
            Submission::None => {}
        }
    }

    /// A new instruction after a result refines that result.
    fn generate(&self, instruction: String) {
        let mut inner = self.lock();
        let session = &mut inner.session;
        session.turn_before_generation = Some((session.history.clone(), session.last_instruction.clone()));
        let raw = session.raw_result();
        session.history = turn::history(&session.history, &session.last_instruction, &raw, session.is_generating);
        session.last_instruction = instruction;
        // A refined conversation is this panel's own again, and replaces the one it came from.
        session.browsing_index = None;
        drop(inner);
        self.run();
    }

    pub fn regenerate(&self) {
        let mut inner = self.lock();
        if inner.session.last_instruction.is_empty() || inner.session.is_generating {
            return;
        }
        let session = &mut inner.session;
        session.turn_before_generation = Some((session.history.clone(), session.last_instruction.clone()));
        drop(inner);
        self.run();
    }

    /// Stops the stream, keeps the previous result, and puts the instruction back for editing.
    pub fn cancel_generation(&self) {
        let mut inner = self.lock();
        if !inner.session.is_generating {
            return;
        }
        if let Some(task) = inner.generation_task.take() {
            task.abort();
        }
        inner.session.roll_back_generation();
        self.publish(&inner);
    }

    /// ↑ and ↓ with an empty field move through recent conversations.
    pub fn browse(&self, direction: Direction) {
        let mut inner = self.lock();
        if inner.session.is_generating {
            return;
        }
        let index = recent::browse(inner.session.browsing_index, direction, inner.recent.len());
        if index == inner.session.browsing_index {
            return;
        }
        let saved = index.map(|index| inner.recent[index].clone());
        let count = inner.recent.len();
        let session = &mut inner.session;
        if session.browsing_index.is_none() {
            session.own_conversation = session.conversation();
        }
        let shown = saved.clone().or_else(|| session.own_conversation.clone()).unwrap_or_default();
        session.history = shown.history;
        session.last_instruction = shown.last_instruction;
        session.answer = shown.answer;
        session.result = shown.result;
        session.restored_from = saved;
        session.browsing_index = index;
        session.browsing_count = count;
        session.error_message = None;
        session.notice = None;
        session.suggests_plus = false;
        self.publish(&inner);
    }

    pub fn toggle_option(&self, option: &str) {
        let mut inner = self.lock();
        let options = &mut inner.session.options;
        match option {
            "app" => options.include_app = !options.include_app,
            "selection" => options.include_selection = !options.include_selection,
            "windowText" => options.include_window_text = !options.include_window_text,
            _ => return,
        }
        self.publish(&inner);
    }

    fn run(&self) {
        let settings = self.settings();
        // Only the paid plans answer questions; the free version assists typing.
        let mode = if settings.connection == Connection::FeatherPlus { Mode::Assistant } else { Mode::TypeAssist };
        let mut inner = self.lock();
        if let Some(task) = inner.generation_task.take() {
            task.abort();
        }
        let session = &mut inner.session;
        session.streaming_result.clear();
        session.streaming_answer.clear();
        session.error_message = None;
        session.notice = None;
        session.suggests_plus = mode == Mode::TypeAssist && settings.plus_enabled && turn::looks_like_question(&session.last_instruction);
        session.is_generating = true;
        session.generation_started_at = Some(now_millis());
        let mut captured = inner.captured.as_ref().map(|sender| sender.subscribe());
        self.publish(&inner);

        let controller = self.clone();
        let task = tauri::async_runtime::spawn(async move {
            if let Some(captured) = captured.as_mut() {
                let _ = captured.wait_for(|done| *done).await;
            }
            let provider = match controller.provider(settings.connection, &settings.plus_base_url).await {
                Ok(provider) => provider,
                Err(message) => {
                    let mut inner = controller.lock();
                    inner.session.error_message = Some(message);
                    inner.session.is_generating = false;
                    controller.publish(&inner);
                    return;
                }
            };
            let request = {
                let inner = controller.lock();
                let session = &inner.session;
                let writing_preferences = settings.reply_style().writing_preferences(&settings.custom_instructions);
                prompt::request(RequestInput {
                    instruction: &session.last_instruction,
                    context: &session.context,
                    options: session.options,
                    history: &session.history,
                    model: &settings.model,
                    session_id: &session.session_id,
                    custom_instructions: &writing_preferences,
                    mode,
                })
            };

            let started = Instant::now();
            let mut first_text_after = None;
            let mut text = String::new();
            let mut published = Instant::now();
            let outcome = stream::generate(&provider, request, |chunk| {
                text.push_str(chunk);
                first_text_after.get_or_insert_with(|| started.elapsed());
                if published.elapsed() >= STREAM_PUBLISH_INTERVAL {
                    let reply = Reply::parse(&text, mode);
                    let mut inner = controller.lock();
                    inner.session.streaming_result = reply.suggestion;
                    inner.session.streaming_answer = reply.answer;
                    controller.publish(&inner);
                    published = Instant::now();
                }
            })
            .await;

            let mut inner = controller.lock();
            let partial = Reply::parse(&text, mode);
            let label = match outcome {
                Ok(()) => {
                    inner.session.result = partial.suggestion;
                    inner.session.answer = partial.answer;
                    "completed"
                }
                Err(LlmError::TimedOut) if !partial.suggestion.is_empty() || !partial.answer.is_empty() => {
                    inner.session.result = partial.suggestion;
                    inner.session.answer = partial.answer;
                    inner.session.notice = Some(t("Stopped after 1 minute. Review the text before inserting it."));
                    "timed_out_with_text"
                }
                Err(error) => {
                    inner.session.error_message = Some(error.message());
                    "failed"
                }
            };
            inner.session.streaming_result.clear();
            inner.session.streaming_answer.clear();
            inner.session.is_generating = false;
            inner.session.turn_before_generation = None;
            controller.publish(&inner);
            // Timings only; screen content, instructions, and responses are never logged.
            eprintln!(
                "generation {label}: first_text={} total={:.2}s",
                first_text_after.map(|duration| format!("{:.2}s", duration.as_secs_f64())).unwrap_or_else(|| "none".into()),
                started.elapsed().as_secs_f64()
            );
        });
        inner.generation_task = Some(task);
    }

    async fn provider(&self, connection: Connection, plus_base_url: &str) -> Result<Provider, String> {
        match connection {
            Connection::OpenCodeGo => Ok(Provider::OpenCodeGo { api_key: credentials::api_key().unwrap_or_default() }),
            Connection::Claude => Ok(Provider::Claude { api_key: credentials::claude_api_key().unwrap_or_default() }),
            Connection::ChatGpt => {
                let credentials = auth::chatgpt::valid_credentials().await?;
                Ok(Provider::ChatGpt { access_token: credentials.access_token, account_id: credentials.account_id })
            }
            Connection::FeatherPlus => credentials::plus_token()
                .map(|token| Provider::FeatherPlus { token, base_url: plus_base_url.to_owned() })
                .ok_or_else(|| t("Sign in to Feather Plus in Settings.")),
        }
    }

    /// A provider for warming the connection; it is never used to send credentials.
    fn provider_for_preconnect(&self, connection: Connection, plus_base_url: &str) -> Option<Provider> {
        Some(match connection {
            Connection::OpenCodeGo => Provider::OpenCodeGo { api_key: String::new() },
            Connection::ChatGpt => Provider::ChatGpt { access_token: String::new(), account_id: None },
            Connection::Claude => Provider::Claude { api_key: String::new() },
            Connection::FeatherPlus => Provider::FeatherPlus { token: String::new(), base_url: plus_base_url.to_owned() },
        })
    }

    fn insert(&self) {
        let (text, target, own_window) = {
            let inner = self.lock();
            (inner.session.result.clone(), inner.target.clone(), inner.own_window)
        };
        if text.is_empty() {
            return;
        }
        if let Some(settings) = self.app.get_webview_window(SETTINGS_LABEL).filter(|_| own_window) {
            self.close();
            let _ = settings.set_focus();
            let _ = self.app.emit_to(SETTINGS_LABEL, "insert-text", text);
            return;
        }
        let can_paste = insert::can_paste();
        let Some(target) = target.filter(|_| can_paste) else {
            insert::copy(&text);
            self.start_closing_countdown(Some(if can_paste {
                t("Copied. Paste it with Ctrl+V.")
            } else {
                t("Copied. This session can't insert text automatically, so paste it with Ctrl+V.")
            }));
            return;
        };
        self.close();
        tauri::async_runtime::spawn_blocking(move || insert::paste(&text, &target));
    }

    pub fn copy_result(&self) {
        let text = {
            let inner = self.lock();
            turn::copyable_text(&inner.session.result, &inner.session.answer).to_owned()
        };
        if text.is_empty() {
            return;
        }
        insert::copy(&text);
        self.start_closing_countdown(None);
    }

    /// An explanation of why Insert copied instead stays up longer than the plain notice.
    fn start_closing_countdown(&self, explanation: Option<String>) {
        let controller = self.clone();
        let mut inner = self.lock();
        if let Some(task) = inner.closing_task.take() {
            task.abort();
        }
        let hold = if explanation.is_some() { Duration::from_secs(4) } else { Duration::from_millis(800) };
        inner.session.notice = Some(explanation.unwrap_or_else(|| t("Copied to clipboard.")));
        self.publish(&inner);
        inner.closing_task = Some(tauri::async_runtime::spawn(async move {
            tokio::time::sleep(hold).await;
            for seconds in CLOSING_COUNTDOWN_SECONDS {
                {
                    let mut inner = controller.lock();
                    inner.session.notice = Some(t("Closing in {seconds}…").replace("{seconds}", &seconds.to_string()));
                    controller.publish(&inner);
                }
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            // `close` aborts this task, so detach it first.
            controller.lock().closing_task = None;
            controller.close();
        }));
    }
}

fn now_millis() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|duration| duration.as_millis() as u64).unwrap_or(0)
}
