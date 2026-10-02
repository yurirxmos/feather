use serde::{Deserialize, Serialize};

use super::stream::CLIENT;
use super::OPENCODE_GO_BASE_URL;
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
    Model { id: "gpt-5.4-mini", name: "GPT-5.4 Mini · Fast" },
    Model { id: "gpt-5.3-codex-spark", name: "GPT-5.3 Codex Spark" },
];

pub const CHATGPT_DEFAULT_MODEL: &str = "gpt-5.4-mini";

/// Sorted case-insensitively, without duplicates, always including the selected model.
pub fn sorted_unique_models(mut models: Vec<String>, selected: Option<&str>) -> Vec<String> {
    if let Some(selected) = selected.filter(|model| !model.is_empty()) {
        models.push(selected.to_owned());
    }
    models.sort_by_key(|model| model.to_lowercase());
    models.dedup();
    models
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
    fn models_are_sorted_unique_and_keep_the_selection() {
        let models = sorted_unique_models(vec!["b".into(), "A".into(), "b".into()], Some("custom"));
        assert_eq!(models, vec!["A", "b", "custom"]);
    }
}
