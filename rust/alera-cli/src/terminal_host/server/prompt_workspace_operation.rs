//! The record of one New Workspace from Prompt operation, as clients read it.
//!
//! The runtime host runs the same steps as the desktop's From Prompt form:
//! choose the project, generate the identity and section, create the
//! workspace, start its setup, and launch the agent. Each step updates this
//! record, which `workspace.promptStart.get` returns and a retry reuses.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const RUNNING: &str = "running";
pub(super) const NEEDS_INPUT: &str = "needsInput";
pub(super) const COMPLETED: &str = "completed";
pub(super) const FAILED: &str = "failed";
pub(super) const CANCELLED: &str = "cancelled";
pub(super) const MAX_PROMPT_CHARS: usize = 65_536;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum StartMode {
    /// A worktree for Git projects, the project folder otherwise.
    #[default]
    Auto,
    Worktree,
    ProjectCheckout,
}

/// Which sidebar section the new workspace joins.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum SectionPolicy {
    /// AI Assist picks a section, or none ("Others") when nothing fits.
    #[default]
    Auto,
    None,
    Id(String),
    Name(String),
}

impl SectionPolicy {
    /// `"auto"`, `"none"`, `{ "id": … }` or `{ "name": … }`.
    pub(super) fn parse(value: Option<&Value>) -> HostResult<Self> {
        let invalid = || HostError::format("section must be auto, none, {id}, or {name}");
        match value {
            None | Some(Value::Null) => Ok(Self::Auto),
            Some(Value::String(text)) => match text.as_str() {
                "auto" => Ok(Self::Auto),
                "none" => Ok(Self::None),
                _ => Err(invalid()),
            },
            Some(Value::Object(object)) => {
                let field = |key: &str| {
                    object
                        .get(key)
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(str::to_owned)
                };
                match (field("id"), field("name")) {
                    (Some(id), None) => Ok(Self::Id(id)),
                    (None, Some(name)) => Ok(Self::Name(name)),
                    _ => Err(invalid()),
                }
            }
            Some(_) => Err(invalid()),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct PromptWorkspaceRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) project_id: Option<String>,
    /// Agent profile id (`prof_…`) or unique name. Omitted means the
    /// runtime's default profile, as in the app.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) profile: Option<String>,
    #[serde(default)]
    pub(super) mode: StartMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) source_branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) host_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) parent_workspace_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) issue_url: Option<String>,
    #[serde(default)]
    pub(super) section: SectionPolicy,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct PromptWorkspaceOperation {
    pub(super) id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) request_id: Option<String>,
    pub(super) status: String,
    pub(super) phase: String,
    pub(super) request: PromptWorkspaceRequest,
    /// Kept while the operation can still use it; a finished operation keeps
    /// only its hash.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) prompt: Option<String>,
    pub(super) prompt_hash: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) candidates: Vec<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) project_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) identity: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) workspace: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) section_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) agent: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) setup: Option<Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(super) warnings: Vec<String>,
    pub(super) client_mutation_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) error: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) origin: Option<Value>,
}

impl PromptWorkspaceOperation {
    pub(super) fn new(
        id: String,
        request_id: Option<String>,
        prompt: String,
        request: PromptWorkspaceRequest,
        origin: Option<Value>,
    ) -> Self {
        Self {
            client_mutation_id: format!("prompt-workspace-{id}"),
            prompt_hash: prompt_hash(&prompt),
            id,
            request_id,
            status: RUNNING.to_owned(),
            phase: "resolvingProject".to_owned(),
            request,
            prompt: Some(prompt),
            candidates: Vec::new(),
            project_id: None,
            profile_id: None,
            identity: None,
            workspace: None,
            section_id: None,
            agent: None,
            setup: None,
            warnings: Vec::new(),
            error: None,
            origin,
        }
    }

    pub(super) fn workspace_id(&self) -> Option<&str> {
        self.workspace.as_ref()?.get("id")?.as_str()
    }

    /// A launch can be retried once the workspace exists and nothing runs.
    pub(super) fn can_retry_launch(&self) -> bool {
        self.workspace_id().is_some()
            && self.agent.is_none()
            && matches!(self.status.as_str(), FAILED | CANCELLED)
    }

    pub(super) fn fail(&mut self, code: &str, message: &str, retryable: bool) {
        self.status = FAILED.to_owned();
        self.error = Some(json!({ "code": code, "message": message, "retryable": retryable }));
        self.forget_prompt_unless_retryable();
    }

    pub(super) fn finish(&mut self, status: &str) {
        self.status = status.to_owned();
        if status == COMPLETED {
            self.phase = "done".to_owned();
            self.prompt = None;
        } else {
            self.forget_prompt_unless_retryable();
        }
    }

    /// A launch retry needs the prompt again, so it stays only for that.
    fn forget_prompt_unless_retryable(&mut self) {
        if !self.can_retry_launch() && self.status != NEEDS_INPUT {
            self.prompt = None;
        }
    }

    pub(super) fn to_value(&self) -> Value {
        serde_json::to_value(self).unwrap_or_else(|_| json!({ "id": self.id }))
    }

    /// What clients see: never the prompt text, which they sent themselves.
    pub(super) fn public_value(&self) -> Value {
        let mut value = self.to_value();
        if let Some(object) = value.as_object_mut() {
            object.remove("prompt");
        }
        value
    }
}

pub(super) fn prompt_hash(prompt: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(prompt.as_bytes());
    hex::encode(hasher.finalize())
}

/// A host error as the shared `{ code, message, retryable }` shape.
pub(super) fn error_code(error: &HostError) -> (&'static str, bool) {
    let message = error.to_string().to_lowercase();
    if message.contains("ai assist") {
        ("ai_assist_unavailable", false)
    } else if message.contains("already exists") || message.contains("workspace for branch") {
        ("conflict", false)
    } else if message.contains("not found") {
        ("not_found", false)
    } else if message.contains("did not finish") || message.contains("closed the connection") {
        ("runtime_unavailable", true)
    } else {
        ("failed", false)
    }
}

#[cfg(test)]
#[path = "prompt_workspace_operation_tests.rs"]
mod tests;
