use serde::{Deserialize, Serialize};

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
