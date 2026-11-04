use crate::{ClaudeClient, ClaudeSdkError, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Native SDK control response. Missing fields stay unknown for older empty acknowledgements.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewindFilesResult {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub can_rewind: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub files_changed: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub insertions: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deletions: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skipped_links: Option<u64>,
    #[serde(skip)]
    pub raw: Value,
}

impl RewindFilesResult {
    pub fn from_response(response: Value) -> Result<Self> {
        if !response.is_object() {
            return Err(ClaudeSdkError::JsonDecode(
                "rewind_files response must be an object".into(),
            ));
        }
        let mut result: Self = serde_json::from_value(response.clone())?;
        result.raw = response;
        Ok(result)
    }
}

impl ClaudeClient {
    pub async fn rewind_files(
        &self,
        user_message_id: impl Into<String>,
    ) -> Result<RewindFilesResult> {
        let user_message_id = user_message_id.into();
        if user_message_id.trim().is_empty() {
            return Err(ClaudeSdkError::InvalidState(
                "rewind_files requires a native user message UUID".into(),
            ));
        }
        let response = self
            .control_command(
                serde_json::json!({"subtype":"rewind_files","user_message_id":user_message_id}),
                self.options_initialize_timeout(),
            )
            .await?;
        RewindFilesResult::from_response(response)
    }
}
