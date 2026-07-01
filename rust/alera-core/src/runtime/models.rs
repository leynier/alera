use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub id: String,
    pub name: String,
    pub repo_path: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub kind: ProjectKind,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProjectKind {
    GitRepository,
    Folder,
}

impl ProjectKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ProjectKind::GitRepository => "gitRepository",
            ProjectKind::Folder => "folder",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "folder" => ProjectKind::Folder,
            _ => ProjectKind::GitRepository,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Workspace {
    pub id: String,
    pub instance_id: String,
    pub host_id: String,
    pub project_id: String,
    pub name: String,
    pub branch: Option<String>,
    pub path: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub kind: WorkspaceKind,
    pub status: WorkspaceStatus,
    pub source_branch: Option<String>,
    pub reuses_existing_branch: bool,
    #[serde(default)]
    pub tag_ids: Vec<String>,
    #[serde(default)]
    pub tag_names: Vec<String>,
    pub parent_workspace_id: Option<String>,
    #[serde(default)]
    pub child_count: i64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceKind {
    Main,
    Linked,
}

impl WorkspaceKind {
    pub fn as_str(self) -> &'static str {
        match self {
            WorkspaceKind::Main => "main",
            WorkspaceKind::Linked => "linked",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "linked" => WorkspaceKind::Linked,
            _ => WorkspaceKind::Main,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceStatus {
    Active,
    Removed,
}

impl WorkspaceStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            WorkspaceStatus::Active => "active",
            WorkspaceStatus::Removed => "removed",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "removed" => WorkspaceStatus::Removed,
            _ => WorkspaceStatus::Active,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceTabRecord {
    pub id: String,
    pub workspace_id: String,
    pub kind: String,
    pub title: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(default)]
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct WorkbenchLayoutRecord {
    pub workspace_id: String,
    #[serde(default)]
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceTag {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRelation {
    pub id: String,
    pub parent_workspace_id: String,
    pub parent_instance_id: String,
    pub child_workspace_id: String,
    pub child_instance_id: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SshTarget {
    pub id: String,
    pub alias: String,
    pub host: String,
    pub port: i64,
    pub username: String,
    pub platform: Option<String>,
    pub arch: Option<String>,
    pub auth_kind: SshAuthKind,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_status: Option<String>,
    #[serde(default)]
    pub install_dir: Option<String>,
    #[serde(default)]
    pub runtime_version: Option<String>,
    #[serde(default)]
    pub runtime_platform: Option<String>,
    #[serde(default)]
    pub runtime_arch: Option<String>,
    #[serde(default)]
    pub bootstrap_status: SshBootstrapStatus,
    #[serde(default)]
    pub last_bootstrap_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub last_checked_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum SshAuthKind {
    Password,
    Key,
    Agent,
}

impl SshAuthKind {
    pub fn as_str(self) -> &'static str {
        match self {
            SshAuthKind::Password => "password",
            SshAuthKind::Key => "key",
            SshAuthKind::Agent => "agent",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "key" => SshAuthKind::Key,
            "agent" => SshAuthKind::Agent,
            _ => SshAuthKind::Password,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SshBootstrapStatus {
    #[default]
    NotInstalled,
    Planned,
    Installing,
    Installed,
    Failed,
    Cancelled,
}

impl SshBootstrapStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            SshBootstrapStatus::NotInstalled => "notInstalled",
            SshBootstrapStatus::Planned => "planned",
            SshBootstrapStatus::Installing => "installing",
            SshBootstrapStatus::Installed => "installed",
            SshBootstrapStatus::Failed => "failed",
            SshBootstrapStatus::Cancelled => "cancelled",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "planned" => SshBootstrapStatus::Planned,
            "installing" => SshBootstrapStatus::Installing,
            "installed" => SshBootstrapStatus::Installed,
            "failed" => SshBootstrapStatus::Failed,
            "cancelled" => SshBootstrapStatus::Cancelled,
            _ => SshBootstrapStatus::NotInstalled,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CascadePreview {
    pub workspace_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSettings {
    #[serde(default)]
    pub workspace_directory: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectConfigRecord {
    pub project_id: String,
    pub config: ProjectConfig,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProjectConfig {
    #[serde(default)]
    pub worktree: WorktreeSetupConfig,
}

impl ProjectConfig {
    pub fn is_empty(&self) -> bool {
        self.worktree.copy.is_empty() && self.worktree.setup.is_empty()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeSetupConfig {
    #[serde(default)]
    pub copy: Vec<WorktreeCopyRule>,
    #[serde(default)]
    pub setup: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeCopyRule {
    pub from: String,
    #[serde(default)]
    pub to: Option<String>,
    #[serde(default)]
    pub overwrite: bool,
}

impl WorktreeCopyRule {
    pub fn destination(&self) -> &str {
        self.to.as_deref().unwrap_or(&self.from)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeSetupReport {
    #[serde(default)]
    pub steps: Vec<WorktreeSetupStepReport>,
}

impl WorktreeSetupReport {
    pub fn empty() -> Self {
        Self { steps: Vec::new() }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeSetupStepReport {
    pub kind: WorktreeSetupStepKind,
    pub label: String,
    pub succeeded: bool,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub exit_code: Option<i64>,
    #[serde(default)]
    pub stdout_tail: Option<String>,
    #[serde(default)]
    pub stderr_tail: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WorktreeSetupStepKind {
    Copy,
    Command,
    Config,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceCreationResult {
    pub workspace: Workspace,
    pub setup_report: WorktreeSetupReport,
}

pub type ProjectConfigMap = BTreeMap<String, ProjectConfig>;
