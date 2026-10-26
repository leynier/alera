use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProviderKind {
    Codex,
    Claude,
    Other(String),
}

impl ProviderKind {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Codex => "codex",
            Self::Claude => "claudeAgent",
            Self::Other(name) => name,
        }
    }
}

impl Serialize for ProviderKind {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for ProviderKind {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let name = String::deserialize(deserializer)?;
        Ok(match name.as_str() {
            "codex" => Self::Codex,
            "claudeAgent" => Self::Claude,
            _ => Self::Other(name),
        })
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RuntimeMode {
    #[default]
    ApprovalRequired,
    AutoAcceptEdits,
    Auto,
    FullAccess,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ApprovalPolicy {
    Untrusted,
    OnFailure,
    OnRequest,
    Never,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InteractionMode {
    #[default]
    Default,
    Plan,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    Starting,
    Ready,
    Running,
    Waiting,
    Stopped,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSession {
    pub provider: ProviderKind,
    pub provider_instance_id: String,
    /// Caller-owned identity, independent of the provider's persistent thread.
    pub thread_id: String,
    pub native_thread_id: String,
    pub status: SessionStatus,
    pub model: Option<String>,
    pub cwd: Option<PathBuf>,
    pub active_turn_id: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderCapabilities {
    #[serde(
        default,
        skip_serializing_if = "crate::McpInjectionCapabilities::is_empty"
    )]
    pub mcp_injection: crate::McpInjectionCapabilities,
    pub resume: bool,
    pub interrupt: bool,
    pub approvals: bool,
    pub user_input: bool,
    pub mcp_elicitation: bool,
    pub streaming: bool,
    pub native_turn_ids: bool,
    pub multiple_threads: bool,
    pub model_switch: bool,
    pub steer: bool,
    pub snapshot: bool,
    pub rollback: bool,
    pub fork: bool,
}
