use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const AUTOMATION_SCHEMA_VERSION: &str = "1";
pub const AUTOMATION_DEFAULT_NAME_TEMPLATE: &str = "auto-{{automation.slug}}-{{run.number}}";
pub const AUTOMATION_DEFAULT_QUEUE_CAP: i64 = 10;
pub const AUTOMATION_DEFAULT_INACTIVITY_TIMEOUT_SECONDS: i64 = 2 * 60 * 60;
pub const AUTOMATION_DEFAULT_HEARTBEAT_INTERVAL_SECONDS: i64 = 60;
pub const AUTOMATION_DEFAULT_MISFIRE_GRACE_SECONDS: i64 = 15 * 60;
pub const AUTOMATION_DEFAULT_RETRY_MAX_ATTEMPTS: i64 = 3;
pub const AUTOMATION_DEFAULT_RETRY_BACKOFF_SECONDS: i64 = 60;
pub const AUTOMATION_DEFAULT_CIRCUIT_FAILURE_THRESHOLD: i64 = 3;
pub const AUTOMATION_DEFAULT_CIRCUIT_OPEN_SECONDS: i64 = 15 * 60;
pub const AUTOMATION_MAX_INACTIVITY_TIMEOUT_SECONDS: i64 = 24 * 60 * 60;
pub const AUTOMATION_MAX_PROMPT_BYTES: usize = 128 * 1024;
pub const AUTOMATION_MAX_RENDERED_PROMPT_BYTES: usize = 128 * 1024;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationState {
    Draft,
    Active,
    Paused,
    Blocked,
    Archived,
    Trashed,
}

impl AutomationState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Active => "active",
            Self::Paused => "paused",
            Self::Blocked => "blocked",
            Self::Archived => "archived",
            Self::Trashed => "trashed",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "active" => Self::Active,
            "paused" => Self::Paused,
            "blocked" => Self::Blocked,
            "archived" => Self::Archived,
            "trashed" => Self::Trashed,
            _ => Self::Draft,
        }
    }

    pub fn is_editable(self) -> bool {
        !matches!(self, Self::Archived | Self::Trashed)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationScheduleKind {
    OneTime,
    Recurring,
}

impl AutomationScheduleKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::OneTime => "oneTime",
            Self::Recurring => "recurring",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationSchedule {
    OneTime {
        at: DateTime<Utc>,
        timezone: String,
    },
    Recurring {
        cron: String,
        timezone: String,
        #[serde(default)]
        start_at: Option<DateTime<Utc>>,
        #[serde(default)]
        end_at: Option<DateTime<Utc>>,
        #[serde(default)]
        max_scheduled_runs: Option<i64>,
    },
}

impl AutomationSchedule {
    pub fn kind(&self) -> AutomationScheduleKind {
        match self {
            Self::OneTime { .. } => AutomationScheduleKind::OneTime,
            Self::Recurring { .. } => AutomationScheduleKind::Recurring,
        }
    }

    pub fn timezone(&self) -> &str {
        match self {
            Self::OneTime { timezone, .. } | Self::Recurring { timezone, .. } => timezone,
        }
    }

    pub fn max_scheduled_runs(&self) -> Option<i64> {
        match self {
            Self::OneTime { .. } => Some(1),
            Self::Recurring {
                max_scheduled_runs, ..
            } => *max_scheduled_runs,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationTarget {
    ExistingTab {
        workspace_id: String,
        tab_id: String,
        #[serde(default)]
        conversation_id: Option<String>,
    },
    FreshTab {
        workspace_id: String,
        agent_profile_id: String,
    },
    ManagedWorkspace {
        source_workspace_id: String,
        source_branch: String,
        #[serde(default = "default_name_template")]
        name_template: String,
        agent_profile_id: String,
    },
}

impl AutomationTarget {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::ExistingTab { .. } => "existingTab",
            Self::FreshTab { .. } => "freshTab",
            Self::ManagedWorkspace { .. } => "managedWorkspace",
        }
    }

    pub fn workspace_id(&self) -> Option<&str> {
        match self {
            Self::ExistingTab { workspace_id, .. } | Self::FreshTab { workspace_id, .. } => {
                Some(workspace_id)
            }
            Self::ManagedWorkspace { .. } => None,
        }
    }

    pub fn agent_profile_id(&self) -> Option<&str> {
        match self {
            Self::ExistingTab { .. } => None,
            Self::FreshTab {
                agent_profile_id, ..
            }
            | Self::ManagedWorkspace {
                agent_profile_id, ..
            } => Some(agent_profile_id),
        }
    }
}

fn default_name_template() -> String {
    AUTOMATION_DEFAULT_NAME_TEMPLATE.to_string()
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationSetupPolicy {
    Wait,
    Parallel,
    Skip,
}

impl AutomationSetupPolicy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Wait => "wait",
            Self::Parallel => "parallel",
            Self::Skip => "skip",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationCleanupPolicy {
    Preserve,
    OnSuccess,
}

impl AutomationCleanupPolicy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Preserve => "preserve",
            Self::OnSuccess => "onSuccess",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationOverlapPolicy {
    Skip,
    RunLatestOnce,
    Queue,
    ForceParallel,
}

impl AutomationOverlapPolicy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Skip => "skip",
            Self::RunLatestOnce => "runLatestOnce",
            Self::Queue => "queue",
            Self::ForceParallel => "forceParallel",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationMisfirePolicy {
    Skip,
    RunLatestOnce,
    Queue,
}

impl AutomationMisfirePolicy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Skip => "skip",
            Self::RunLatestOnce => "runLatestOnce",
            Self::Queue => "queue",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationRunTrigger {
    Scheduled,
    Manual,
}

impl AutomationRunTrigger {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Scheduled => "scheduled",
            Self::Manual => "manual",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationRunStatus {
    Pending,
    PrecheckSkipped,
    MisfireSkipped,
    OverlapSkipped,
    QueueLimitSkipped,
    Dispatching,
    Dispatched,
    WaitingForUser,
    Success,
    Failure,
    Blocked,
    Timeout,
    Cancelled,
}

impl AutomationRunStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::PrecheckSkipped => "precheckSkipped",
            Self::MisfireSkipped => "misfireSkipped",
            Self::OverlapSkipped => "overlapSkipped",
            Self::QueueLimitSkipped => "queueLimitSkipped",
            Self::Dispatching => "dispatching",
            Self::Dispatched => "dispatched",
            Self::WaitingForUser => "waitingForUser",
            Self::Success => "success",
            Self::Failure => "failure",
            Self::Blocked => "blocked",
            Self::Timeout => "timeout",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "precheckSkipped" => Self::PrecheckSkipped,
            "misfireSkipped" => Self::MisfireSkipped,
            "overlapSkipped" => Self::OverlapSkipped,
            "queueLimitSkipped" => Self::QueueLimitSkipped,
            "dispatching" => Self::Dispatching,
            "dispatched" => Self::Dispatched,
            "waitingForUser" => Self::WaitingForUser,
            "success" => Self::Success,
            "failure" => Self::Failure,
            "blocked" => Self::Blocked,
            "timeout" => Self::Timeout,
            "cancelled" => Self::Cancelled,
            _ => Self::Pending,
        }
    }

    pub fn is_final(self) -> bool {
        matches!(
            self,
            Self::PrecheckSkipped
                | Self::MisfireSkipped
                | Self::OverlapSkipped
                | Self::QueueLimitSkipped
                | Self::Success
                | Self::Failure
                | Self::Blocked
                | Self::Timeout
                | Self::Cancelled
        )
    }

    pub fn counts_as_failure(self) -> bool {
        matches!(self, Self::Failure | Self::Timeout)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationActorKind {
    HumanDesktop,
    AuthenticatedMobile,
    LocalCli,
    ManagedAgent,
}

impl AutomationActorKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::HumanDesktop => "humanDesktop",
            Self::AuthenticatedMobile => "authenticatedMobile",
            Self::LocalCli => "localCli",
            Self::ManagedAgent => "managedAgent",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationActor {
    pub kind: AutomationActorKind,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationPrecheck {
    pub command: String,
    pub timeout_seconds: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationDefinition {
    pub id: String,
    pub slug: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub tag_ids: Vec<String>,
    pub prompt_template: String,
    pub schedule: AutomationSchedule,
    pub target: AutomationTarget,
    #[serde(default = "default_setup_policy")]
    pub setup_policy: AutomationSetupPolicy,
    #[serde(default)]
    pub cleanup_policy: Option<AutomationCleanupPolicy>,
    #[serde(default = "default_overlap_policy")]
    pub overlap_policy: AutomationOverlapPolicy,
    #[serde(default = "default_queue_cap")]
    pub queue_cap: i64,
    #[serde(default = "default_inactivity_timeout")]
    pub inactivity_timeout_seconds: i64,
    #[serde(default = "default_heartbeat_interval")]
    pub heartbeat_interval_seconds: i64,
    #[serde(default = "default_misfire_grace")]
    pub misfire_grace_seconds: i64,
    #[serde(default = "default_misfire_policy")]
    pub misfire_policy: AutomationMisfirePolicy,
    #[serde(default = "default_retry_max_attempts")]
    pub retry_max_attempts: i64,
    #[serde(default = "default_retry_backoff_seconds")]
    pub retry_backoff_seconds: i64,
    #[serde(default = "default_circuit_failure_threshold")]
    pub circuit_failure_threshold: i64,
    #[serde(default = "default_circuit_open_seconds")]
    pub circuit_open_seconds: i64,
    #[serde(default)]
    pub precheck: Option<AutomationPrecheck>,
    #[serde(default)]
    pub notify_on_success: bool,
    #[serde(default)]
    pub circuit_opened: bool,
    pub state: AutomationState,
    pub revision: i64,
    #[serde(default)]
    pub approved_revision: Option<i64>,
    pub created_by: AutomationActor,
    pub modified_by: AutomationActor,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

fn default_setup_policy() -> AutomationSetupPolicy {
    AutomationSetupPolicy::Wait
}

fn default_overlap_policy() -> AutomationOverlapPolicy {
    AutomationOverlapPolicy::Skip
}

fn default_queue_cap() -> i64 {
    AUTOMATION_DEFAULT_QUEUE_CAP
}

fn default_inactivity_timeout() -> i64 {
    AUTOMATION_DEFAULT_INACTIVITY_TIMEOUT_SECONDS
}

fn default_heartbeat_interval() -> i64 {
    AUTOMATION_DEFAULT_HEARTBEAT_INTERVAL_SECONDS
}

fn default_misfire_grace() -> i64 {
    AUTOMATION_DEFAULT_MISFIRE_GRACE_SECONDS
}

fn default_misfire_policy() -> AutomationMisfirePolicy {
    AutomationMisfirePolicy::Skip
}

fn default_retry_max_attempts() -> i64 {
    AUTOMATION_DEFAULT_RETRY_MAX_ATTEMPTS
}

fn default_retry_backoff_seconds() -> i64 {
    AUTOMATION_DEFAULT_RETRY_BACKOFF_SECONDS
}

fn default_circuit_failure_threshold() -> i64 {
    AUTOMATION_DEFAULT_CIRCUIT_FAILURE_THRESHOLD
}

fn default_circuit_open_seconds() -> i64 {
    AUTOMATION_DEFAULT_CIRCUIT_OPEN_SECONDS
}

#[path = "automation_model_impl.rs"]
mod automation_model_impl;
#[path = "automation_run_models.rs"]
mod automation_run_models;
pub use automation_run_models::*;
