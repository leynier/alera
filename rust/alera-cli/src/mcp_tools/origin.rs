//! Who made an MCP call, handed to the CLI process that runs the tool.
//!
//! A remote call names the OAuth client and grant the cloud signed; a local
//! call names the client from its `initialize` request. Commands that record
//! an origin, such as `inbox ask`, read it from [`ORIGIN_VARIABLE`].

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Environment variable that carries the JSON-encoded [`CallOrigin`].
pub(crate) const ORIGIN_VARIABLE: &str = "ALERA_MCP_ORIGIN";
const MAX_FIELD_CHARS: usize = 256;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CallOrigin {
    /// `remote` (through the Alera cloud) or `local` (`alera mcp serve`).
    pub(crate) transport: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) client_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) client_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) grant_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) call_id: Option<String>,
}

impl CallOrigin {
    pub(crate) fn remote(
        client_id: &str,
        client_name: &str,
        grant_id: &str,
        call_id: &str,
    ) -> Self {
        Self {
            transport: "remote".to_owned(),
            client_id: bounded(client_id),
            client_name: bounded(client_name),
            grant_id: bounded(grant_id),
            call_id: bounded(call_id),
        }
    }

    /// The local client as its `initialize` request named itself.
    pub(crate) fn local(client_info: &Value) -> Self {
        let name = client_info["title"]
            .as_str()
            .or_else(|| client_info["name"].as_str())
            .unwrap_or_default();
        Self {
            transport: "local".to_owned(),
            client_id: client_info["name"].as_str().and_then(bounded),
            client_name: bounded(name),
            grant_id: None,
            call_id: None,
        }
    }

    pub(crate) fn with_call_id(mut self, call_id: &str) -> Self {
        self.call_id = bounded(call_id);
        self
    }

    pub(crate) fn to_env_value(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }

    /// The origin of the current process, when an MCP tool started it.
    pub(crate) fn from_env() -> Option<Self> {
        let text = std::env::var(ORIGIN_VARIABLE).ok()?;
        serde_json::from_str::<Self>(&text)
            .ok()
            .filter(|origin| matches!(origin.transport.as_str(), "remote" | "local"))
    }
}

/// Keeps a self-asserted value short enough to show and store.
fn bounded(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed.chars().take(MAX_FIELD_CHARS).collect())
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::CallOrigin;

    #[test]
    fn local_origin_prefers_the_client_title() {
        let origin = CallOrigin::local(&json!({ "name": "codex-mcp", "title": "Codex" }));
        assert_eq!(origin.transport, "local");
        assert_eq!(origin.client_name.as_deref(), Some("Codex"));
        assert_eq!(origin.client_id.as_deref(), Some("codex-mcp"));
        let unnamed = CallOrigin::local(&json!({}));
        assert!(unnamed.client_name.is_none());
    }

    #[test]
    fn remote_origin_round_trips_through_the_environment_value() {
        let origin = CallOrigin::remote("https://chatgpt.com/client", "ChatGPT", "g-1", "c-1");
        let text = origin.to_env_value();
        let parsed: CallOrigin = serde_json::from_str(&text).unwrap();
        assert_eq!(parsed, origin);
        assert!(!text.contains("null"));
    }

    #[test]
    fn long_and_blank_values_are_bounded() {
        let origin = CallOrigin::remote(&"x".repeat(5000), "  ", "g", "c");
        assert_eq!(origin.client_id.unwrap().chars().count(), 256);
        assert!(origin.client_name.is_none());
    }
}
