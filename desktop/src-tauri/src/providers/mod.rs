//! Chat backends that stream text over server-sent events. Mirrors the providers in the macOS
//! app's `FeatherCore`, so both apps send the same requests.

pub mod catalog;
pub mod stream;

use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};

use crate::core::error::{endpoint, error_message, LlmError};
use crate::core::plus;
use crate::core::prompt::{GenerationRequest, Reasoning};
use crate::core::sse::SseEvent;

pub const USER_AGENT: &str = "Feather/0.1.0";
pub const OPENCODE_GO_BASE_URL: &str = "https://opencode.ai/zen/go/v1";
pub const OPENCODE_GO_DEFAULT_MODEL: &str = "deepseek-v4.1-flash";
pub const CLAUDE_BASE_URL: &str = "https://api.anthropic.com/v1";
pub const CLAUDE_DEFAULT_MODEL: &str = "claude-haiku-5-5";
pub const CLAUDE_API_VERSION: &str = "2023-06-01";
pub const CHATGPT_ENDPOINT: &str = "https://chatgpt.com/backend-api/codex/responses";

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Chunk {
    Text(String),
    /// The last text of the response; the stream ends after it.
    FinalText(String),
    Done,
    Ignore,
}

#[derive(Clone, Debug)]
pub enum Provider {
    /// OpenCode Go's OpenAI-compatible chat completions endpoint.
    OpenCodeGo { api_key: String },
    /// ChatGPT account access through the Codex Responses API.
    ChatGpt { access_token: String, account_id: Option<String> },
    /// Anthropic's Messages API, with an API key from the Anthropic Console.
    Claude { api_key: String },
    /// Feather Plus's OpenAI-compatible endpoint. Every plan uses the server's model, so the model
    /// sent is a placeholder and the body is otherwise OpenCode Go's.
    FeatherPlus { token: String, base_url: String },
}

pub struct HttpRequest {
    pub url: reqwest::Url,
    pub headers: Vec<(&'static str, String)>,
    pub body: Value,
}

impl Provider {
    pub fn http_request(&self, request: &GenerationRequest) -> Result<HttpRequest, LlmError> {
        if request.model.is_empty() {
            return Err(LlmError::MissingModel);
        }
        let mut headers = Vec::new();
        let (url, token, body) = match self {
            Provider::OpenCodeGo { api_key } => {
                if !request.session_id.is_empty() {
                    headers.push(("x-opencode-session", request.session_id.clone()));
                }
                (endpoint(OPENCODE_GO_BASE_URL, "/chat/completions")?, api_key, chat_completions_body(request))
            }
            Provider::ChatGpt { access_token, account_id } => {
                if let Some(account_id) = account_id.as_ref().filter(|id| !id.is_empty()) {
                    headers.push(("ChatGPT-Account-Id", account_id.clone()));
                }
                if !request.session_id.is_empty() {
                    headers.push(("session-id", request.session_id.clone()));
                }
                (reqwest::Url::parse(CHATGPT_ENDPOINT).expect("valid endpoint"), access_token, responses_body(request))
            }
            Provider::Claude { api_key } => {
                headers.push(("x-api-key", api_key.clone()));
                headers.push(("anthropic-version", CLAUDE_API_VERSION.to_owned()));
                (endpoint(CLAUDE_BASE_URL, "/messages")?, api_key, claude_body(request))
            }
            Provider::FeatherPlus { token, base_url } => {
                (endpoint(base_url, "/v1/chat/completions")?, token, chat_completions_body(request))
            }
        };
        if token.is_empty() {
            return Err(LlmError::MissingApiKey);
        }
        // Anthropic authenticates with `x-api-key`, not a bearer token.
        if !matches!(self, Provider::Claude { .. }) {
            headers.push(("Authorization", format!("Bearer {token}")));
        }
        Ok(HttpRequest { url, headers, body })
    }

    /// Whether `GenerationRequest::reasoning` changes the request body. Feather Plus does not know
    /// the real model, and its proxy reports upstream 400s as 502, so the server decides.
    pub fn controls_reasoning(&self) -> bool {
        matches!(self, Provider::OpenCodeGo { .. })
    }

    /// A URL on the provider's host that is cheap to request without credentials.
    pub fn preconnect_url(&self) -> Option<reqwest::Url> {
        match self {
            Provider::OpenCodeGo { .. } => endpoint(OPENCODE_GO_BASE_URL, "/models").ok(),
            Provider::ChatGpt { .. } => reqwest::Url::parse(CHATGPT_ENDPOINT).ok(),
            Provider::Claude { .. } => endpoint(CLAUDE_BASE_URL, "/models").ok(),
            Provider::FeatherPlus { base_url, .. } => endpoint(base_url, "/health").ok(),
        }
    }

    pub fn parse(&self, event: &SseEvent) -> Result<Chunk, LlmError> {
        match self {
            Provider::OpenCodeGo { .. } | Provider::FeatherPlus { .. } => parse_chat_completions(event),
            Provider::ChatGpt { .. } => parse_responses(event),
            Provider::Claude { .. } => parse_claude(event),
        }
    }
}

pub fn default_model_for(connection: crate::settings::Connection) -> &'static str {
    use crate::settings::Connection;
    match connection {
        Connection::OpenCodeGo => OPENCODE_GO_DEFAULT_MODEL,
        Connection::ChatGpt => catalog::CHATGPT_DEFAULT_MODEL,
        Connection::Claude => CLAUDE_DEFAULT_MODEL,
        Connection::FeatherPlus => plus::DEFAULT_MODEL,
    }
}

fn image_url(image: &[u8]) -> String {
    format!("data:image/jpeg;base64,{}", STANDARD.encode(image))
}

/// Omits a token limit on purpose: servers disagree on `max_tokens` vs. `max_completion_tokens`,
/// and reasoning models reject the former.
fn chat_completions_body(request: &GenerationRequest) -> Value {
    let mut messages = vec![json!({ "role": "system", "content": request.system })];
    for (index, turn) in request.turns.iter().enumerate() {
        match (&request.image_jpeg, index) {
            (Some(image), 0) => messages.push(json!({
                "role": turn.role.as_str(),
                "content": [
                    { "type": "text", "text": turn.text },
                    { "type": "image_url", "image_url": { "url": image_url(image) } }
                ]
            })),
            _ => messages.push(json!({ "role": turn.role.as_str(), "content": turn.text })),
        }
    }
    let mut body = json!({ "model": request.model, "stream": true, "messages": messages });
    if request.reasoning == Reasoning::Minimal {
        body["reasoning_effort"] = json!("none");
    }
    body
}

fn claude_body(request: &GenerationRequest) -> Value {
    let messages: Vec<Value> = request
        .turns
        .iter()
        .enumerate()
        .map(|(index, turn)| match (&request.image_jpeg, index) {
            (Some(image), 0) => json!({
                "role": turn.role.as_str(),
                "content": [
                    { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": STANDARD.encode(image) } },
                    { "type": "text", "text": turn.text }
                ]
            }),
            _ => json!({ "role": turn.role.as_str(), "content": turn.text }),
        })
        .collect();
    json!({
        "model": request.model,
        "max_tokens": request.max_tokens,
        "stream": true,
        "system": request.system,
        "messages": messages
    })
}

fn responses_body(request: &GenerationRequest) -> Value {
    let input: Vec<Value> = request
        .turns
        .iter()
        .enumerate()
        .map(|(index, turn)| {
            let mut content = vec![json!({ "type": "input_text", "text": turn.text })];
            if let (0, Some(image)) = (index, &request.image_jpeg) {
                content.push(json!({ "type": "input_image", "image_url": image_url(image) }));
            }
            json!({ "role": turn.role.as_str(), "content": content })
        })
        .collect();
    json!({ "model": request.model, "instructions": request.system, "input": input, "stream": true })
}

fn stream_error(data: &str) -> LlmError {
    LlmError::Api(error_message(data.as_bytes()).unwrap_or_else(|| "Unknown error".to_owned()))
}

fn parse_chat_completions(event: &SseEvent) -> Result<Chunk, LlmError> {
    if event.data == "[DONE]" {
        return Ok(Chunk::Done);
    }
    let Ok(json) = serde_json::from_str::<Value>(&event.data) else {
        return Ok(Chunk::Ignore);
    };
    if json.get("error").is_some() {
        return Err(stream_error(&event.data));
    }
    let Some(choice) = json.pointer("/choices/0") else {
        return Ok(Chunk::Ignore);
    };
    let text = choice.pointer("/delta/content").and_then(Value::as_str).unwrap_or_default().to_owned();
    // Some servers keep the connection open after the final chunk instead of sending `[DONE]`, so
    // a finish reason ends the stream on its own.
    if let Some(reason) = choice.get("finish_reason").and_then(Value::as_str).filter(|reason| !reason.is_empty()) {
        if reason == "content_filter" {
            return Err(LlmError::Refused);
        }
        return Ok(if text.is_empty() { Chunk::Done } else { Chunk::FinalText(text) });
    }
    Ok(if text.is_empty() { Chunk::Ignore } else { Chunk::Text(text) })
}

fn parse_claude(event: &SseEvent) -> Result<Chunk, LlmError> {
    let Ok(json) = serde_json::from_str::<Value>(&event.data) else {
        return Ok(Chunk::Ignore);
    };
    let kind = json.get("type").and_then(Value::as_str).or(event.event.as_deref()).unwrap_or_default();
    match kind {
        "content_block_delta" => {
            let is_text = json.pointer("/delta/type").and_then(Value::as_str) == Some("text_delta");
            let text = json.pointer("/delta/text").and_then(Value::as_str).filter(|text| !text.is_empty());
            Ok(match (is_text, text) {
                (true, Some(text)) => Chunk::Text(text.to_owned()),
                _ => Chunk::Ignore,
            })
        }
        "message_delta" if json.pointer("/delta/stop_reason").and_then(Value::as_str) == Some("refusal") => Err(LlmError::Refused),
        "message_stop" => Ok(Chunk::Done),
        "error" => Err(stream_error(&event.data)),
        _ => Ok(Chunk::Ignore),
    }
}

fn parse_responses(event: &SseEvent) -> Result<Chunk, LlmError> {
    let Ok(json) = serde_json::from_str::<Value>(&event.data) else {
        return Ok(Chunk::Ignore);
    };
    if json.get("error").is_some_and(|error| !error.is_null()) {
        return Err(stream_error(&event.data));
    }
    match event.event.as_deref() {
        Some("response.output_text.delta") => {
            Ok(json.get("delta").and_then(Value::as_str).map(|text| Chunk::Text(text.to_owned())).unwrap_or(Chunk::Ignore))
        }
        Some("response.completed" | "response.done" | "response.incomplete") => Ok(Chunk::Done),
        Some("response.failed") => Err(LlmError::Api(
            json.pointer("/response/error/message").and_then(Value::as_str).unwrap_or("The response failed.").to_owned(),
        )),
        _ => Ok(Chunk::Ignore),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::prompt::{Role, Turn};

    fn request(image: Option<Vec<u8>>) -> GenerationRequest {
        GenerationRequest {
            system: "System".into(),
            turns: vec![
                Turn { role: Role::User, text: "First".into() },
                Turn { role: Role::Assistant, text: "Draft".into() },
                Turn { role: Role::User, text: "Shorter".into() },
            ],
            image_jpeg: image,
            model: "model".into(),
            max_tokens: 100,
            session_id: "session".into(),
            reasoning: Reasoning::Minimal,
        }
    }

    fn event(event: Option<&str>, data: &str) -> SseEvent {
        SseEvent { event: event.map(str::to_owned), data: data.to_owned() }
    }

    #[test]
    fn chat_completions_attach_the_image_to_the_first_turn() {
        let body = chat_completions_body(&request(Some(vec![1, 2, 3])));
        assert_eq!(body["messages"][0]["role"], "system");
        assert_eq!(body["messages"][1]["content"][1]["image_url"]["url"], "data:image/jpeg;base64,AQID");
        assert_eq!(body["messages"][3]["content"], "Shorter");
        assert_eq!(body["reasoning_effort"], "none");
        assert!(body.get("max_tokens").is_none());
    }

    #[test]
    fn responses_body_uses_instructions_and_input() {
        let body = responses_body(&request(Some(vec![1])));
        assert_eq!(body["instructions"], "System");
        assert_eq!(body["input"][0]["content"][1]["type"], "input_image");
        assert_eq!(body["input"][1]["role"], "assistant");
    }

    #[test]
    fn opencode_go_sends_the_session_header_and_bearer_token() {
        let provider = Provider::OpenCodeGo { api_key: "key".into() };
        let http = provider.http_request(&request(None)).unwrap();
        assert!(http.headers.contains(&("x-opencode-session", "session".into())));
        assert!(http.headers.contains(&("Authorization", "Bearer key".into())));

        let missing = Provider::OpenCodeGo { api_key: String::new() };
        assert_eq!(missing.http_request(&request(None)).err(), Some(LlmError::MissingApiKey));
    }

    #[test]
    fn claude_uses_the_api_key_header_and_messages_body() {
        let provider = Provider::Claude { api_key: "sk-ant".into() };
        let http = provider.http_request(&request(Some(vec![1, 2, 3]))).unwrap();
        assert_eq!(http.url.as_str(), "https://api.anthropic.com/v1/messages");
        assert!(http.headers.contains(&("x-api-key", "sk-ant".into())));
        assert!(http.headers.contains(&("anthropic-version", "2023-06-01".into())));
        assert!(!http.headers.iter().any(|(name, _)| *name == "Authorization"));
        assert_eq!(http.body["system"], "System");
        assert_eq!(http.body["max_tokens"], 100);
        assert_eq!(http.body["messages"][0]["content"][0]["source"]["data"], "AQID");
        assert_eq!(http.body["messages"][2]["content"], "Shorter");

        let missing = Provider::Claude { api_key: String::new() };
        assert_eq!(missing.http_request(&request(None)).err(), Some(LlmError::MissingApiKey));
    }

    #[test]
    fn parses_claude_events() {
        let delta = r#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#;
        assert_eq!(parse_claude(&event(Some("content_block_delta"), delta)), Ok(Chunk::Text("Hi".into())));
        assert_eq!(parse_claude(&event(Some("ping"), r#"{"type":"ping"}"#)), Ok(Chunk::Ignore));
        assert_eq!(parse_claude(&event(Some("message_stop"), r#"{"type":"message_stop"}"#)), Ok(Chunk::Done));
        assert_eq!(
            parse_claude(&event(Some("message_delta"), r#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#)),
            Err(LlmError::Refused)
        );
        assert_eq!(
            parse_claude(&event(Some("error"), r#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)),
            Err(LlmError::Api("Overloaded".into()))
        );
    }

    #[test]
    fn feather_plus_appends_the_versioned_path() {
        let provider = Provider::FeatherPlus { token: "t".into(), base_url: "https://api.example.com/".into() };
        assert_eq!(provider.http_request(&request(None)).unwrap().url.as_str(), "https://api.example.com/v1/chat/completions");
        assert!(!provider.controls_reasoning());
    }

    #[test]
    fn parses_chat_completion_chunks() {
        assert_eq!(parse_chat_completions(&event(None, "[DONE]")), Ok(Chunk::Done));
        assert_eq!(
            parse_chat_completions(&event(None, r#"{"choices":[{"delta":{"content":"Hi"}}]}"#)),
            Ok(Chunk::Text("Hi".into()))
        );
        assert_eq!(
            parse_chat_completions(&event(None, r#"{"choices":[{"delta":{"content":"!"},"finish_reason":"stop"}]}"#)),
            Ok(Chunk::FinalText("!".into()))
        );
        assert_eq!(
            parse_chat_completions(&event(None, r#"{"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#)),
            Err(LlmError::Refused)
        );
        assert_eq!(
            parse_chat_completions(&event(None, r#"{"error":{"message":"Quota"}}"#)),
            Err(LlmError::Api("Quota".into()))
        );
    }

    #[test]
    fn parses_responses_events() {
        assert_eq!(
            parse_responses(&event(Some("response.output_text.delta"), r#"{"delta":"Hi"}"#)),
            Ok(Chunk::Text("Hi".into()))
        );
        assert_eq!(parse_responses(&event(Some("response.completed"), "{}")), Ok(Chunk::Done));
        assert_eq!(
            parse_responses(&event(Some("response.failed"), r#"{"response":{"error":{"message":"Nope"}}}"#)),
            Err(LlmError::Api("Nope".into()))
        );
    }
}
