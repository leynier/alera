use serde::{Deserialize, Serialize};

use super::IssueProvider;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum IssueState {
    Open,
    Closed,
    Unknown,
}

impl IssueState {
    pub fn wire_name(self) -> &'static str {
        match self {
            IssueState::Open => "open",
            IssueState::Closed => "closed",
            IssueState::Unknown => "unknown",
        }
    }
}

/// The provider-neutral issue payload returned by `issue.fetch` and printed by
/// `alera issue show --json`. `state_label` keeps the forge's own wording
/// (Azure DevOps states such as `Active` or `Resolved` are process-defined).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueDetails {
    pub provider: IssueProvider,
    pub url: String,
    #[serde(default)]
    pub repository: Option<String>,
    pub number: i64,
    pub title: String,
    pub state: IssueState,
    #[serde(default)]
    pub state_label: Option<String>,
    #[serde(default)]
    pub body: Option<String>,
    #[serde(default)]
    pub labels: Vec<String>,
    #[serde(default)]
    pub assignees: Vec<String>,
    #[serde(default)]
    pub author: Option<String>,
    #[serde(default)]
    pub created_at: Option<String>,
    #[serde(default)]
    pub updated_at: Option<String>,
}
