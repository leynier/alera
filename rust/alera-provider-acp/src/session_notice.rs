//! ACP `notice` session updates: messages the agent shows the person outside
//! the conversation, such as a model fallback. Bounds follow T3 Code's
//! `runtimeModel.ts`.

use serde_json::{json, Value};

const TITLE_LIMIT: usize = 1024;
const DESCRIPTION_LIMIT: usize = 4096;
const SEVERITY_LIMIT: usize = 64;

/// The `runtime.warning` payload of a notice, or `None` when it has no title.
/// `message` joins the title and description for the chat's notice row.
pub(crate) fn notice_payload(update: &Value) -> Option<Value> {
    let title = bounded(update.get("title"), TITLE_LIMIT)?;
    let description = bounded(update.get("description"), DESCRIPTION_LIMIT);
    let severity = bounded(update.get("severity"), SEVERITY_LIMIT).unwrap_or_else(|| "info".into());
    let message = match &description {
        Some(description) => format!("{title}\n\n{description}"),
        None => title.clone(),
    };
    let mut payload = json!({
        "message": message,
        "title": title,
        "severity": severity,
        "source": "acp.notice",
    });
    if let Some(description) = description {
        payload["description"] = Value::String(description);
    }
    Some(payload)
}

/// The trimmed text cut to `limit` characters, or `None` when it is blank.
fn bounded(value: Option<&Value>, limit: usize) -> Option<String> {
    let text = value?.as_str()?.trim();
    if text.is_empty() {
        return None;
    }
    Some(
        text.chars()
            .take(limit)
            .collect::<String>()
            .trim_end()
            .to_owned(),
    )
}

#[cfg(test)]
mod tests {
    use super::notice_payload;
    use serde_json::json;

    #[test]
    fn notices_are_trimmed_and_cut_on_char_boundaries() {
        let title = format!("  {}  ", "é".repeat(1100));
        let payload = notice_payload(&json!({
            "title": title,
            "description": "ü".repeat(5000),
            "severity": "w".repeat(80),
        }))
        .unwrap();
        assert_eq!(payload["title"].as_str().unwrap().chars().count(), 1024);
        assert_eq!(
            payload["description"].as_str().unwrap().chars().count(),
            4096
        );
        assert_eq!(payload["severity"].as_str().unwrap().len(), 64);
    }

    #[test]
    fn untitled_notices_have_no_payload_and_severity_defaults_to_info() {
        assert!(notice_payload(&json!({"title":"  ","description":"x"})).is_none());
        assert!(notice_payload(&json!({"description":"x"})).is_none());
        let payload = notice_payload(&json!({"title":"Model fallback"})).unwrap();
        assert_eq!(payload["severity"], "info");
        assert_eq!(payload["message"], "Model fallback");
        assert!(payload.get("description").is_none());
    }
}
