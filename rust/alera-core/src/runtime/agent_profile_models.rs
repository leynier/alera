use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentProfileLaunchMode {
    Managed,
    #[default]
    Command,
}

impl AgentProfileLaunchMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Managed => "managed",
            Self::Command => "command",
        }
    }
}

impl std::str::FromStr for AgentProfileLaunchMode {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "managed" => Ok(Self::Managed),
            "command" => Ok(Self::Command),
            other => Err(format!("unsupported agent profile launch mode: {other}")),
        }
    }
}

/// A user-declared launch configuration for an orchestration worker agent.
///
/// Profiles are user configuration, not run state: they live in the runtime
/// schema next to the other declared catalogs so resetting orchestration state
/// never destroys them.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfile {
    pub id: String,
    pub name: String,
    /// Which built-in adapter drives readiness detection, preamble injection
    /// and submission. Validated against the adapter registry by the host,
    /// which owns that table.
    pub agent_type: String,
    /// The interactive launch command. A one-shot mode cannot satisfy the
    /// worker contract of accept/heartbeat/complete. Managed profiles retain a
    /// generated preview here for older clients; the host launches from
    /// `managed_config`, never by reparsing the preview.
    pub command: String,
    #[serde(default)]
    pub launch_mode: AgentProfileLaunchMode,
    #[serde(default)]
    pub managed_config: Option<Value>,
    /// Instructions appended after a dispatched prompt and before project
    /// instructions.
    #[serde(default)]
    pub custom_prompt: String,
    #[serde(default)]
    pub description: String,
    /// Profiles sharing a group drain the same usage bucket. Alera never
    /// measures or verifies this; it is an assertion the user makes so that
    /// fallback selection can prefer a candidate from a different bucket.
    #[serde(default)]
    pub quota_group: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
