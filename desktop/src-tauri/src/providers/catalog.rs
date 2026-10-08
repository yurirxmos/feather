use serde::{Deserialize, Serialize};

use super::stream::CLIENT;
use super::{CLAUDE_API_VERSION, CLAUDE_BASE_URL, OPENCODE_GO_BASE_URL};
use crate::core::error::{endpoint, error_message, LlmError};

#[derive(Clone, Debug, Serialize)]
pub struct Model {
    pub id: &'static str,
    pub name: &'static str,
}

/// Models exposed by OpenCode's ChatGPT/Codex OAuth integration.
pub const CHATGPT_MODELS: [Model; 6] = [
    Model { id: "gpt-6-luna", name: "GPT-6 Luna" },
    Model { id: "gpt-6-sol", name: "GPT-6 Sol" },
    Model { id: "gpt-5.5", name: "GPT-5.5" },
    Model { id: "gpt-5.4", name: "GPT-5.4" },
    Model { id: CHATGPT_DEFAULT_MODEL, name: "GPT-5.4 Mini · Fast" },
    Model { id: "gpt-5.3-codex-spark", name: "GPT-5.3 Codex Spark" },
];

pub const CHATGPT_DEFAULT_MODEL: &str = "gpt-5.4-mini";

/// The Codex backend lists only the models the signed-in account can use, and hides the ones newer
/// than the client version it is told about.
const CHATGPT_MODELS_URL: &str = "https://chatgpt.com/backend-api/codex/models";
const CHATGPT_CLIENT_VERSION: &str = "0.159.0";

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ChatGptModel {
    pub id: String,
    pub name: String,
}

/// Reads the model list, keeping the server's order. Accepts `{"models": [...]}` or a bare array,
/// with each entry naming itself by `slug`, `id`, or `model`, and skips hidden ones.
pub fn parse_chatgpt_models(body: &[u8]) -> Vec<ChatGptModel> {
    let Ok(json) = serde_json::from_slice::<serde_json::Value>(body) else { return Vec::new() };
    let entries = json.get("models").and_then(|value| value.as_array()).or_else(|| json.as_array());
    let mut models: Vec<ChatGptModel> = Vec::new();
    for entry in entries.into_iter().flatten() {
        let text = |name: &str| entry.get(name).and_then(|value| value.as_str()).filter(|value| !value.is_empty());
        let Some(id) = text("slug").or_else(|| text("id")).or_else(|| text("model")) else { continue };
        if matches!(text("visibility"), Some("hide" | "hidden" | "none")) || models.iter().any(|model| model.id == id) {
            continue;
        }
        let name = text("display_name").or_else(|| text("name")).unwrap_or(id);
        models.push(ChatGptModel { id: id.to_owned(), name: name.to_owned() });
    }
    models
}

/// Keeps `current` when the account can use it; otherwise the fast default, else the first model.
pub fn chatgpt_model_for_account(models: &[ChatGptModel], current: &str) -> Option<String> {
    if models.iter().any(|model| model.id == current) {
        return Some(current.to_owned());
    }
    models
        .iter()
        .find(|model| model.id == CHATGPT_DEFAULT_MODEL)
        .or_else(|| models.first())
        .map(|model| model.id.clone())
}

/// Fetches the models the signed-in ChatGPT account can use.
pub async fn fetch_chatgpt_models(access_token: &str, account_id: Option<&str>) -> Result<Vec<ChatGptModel>, LlmError> {
    let mut request = CLIENT.get(CHATGPT_MODELS_URL).query(&[("client_version", CHATGPT_CLIENT_VERSION)]).bearer_auth(access_token);
    if let Some(account_id) = account_id.filter(|id| !id.is_empty()) {
        request = request.header("ChatGPT-Account-Id", account_id);
    }
    let response = request.send().await.map_err(|_| LlmError::Network)?;
    let status = response.status().as_u16();
    let body = response.bytes().await.map_err(|_| LlmError::Network)?;
    if !(200..300).contains(&status) {
        return Err(LlmError::Http { status, message: error_message(&body) });
    }
    let models = parse_chatgpt_models(&body);
    if models.is_empty() {
        return Err(LlmError::Api("ChatGPT returned no models for this account.".into()));
    }
    Ok(models)
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
    fn the_chatgpt_default_is_the_fast_model() {
        let fast = CHATGPT_MODELS.iter().find(|model| model.name.to_lowercase().contains("fast")).unwrap();
        assert_eq!(fast.id, CHATGPT_DEFAULT_MODEL);
    }

    #[test]
    fn reads_the_account_models_in_server_order() {
        let body = br#"{"models":[
            {"slug":"gpt-5.5","display_name":"GPT-5.5","visibility":"list"},
            {"slug":"internal","visibility":"hide"},
            {"id":"gpt-5.4-mini"},
            {"slug":"gpt-5.5"}
        ]}"#;
        let models = parse_chatgpt_models(body);
        assert_eq!(
            models,
            vec![
                ChatGptModel { id: "gpt-5.5".into(), name: "GPT-5.5".into() },
                ChatGptModel { id: "gpt-5.4-mini".into(), name: "gpt-5.4-mini".into() },
            ]
        );
        assert_eq!(parse_chatgpt_models(br#"[{"slug":"a"}]"#).len(), 1);
        assert!(parse_chatgpt_models(b"not json").is_empty());
    }

    #[test]
    fn a_model_the_account_lacks_falls_back_to_the_default_then_the_first() {
        let with_default = parse_chatgpt_models(br#"{"models":[{"slug":"a"},{"slug":"gpt-5.4-mini"}]}"#);
        assert_eq!(chatgpt_model_for_account(&with_default, "a").as_deref(), Some("a"));
        assert_eq!(chatgpt_model_for_account(&with_default, "gone").as_deref(), Some("gpt-5.4-mini"));
        let without_default = parse_chatgpt_models(br#"{"models":[{"slug":"a"},{"slug":"b"}]}"#);
        assert_eq!(chatgpt_model_for_account(&without_default, "gpt-5.4-mini").as_deref(), Some("a"));
        assert_eq!(chatgpt_model_for_account(&[], "a"), None);
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
