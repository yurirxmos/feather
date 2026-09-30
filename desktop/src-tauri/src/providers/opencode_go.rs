use reqwest::Client;
use serde_json::{json, Value};

const ENDPOINT: &str = "https://opencode.ai/zen/go/v1/chat/completions";
const DEFAULT_MODEL: &str = "deepseek-v4.1-flash";
const SYSTEM_PROMPT: &str = "You are a typing assistant. Write only the text the user wants to type. Do not add explanations, headings, or quotation marks unless requested.";

pub async fn generate(api_key: &str, instruction: &str) -> Result<String, String> {
    let instruction = instruction.trim();
    if instruction.is_empty() {
        return Err("Enter an instruction before generating.".to_owned());
    }

    let response = Client::new()
        .post(ENDPOINT)
        .bearer_auth(api_key)
        .json(&request_body(instruction))
        .send()
        .await
        .map_err(|_| "Feather could not reach OpenCode Go. Check your connection and try again.".to_owned())?;

    if !response.status().is_success() {
        return Err(match response.status().as_u16() {
            401 | 403 => "OpenCode Go rejected the API key.".to_owned(),
            429 => "OpenCode Go is rate-limiting this request. Try again shortly.".to_owned(),
            status => format!("OpenCode Go returned an error ({status})."),
        });
    }

    let payload: Value = response
        .json()
        .await
        .map_err(|_| "OpenCode Go returned an unreadable response.".to_owned())?;
    payload
        .pointer("/choices/0/message/content")
        .and_then(Value::as_str)
        .map(|text| text.trim().to_owned())
        .filter(|text| !text.is_empty())
        .ok_or_else(|| "OpenCode Go returned an empty response.".to_owned())
}

fn request_body(instruction: &str) -> Value {
    json!({
        "model": DEFAULT_MODEL,
        "stream": false,
        "messages": [
            { "role": "system", "content": SYSTEM_PROMPT },
            { "role": "user", "content": instruction }
        ]
    })
}

#[cfg(test)]
mod tests {
    use super::request_body;

    #[test]
    fn request_uses_the_typing_assistant_prompt() {
        let request = request_body("Reply briefly");

        assert_eq!(request["stream"], false);
        assert_eq!(request["messages"][1]["content"], "Reply briefly");
        assert!(request["messages"][0]["content"]
            .as_str()
            .is_some_and(|prompt| prompt.contains("typing assistant")));
    }
}
