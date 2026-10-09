use std::collections::HashSet;
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use futures_util::StreamExt;

use super::{Chunk, Provider, USER_AGENT};
use crate::core::error::{error_message, LlmError};
use crate::core::prompt::{GenerationRequest, Reasoning};
use crate::core::sse::SseParser;

/// The longest one generation may take, from sending the request to its last text. A typing
/// assistant that needs longer is stuck, not thinking.
pub const RESPONSE_DEADLINE: Duration = Duration::from_secs(60);

/// How long the stream may stay silent after its first text before it ends with
/// `LlmError::Stalled`. Guards against servers that never close the connection; the caller keeps
/// the text so far, but it may be incomplete.
const IDLE_TIMEOUT: Duration = Duration::from_secs(10);

const MAX_ERROR_BODY_BYTES: usize = 64_000;

/// One client for every request, so a preconnect leaves a warm connection in its pool.
pub static CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(15))
        .build()
        .expect("the HTTP client could not be created")
});

/// Models that returned HTTP 400 for `Reasoning::Minimal` during this launch.
static MINIMAL_REJECTED: LazyLock<Mutex<HashSet<String>>> = LazyLock::new(Default::default);

/// Opens the connection to the provider before the prompt is ready, so DNS, TCP, and TLS are done
/// when the user submits. Sends no credentials, prompt, or screen content.
pub async fn preconnect(provider: &Provider) {
    if let Some(url) = provider.preconnect_url() {
        let _ = CLIENT.head(url).timeout(Duration::from_secs(10)).send().await;
    }
}

/// Streams text deltas to `on_text`. Dropping the future cancels the HTTP request. Fails with
/// `LlmError::TimedOut` once the deadline passes; text delivered before that stays delivered, so
/// the caller can keep a partial response.
pub async fn generate(provider: &Provider, request: GenerationRequest, on_text: impl FnMut(&str)) -> Result<(), LlmError> {
    match tokio::time::timeout(RESPONSE_DEADLINE, run(provider, request, on_text)).await {
        Ok(result) => result,
        Err(_) => Err(LlmError::TimedOut),
    }
}

async fn run(provider: &Provider, mut request: GenerationRequest, mut on_text: impl FnMut(&str)) -> Result<(), LlmError> {
    if !provider.controls_reasoning() || rejects_minimal(&request.model) {
        request.reasoning = Reasoning::ProviderDefault;
    }
    let mut response = open(provider, &request).await?;
    // Some models reject the reasoning control. Ask again with the model's default and remember
    // it, so later requests skip the failed attempt.
    if response.status().as_u16() == 400 && request.reasoning == Reasoning::Minimal {
        request.reasoning = Reasoning::ProviderDefault;
        response = open(provider, &request).await?;
        if response.status().is_success() {
            if let Ok(mut models) = MINIMAL_REJECTED.lock() {
                models.insert(request.model.clone());
            }
        }
    }
    if !response.status().is_success() {
        let status = response.status().as_u16();
        let body = read_error_body(response).await;
        return Err(LlmError::Http { status, message: error_message(&body) });
    }

    let mut parser = SseParser::default();
    let mut pending = Vec::new();
    let mut bytes = response.bytes_stream();
    let mut saw_text = false;

    loop {
        let next = if saw_text {
            match tokio::time::timeout(IDLE_TIMEOUT, bytes.next()).await {
                Ok(next) => next,
                Err(_) => return Err(LlmError::Stalled),
            }
        } else {
            bytes.next().await
        };
        let Some(chunk) = next else { break };
        pending.extend_from_slice(&chunk.map_err(|_| LlmError::Network)?);
        let text = take_utf8(&mut pending);
        for event in parser.push(&text) {
            match provider.parse(&event)? {
                Chunk::Text(text) => {
                    saw_text = true;
                    on_text(&text);
                }
                Chunk::FinalText(text) => {
                    on_text(&text);
                    return Ok(());
                }
                Chunk::Done => return Ok(()),
                Chunk::Ignore => {}
            }
        }
    }
    for event in parser.finish() {
        match provider.parse(&event)? {
            Chunk::Text(text) | Chunk::FinalText(text) => on_text(&text),
            Chunk::Done | Chunk::Ignore => {}
        }
    }
    Ok(())
}

async fn open(provider: &Provider, request: &GenerationRequest) -> Result<reqwest::Response, LlmError> {
    let http = provider.http_request(request)?;
    let mut builder = CLIENT.post(http.url).json(&http.body);
    for (name, value) in http.headers {
        builder = builder.header(name, value);
    }
    builder.send().await.map_err(|_| LlmError::Network)
}

fn rejects_minimal(model: &str) -> bool {
    MINIMAL_REJECTED.lock().map(|models| models.contains(model)).unwrap_or(false)
}

async fn read_error_body(response: reqwest::Response) -> Vec<u8> {
    let mut body = Vec::new();
    let mut bytes = response.bytes_stream();
    while let Some(Ok(chunk)) = bytes.next().await {
        body.extend_from_slice(&chunk);
        if body.len() >= MAX_ERROR_BODY_BYTES {
            body.truncate(MAX_ERROR_BODY_BYTES);
            break;
        }
    }
    body
}

/// Removes and returns the longest valid UTF-8 prefix, keeping a split character for later.
fn take_utf8(pending: &mut Vec<u8>) -> String {
    let valid = match std::str::from_utf8(pending) {
        Ok(_) => pending.len(),
        Err(error) if error.error_len().is_none() => error.valid_up_to(),
        // Invalid bytes are not a split character; decode them lossily so the stream moves on.
        Err(_) => return String::from_utf8_lossy(&std::mem::take(pending)).into_owned(),
    };
    let rest = pending.split_off(valid);
    String::from_utf8(std::mem::replace(pending, rest)).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::take_utf8;

    #[test]
    fn keeps_a_character_split_across_chunks() {
        let mut pending = "olá".as_bytes()[..3].to_vec();
        assert_eq!(take_utf8(&mut pending), "ol");
        pending.extend_from_slice(&"olá".as_bytes()[3..]);
        assert_eq!(take_utf8(&mut pending), "á");
        assert!(pending.is_empty());
    }
}
