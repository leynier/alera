use crate::{
    error::nonempty, ApprovalPolicy, InteractionMode, ProviderError, RuntimeMode, SandboxMode,
};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::path::PathBuf;

pub const MAX_TURN_INPUT_CHARS: usize = 120_000;
pub const MAX_TURN_ATTACHMENTS: usize = 100;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionStartInput {
    pub thread_id: String,
    pub resume_thread_id: Option<String>,
    pub cwd: Option<PathBuf>,
    pub model: Option<String>,
    #[serde(default)]
    pub runtime_mode: RuntimeMode,
    pub approval_policy: Option<ApprovalPolicy>,
    pub sandbox_mode: Option<SandboxMode>,
    #[serde(default)]
    pub options: Map<String, Value>,
}

impl SessionStartInput {
    pub fn new(thread_id: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            ..Self::default()
        }
    }
    pub fn validate(&self) -> Result<(), ProviderError> {
        nonempty(&self.thread_id, "threadId")?;
        if let Some(id) = &self.resume_thread_id {
            nonempty(id, "resumeThreadId")?;
        }
        if let Some(model) = &self.model {
            nonempty(model, "model")?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Attachment {
    Image { url: String },
    LocalImage { path: PathBuf },
    File { path: PathBuf },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TurnInput {
    pub thread_id: String,
    pub input: String,
    #[serde(default)]
    pub attachments: Vec<Attachment>,
    pub model: Option<String>,
    #[serde(default)]
    pub interaction_mode: InteractionMode,
    #[serde(default)]
    pub options: Map<String, Value>,
}

impl TurnInput {
    pub fn text(thread_id: impl Into<String>, input: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            input: input.into(),
            ..Self::default()
        }
    }
    pub fn validate(&self) -> Result<(), ProviderError> {
        nonempty(&self.thread_id, "threadId")?;
        if self.input.trim().is_empty() && self.attachments.is_empty() {
            return Err(ProviderError::Validation(
                "a turn requires text or attachments".into(),
            ));
        }
        if self.input.encode_utf16().count() > MAX_TURN_INPUT_CHARS {
            return Err(ProviderError::Validation(
                "turn input exceeds 120000 characters".into(),
            ));
        }
        if self.attachments.len() > MAX_TURN_ATTACHMENTS {
            return Err(ProviderError::Validation(
                "a turn supports at most 100 attachments".into(),
            ));
        }
        if let Some(model) = &self.model {
            nonempty(model, "model")?;
        }
        for attachment in &self.attachments {
            match attachment {
                Attachment::Image { url } => nonempty(url, "image url")?,
                Attachment::LocalImage { path } | Attachment::File { path } => {
                    if path.as_os_str().is_empty() {
                        return Err(ProviderError::Validation(
                            "attachment path must not be empty".into(),
                        ));
                    }
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TurnStartResult {
    pub thread_id: String,
    pub turn_id: String,
    pub native_turn_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InterruptInput {
    pub thread_id: String,
    pub turn_id: Option<String>,
}
