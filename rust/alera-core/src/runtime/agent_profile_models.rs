use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

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
    /// worker contract of accept/heartbeat/complete.
    pub command: String,
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
