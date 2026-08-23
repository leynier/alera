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
    /// Stable user-defined order within the profile catalog.
    #[serde(default)]
    pub sort_order: i64,
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
    /// Monotonic concurrency token covering every persisted profile field,
    /// including its position in the catalog.
    #[serde(default)]
    pub revision: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A safe identity for a persisted tab that still depends on an agent profile.
/// Tab titles and payloads are deliberately excluded because either may contain
/// user or agent-provided text.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileTabReference {
    pub workspace_id: String,
    pub tab_id: String,
}

/// Host-owned dependency snapshot used to gate profile removal. Only stable
/// identifiers are exposed; profile commands, prompts, automation prompts and
/// tab payloads never cross this boundary.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileRemovalImpact {
    pub profile_id: String,
    pub exists: bool,
    pub revision: Option<i64>,
    pub is_default: bool,
    pub automation_ids: Vec<String>,
    pub has_automation_policy: bool,
    pub execution_policy_run_ids: Vec<String>,
    pub tabs: Vec<AgentProfileTabReference>,
}

impl AgentProfileRemovalImpact {
    pub fn reference_count(&self) -> usize {
        usize::from(self.is_default)
            + self.automation_ids.len()
            + usize::from(self.has_automation_policy)
            + self.execution_policy_run_ids.len()
            + self.tabs.len()
    }

    pub fn has_references(&self) -> bool {
        self.reference_count() > 0
    }

    pub fn has_blocking_references(&self) -> bool {
        !self.automation_ids.is_empty()
            || !self.execution_policy_run_ids.is_empty()
            || !self.tabs.is_empty()
    }
}
