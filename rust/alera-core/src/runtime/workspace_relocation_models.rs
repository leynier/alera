use serde::{Deserialize, Serialize};

use super::Workspace;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceRelocationPhase {
    Prepared,
    Snapshotting,
    Snapshotted,
    PreparingDestination,
    DestinationReady,
    ApplyingChanges,
    ChangesApplied,
    Committed,
    RemovingSource,
    Completed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRelocation {
    pub id: String,
    pub source: Workspace,
    pub destination: Workspace,
    pub repository_path: String,
    pub original_branch: String,
    pub source_commit: String,
    pub replacement_branch: Option<String>,
    pub replacement_commit: Option<String>,
    pub destination_original_branch: Option<String>,
    pub destination_original_commit: Option<String>,
    pub move_changes: bool,
    pub recovery_stash_oid: Option<String>,
    pub phase: WorkspaceRelocationPhase,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRelocationRecovery {
    pub relocation: WorkspaceRelocation,
    pub setup: Option<super::RelocationSetupReceipt>,
    #[serde(default)]
    pub setup_root_processes: Vec<super::RelocationSetupProcess>,
    #[serde(default)]
    pub setup_descendants: Vec<super::RelocationSetupDescendant>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub setup_root_observations: Vec<SetupRootObservation>,
    #[serde(default)]
    pub setup_cancellation_requested: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupRootObservation {
    pub command_index: u32,
    pub state: SetupRootObservationState,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SetupRootObservationState {
    Live,
    Exited,
    Unknown,
}
