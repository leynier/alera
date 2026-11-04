use crate::{error::nonempty, ProviderError, ProviderSession, SessionStartInput};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "id", rename_all = "camelCase")]
pub enum NativeForkBoundary {
    /// Inclusive settled native turn, not a host transcript turn id.
    Turn(String),
    /// Inclusive native transcript-entry UUID.
    Message(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeForkInput {
    pub source_native_thread_id: String,
    pub session: SessionStartInput,
    pub boundary: Option<NativeForkBoundary>,
}

impl NativeForkInput {
    pub fn validate(&self) -> Result<(), ProviderError> {
        nonempty(&self.source_native_thread_id, "sourceNativeThreadId")?;
        self.session.validate()?;
        if self.session.resume_thread_id.is_some() {
            return Err(ProviderError::Validation(
                "fork source must use sourceNativeThreadId".into(),
            ));
        }
        if let Some(NativeForkBoundary::Turn(id) | NativeForkBoundary::Message(id)) = &self.boundary
        {
            nonempty(id, "native fork boundary")?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeForkResult {
    pub session: ProviderSession,
    pub source_native_thread_id: String,
    /// Absent until the provider reports the new native identity.
    pub native_thread_id: Option<String>,
    pub boundary: Option<NativeForkBoundary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "camelCase")]
pub enum NativeRollbackBoundary {
    /// Legacy Codex thread/rollback: remove this many native turns.
    RemoveTurns(u32),
    /// Paginated Codex thread/revert: remove this native turn and everything after it.
    BeforeTurn(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRollbackInput {
    pub thread_id: String,
    pub boundary: NativeRollbackBoundary,
}

impl NativeRollbackInput {
    pub fn validate(&self) -> Result<(), ProviderError> {
        nonempty(&self.thread_id, "threadId")?;
        match &self.boundary {
            NativeRollbackBoundary::RemoveTurns(0) => Err(ProviderError::Validation(
                "rollback requires at least one native turn".into(),
            )),
            NativeRollbackBoundary::BeforeTurn(id) => nonempty(id, "beforeTurnId"),
            _ => Ok(()),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRollbackResult {
    pub thread_id: String,
    pub native_thread_id: String,
    pub boundary: NativeRollbackBoundary,
    /// Provider history only; a conversation rollback does not restore files.
    pub native_response: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRewindFilesInput {
    pub thread_id: String,
    pub native_user_message_id: String,
}

impl NativeRewindFilesInput {
    pub fn validate(&self) -> Result<(), ProviderError> {
        nonempty(&self.thread_id, "threadId")?;
        nonempty(&self.native_user_message_id, "nativeUserMessageId")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeRewindFilesResult {
    pub thread_id: String,
    pub native_thread_id: String,
    pub native_user_message_id: String,
    /// None means an acknowledgement without proof of a native rewind outcome.
    pub can_rewind: Option<bool>,
    pub error: Option<String>,
    pub files_changed: Option<Vec<String>>,
    pub insertions: Option<u64>,
    pub deletions: Option<u64>,
    pub skipped_links: Option<u64>,
    pub native_response: Value,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeHistoryCapabilities {
    /// Supports enabling checkpointing at launch, distinct from an enabled session's rewind.
    #[serde(default)]
    pub file_checkpointing: bool,
    pub fork_at_turn: bool,
    pub fork_at_message: bool,
    pub rollback_remove_turns: bool,
    pub rollback_before_turn: bool,
    pub rewind_files: bool,
}
