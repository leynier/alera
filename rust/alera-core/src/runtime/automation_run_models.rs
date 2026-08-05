use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationOverlapPolicy,
    AutomationRunStatus, AutomationRunTrigger,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationTargetIdentity {
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub tab_id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub profile_id: Option<String>,
    #[serde(default)]
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub terminal_handle: Option<String>,
}

impl AutomationTargetIdentity {
    pub fn is_empty(&self) -> bool {
        self.workspace_id.is_none()
            && self.tab_id.is_none()
            && self.session_id.is_none()
            && self.profile_id.is_none()
            && self.conversation_id.is_none()
            && self.terminal_handle.is_none()
    }

    pub fn matches(&self, other: &Self) -> bool {
        self.workspace_id == other.workspace_id
            && self.tab_id == other.tab_id
            && self.session_id == other.session_id
            && self.profile_id == other.profile_id
            && self.conversation_id == other.conversation_id
            && self.terminal_handle == other.terminal_handle
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationRun {
    pub id: String,
    pub automation_id: String,
    pub number: i64,
    pub occurrence_key: String,
    pub scheduled_at: DateTime<Utc>,
    pub trigger: AutomationRunTrigger,
    #[serde(default)]
    pub actor_kind: Option<AutomationActorKind>,
    #[serde(default)]
    pub actor_id: Option<String>,
    #[serde(default)]
    pub target_identity: Option<AutomationTargetIdentity>,
    /// Manual Run Now keeps its explicit overlap choice with the queued run so
    /// a later scheduler tick cannot silently replace it with the definition
    /// default.
    #[serde(default)]
    pub overlap_policy: Option<AutomationOverlapPolicy>,
    #[serde(default)]
    pub precheck: Option<bool>,
    pub status: AutomationRunStatus,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub rendered_prompt: Option<String>,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub tab_id: Option<String>,
    #[serde(default)]
    pub setup_tab_id: Option<String>,
    #[serde(default)]
    pub workspace_branch: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub owned_workspace: bool,
    #[serde(default)]
    pub owned_tab: bool,
    #[serde(default)]
    pub taken_over: bool,
    pub attempt_count: i64,
    #[serde(default)]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub last_heartbeat_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub absolute_deadline_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub waiting_extension_until: Option<DateTime<Utc>>,
    #[serde(default)]
    pub cancel_requested_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub retry_after: Option<DateTime<Utc>>,
    #[serde(default)]
    pub finished_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationAttempt {
    pub id: String,
    pub run_id: String,
    pub number: i64,
    pub status: AutomationRunStatus,
    #[serde(default)]
    pub error: Option<String>,
    pub started_at: DateTime<Utc>,
    #[serde(default)]
    pub finished_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationOccurrence {
    pub automation_id: String,
    pub key: String,
    pub scheduled_at: DateTime<Utc>,
    pub local_time: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationAuditEvent {
    pub id: String,
    pub automation_id: Option<String>,
    pub run_id: Option<String>,
    pub action: String,
    pub actor: AutomationActor,
    pub revision: Option<i64>,
    #[serde(default)]
    pub details: Value,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationTag {
    pub id: String,
    pub name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationTemplate {
    pub id: String,
    pub name: String,
    pub prompt_template: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub tag_ids: Vec<String>,
    pub created_by: AutomationActor,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationAgentPolicy {
    pub profile_id: String,
    #[serde(default)]
    pub may_activate_or_edit_active: bool,
    #[serde(default)]
    pub may_execute: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationProjectPolicy {
    pub project_id: String,
    #[serde(default)]
    pub repo_declared: bool,
    #[serde(default)]
    pub local_approved: bool,
    #[serde(default)]
    pub restrictive: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationImportBundle {
    pub schema_version: String,
    pub definitions: Vec<AutomationDefinition>,
    #[serde(default)]
    pub templates: Vec<AutomationTemplate>,
    #[serde(default)]
    pub tags: Vec<AutomationTag>,
}

/// A portable catalog deliberately stores definitions as JSON values. Target
/// workspaces, tabs, profiles, and conversations belong to one runtime and
/// must never leak into an export that can be shared with another runtime.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationExportBundle {
    pub schema_version: String,
    pub definitions: Vec<Value>,
    #[serde(default)]
    pub templates: Vec<Value>,
    #[serde(default)]
    pub tags: Vec<Value>,
}
