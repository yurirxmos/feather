use serde::Deserialize;

use super::stream::CLIENT;
use super::{CLAUDE_API_VERSION, CLAUDE_BASE_URL, OPENAI_BASE_URL, OPENAI_DEFAULT_MODEL, OPENCODE_GO_BASE_URL};
use crate::core::error::{endpoint, error_message, LlmError};

/// Shown until, or unless, the key's own list loads.
pub const OPENAI_FALLBACK_MODELS: [&str; 3] = [OPENAI_DEFAULT_MODEL, "gpt-5.4", "gpt-5.5"];

/// Words in the IDs of models that cannot write chat replies, such as audio, image, and embedding
/// models, or that only work through other APIs.
const OPENAI_EXCLUDED_WORDS: [&str; 13] = [
    "audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "moderation", "instruct", "codex", "pro",
    "deep-research", "computer-use",
];

fn is_openai_chat_model(id: &str) -> bool {
    let is_family = id.starts_with("gpt-") || (id.starts_with('o') && id[1..].starts_with(|c: char| c.is_ascii_digit()));
    // Dated snapshots such as gpt-5.4-2026-03-01.
    let parts: Vec<&str> = id.split('-').collect();
    let is_snapshot = parts.len() >= 4
        && parts[parts.len() - 3..].iter().zip([4, 2, 2]).all(|(part, len)| part.len() == len && part.chars().all(|c| c.is_ascii_digit()));
    let is_excluded = OPENAI_EXCLUDED_WORDS.iter().any(|word| if word.contains('-') { id.contains(word) } else { parts.contains(word) });
    is_family && !is_snapshot && !is_excluded
}

/// Keeps the GPT and o-series chat models from OpenAI's model list, newest first, without dated
/// snapshots.
pub fn parse_openai_models(body: &[u8]) -> Option<Vec<String>> {
    let json = serde_json::from_slice::<serde_json::Value>(body).ok()?;
    let mut models: Vec<(i64, String)> = json
        .get("data")?
        .as_array()?
        .iter()
        .filter_map(|entry| {
            let id = entry.get("id")?.as_str()?;
            Some((entry.get("created").and_then(|value| value.as_i64()).unwrap_or(0), id.to_owned()))
        })
        .filter(|(_, id)| is_openai_chat_model(id))
        .collect();
    models.sort_by_key(|(created, _)| std::cmp::Reverse(*created));
    Some(models.into_iter().map(|(_, id)| id).collect())
}

/// Keeps `current` when the key can use it; otherwise the default, else the newest model.
pub fn openai_model_for_key(models: &[String], current: &str) -> Option<String> {
    if models.iter().any(|model| model == current) {
        return Some(current.to_owned());
    }
    models.iter().find(|model| *model == OPENAI_DEFAULT_MODEL).or_else(|| models.first()).cloned()
}

/// Fetches the chat models available to an OpenAI API key.
pub async fn fetch_openai_models(api_key: &str) -> Result<Vec<String>, LlmError> {
    let response = CLIENT
        .get(endpoint(OPENAI_BASE_URL, "/models")?)
        .bearer_auth(api_key)
        .send()
        .await
        .map_err(|_| LlmError::Network)?;
    let status = response.status().as_u16();
    let body = response.bytes().await.map_err(|_| LlmError::Network)?;
    if !(200..300).contains(&status) {
        return Err(LlmError::Http { status, message: error_message(&body) });
    }
    match parse_openai_models(&body) {
        Some(models) if !models.is_empty() => Ok(models),
        _ => Err(LlmError::Api("OpenAI returned no chat models for this key.".into())),
    }
}

/// Sorted case-insensitively, without duplicates, always including the selected model.
pub fn sorted_unique_models(mut models: Vec<String>, selected: Option<&str>) -> Vec<String> {
    if let Some(selected) = selected.filter(|model| !model.is_empty()) {
        models.push(selected.to_owned());
    }
    models.sort_by_key(|model| model.to_lowercase());
    models.dedup();
    models
}

/// Reads the ids from Anthropic's model list, keeping its order (newest first).
pub fn parse_claude_models(body: &[u8]) -> Vec<String> {
    let Ok(json) = serde_json::from_slice::<serde_json::Value>(body) else { return Vec::new() };
    json.get("data")
        .and_then(|value| value.as_array())
        .into_iter()
        .flatten()
        .filter_map(|entry| entry.get("id").and_then(|id| id.as_str()).map(str::to_owned))
        .collect()
}

/// Fetches the models available to an Anthropic API key.
pub async fn fetch_claude_models(api_key: &str) -> Result<Vec<String>, LlmError> {
    let response = CLIENT
        .get(endpoint(CLAUDE_BASE_URL, "/models")?)
        .query(&[("limit", "100")])
        .header("x-api-key", api_key)
        .header("anthropic-version", CLAUDE_API_VERSION)
        .send()
        .await
        .map_err(|_| LlmError::Network)?;
    let status = response.status().as_u16();
    let body = response.bytes().await.map_err(|_| LlmError::Network)?;
    if !(200..300).contains(&status) {
        return Err(LlmError::Http { status, message: error_message(&body) });
    }
    let models = parse_claude_models(&body);
    if models.is_empty() {
        return Err(LlmError::Api("Anthropic returned no models for this key.".into()));
    }
    Ok(models)
}

/// Fetches the models available to an OpenCode Go API key.
pub async fn fetch_opencode_models(api_key: &str) -> Result<Vec<String>, LlmError> {
    #[derive(Deserialize)]
    struct Response {
        data: Vec<Entry>,
    }
    #[derive(Deserialize)]
    struct Entry {
        id: String,
    }

    let response = CLIENT
        .get(endpoint(OPENCODE_GO_BASE_URL, "/models")?)
        .bearer_auth(api_key)
        .send()
        .await
        .map_err(|_| LlmError::Network)?;
    let status = response.status().as_u16();
    let body = response.bytes().await.map_err(|_| LlmError::Network)?;
    if !(200..300).contains(&status) {
        return Err(LlmError::Http { status, message: error_message(&body) });
    }
    let decoded: Response =
        serde_json::from_slice(&body).map_err(|_| LlmError::Api("OpenCode Go returned an unreadable model list.".into()))?;
    Ok(sorted_unique_models(decoded.data.into_iter().map(|entry| entry.id).collect(), None))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_openai_chat_models_newest_first() {
        let body = br#"{"data":[
            {"id":"gpt-5.4","created":200},
            {"id":"gpt-5.4-mini","created":300},
            {"id":"o4-mini","created":100},
            {"id":"gpt-5.4-2026-03-01","created":250},
            {"id":"gpt-image-2","created":400},
            {"id":"gpt-realtime","created":400},
            {"id":"gpt-4o-mini-tts","created":400},
            {"id":"gpt-5.3-codex","created":400},
            {"id":"gpt-5-pro","created":400},
            {"id":"text-embedding-3-large","created":400},
            {"id":"dall-e-3","created":400},
            {"id":"omni-moderation-latest","created":400}
        ]}"#;
        assert_eq!(parse_openai_models(body), Some(vec!["gpt-5.4-mini".to_owned(), "gpt-5.4".to_owned(), "o4-mini".to_owned()]));
        assert_eq!(parse_openai_models(b"not json"), None);
    }

    #[test]
    fn an_openai_model_the_key_lacks_falls_back_to_the_default_then_the_newest() {
        let with_default = vec!["a".to_owned(), OPENAI_DEFAULT_MODEL.to_owned()];
        assert_eq!(openai_model_for_key(&with_default, "a").as_deref(), Some("a"));
        assert_eq!(openai_model_for_key(&with_default, "gone").as_deref(), Some(OPENAI_DEFAULT_MODEL));
        assert_eq!(openai_model_for_key(&["a".to_owned(), "b".to_owned()], "gone").as_deref(), Some("a"));
        assert_eq!(openai_model_for_key(&[], "a"), None);
    }

    #[test]
    fn reads_claude_models_in_the_servers_order() {
        let body = br#"{"data":[{"id":"claude-b","display_name":"B"},{"id":"claude-a"}],"has_more":false}"#;
        assert_eq!(parse_claude_models(body), vec!["claude-b", "claude-a"]);
        assert!(parse_claude_models(b"not json").is_empty());
    }

    #[test]
    fn models_are_sorted_unique_and_keep_the_selection() {
        let models = sorted_unique_models(vec!["b".into(), "A".into(), "b".into()], Some("custom"));
        assert_eq!(models, vec!["A", "b", "custom"]);
    }
}
