use serde::{Deserialize, Serialize};

/// Storage identity is scoped to a host. Task identity remains on Workspace.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryCheckout {
    pub id: String,
    pub project_id: String,
    pub host_id: String,
    pub path: String,
    pub kind: CheckoutKind,
    /// The owning Git repository, which can differ for legacy SSH worktrees.
    pub repository_path: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum CheckoutKind {
    Project,
    Linked,
}

impl CheckoutKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Project => "project",
            Self::Linked => "linked",
        }
    }
}
