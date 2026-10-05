use super::AUTOMATION_DEFAULT_NAME_TEMPLATE;
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum AutomationTarget {
    ProjectCheckout {
        #[serde(alias = "project_id")]
        project_id: String,
        #[serde(alias = "host_id")]
        host_id: String,
        #[serde(default = "default_name_template", alias = "name_template")]
        name_template: String,
        #[serde(alias = "agent_profile_id")]
        agent_profile_id: String,
    },
    ExistingTab {
        #[serde(alias = "workspace_id")]
        workspace_id: String,
        #[serde(alias = "tab_id")]
        tab_id: String,
        #[serde(default, alias = "conversation_id")]
        conversation_id: Option<String>,
    },
    FreshTab {
        #[serde(alias = "workspace_id")]
        workspace_id: String,
        #[serde(alias = "agent_profile_id")]
        agent_profile_id: String,
    },
    ManagedWorkspace {
        #[serde(alias = "source_workspace_id")]
        source_workspace_id: String,
        #[serde(alias = "source_branch")]
        source_branch: String,
        #[serde(default = "default_name_template", alias = "name_template")]
        name_template: String,
        #[serde(alias = "agent_profile_id")]
        agent_profile_id: String,
    },
    /// A new worktree and branch from a project's source branch on this
    /// computer, with no parent workspace.
    ProjectWorktree {
        #[serde(alias = "project_id")]
        project_id: String,
        #[serde(alias = "source_branch")]
        source_branch: String,
        #[serde(default = "default_name_template", alias = "name_template")]
        name_template: String,
        #[serde(alias = "agent_profile_id")]
        agent_profile_id: String,
    },
}

impl AutomationTarget {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::ProjectCheckout { .. } => "projectCheckout",
            Self::ExistingTab { .. } => "existingTab",
            Self::FreshTab { .. } => "freshTab",
            Self::ManagedWorkspace { .. } => "managedWorkspace",
            Self::ProjectWorktree { .. } => "projectWorktree",
        }
    }

    pub fn workspace_id(&self) -> Option<&str> {
        match self {
            Self::ExistingTab { workspace_id, .. } | Self::FreshTab { workspace_id, .. } => {
                Some(workspace_id)
            }
            Self::ManagedWorkspace { .. }
            | Self::ProjectCheckout { .. }
            | Self::ProjectWorktree { .. } => None,
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
            }
            | Self::ProjectCheckout {
                agent_profile_id, ..
            }
            | Self::ProjectWorktree {
                agent_profile_id, ..
            } => Some(agent_profile_id),
        }
    }

    pub fn source_workspace_id(&self) -> Option<&str> {
        match self {
            Self::ManagedWorkspace {
                source_workspace_id,
                ..
            } => Some(source_workspace_id),
            _ => self.workspace_id(),
        }
    }

    pub fn project_checkout(&self) -> Option<(&str, &str)> {
        match self {
            Self::ProjectCheckout {
                project_id,
                host_id,
                ..
            } => Some((project_id, host_id)),
            _ => None,
        }
    }

    pub fn project_worktree(&self) -> Option<(&str, &str)> {
        match self {
            Self::ProjectWorktree {
                project_id,
                source_branch,
                ..
            } => Some((project_id, source_branch)),
            _ => None,
        }
    }

    /// The project a target names directly, without going through a workspace.
    pub fn direct_project_id(&self) -> Option<&str> {
        self.project_checkout()
            .or(self.project_worktree())
            .map(|(project_id, _)| project_id)
    }
}

impl AutomationTarget {
    /// Project targets carry every field they run with, and the definition's
    /// project, when set, must be the one they name.
    pub(super) fn validate_project_target(&self, definition_project: Option<&str>) -> Result<()> {
        let (kind, values) = match self {
            Self::ProjectCheckout {
                project_id,
                host_id,
                name_template,
                agent_profile_id,
            } => (
                "checkout",
                [project_id, host_id, name_template, agent_profile_id],
            ),
            Self::ProjectWorktree {
                project_id,
                source_branch,
                name_template,
                agent_profile_id,
            } => (
                "worktree",
                [project_id, source_branch, name_template, agent_profile_id],
            ),
            _ => return Ok(()),
        };
        if values.iter().any(|value| value.trim().is_empty()) {
            if kind == "checkout" {
                bail!("Project checkout automations require a project, host, task name template and agent profile");
            }
            bail!("Project worktree automations require a project, source branch, task name template and agent profile");
        }
        if definition_project.is_some_and(|id| id != values[0]) {
            bail!("Automation project does not match its project {kind} target");
        }
        Ok(())
    }
}

fn default_name_template() -> String {
    AUTOMATION_DEFAULT_NAME_TEMPLATE.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn project_checkout_contract_keeps_host_explicit_and_has_no_workspace_dependency() {
        let target: AutomationTarget = serde_json::from_value(serde_json::json!({
            "projectCheckout": {"projectId":"project", "hostId":"ssh", "agentProfileId":"profile"}
        }))
        .unwrap();
        assert_eq!(target.kind(), "projectCheckout");
        assert_eq!(target.project_checkout(), Some(("project", "ssh")));
        assert_eq!(target.agent_profile_id(), Some("profile"));
        assert!(target.workspace_id().is_none());
        assert!(target.source_workspace_id().is_none());
        assert_eq!(
            serde_json::to_value(target).unwrap()["projectCheckout"]["nameTemplate"],
            AUTOMATION_DEFAULT_NAME_TEMPLATE
        );
        assert!(
            serde_json::from_value::<AutomationTarget>(serde_json::json!({
                "projectCheckout": {"projectId":"project", "agentProfileId":"profile"}
            }))
            .is_err()
        );
    }

    #[test]
    fn project_worktree_contract_names_a_project_and_a_source_branch() {
        let target: AutomationTarget = serde_json::from_value(serde_json::json!({
            "projectWorktree": {"projectId":"project", "sourceBranch":"main", "agentProfileId":"profile"}
        }))
        .unwrap();
        assert_eq!(target.kind(), "projectWorktree");
        assert_eq!(target.project_worktree(), Some(("project", "main")));
        assert_eq!(target.direct_project_id(), Some("project"));
        assert_eq!(target.agent_profile_id(), Some("profile"));
        assert!(target.workspace_id().is_none());
        assert!(target.source_workspace_id().is_none());
        assert!(target.project_checkout().is_none());
        let encoded = serde_json::to_value(&target).unwrap();
        assert_eq!(
            encoded,
            serde_json::json!({"projectWorktree": {
                "projectId": "project",
                "sourceBranch": "main",
                "nameTemplate": AUTOMATION_DEFAULT_NAME_TEMPLATE,
                "agentProfileId": "profile",
            }})
        );
        let snake: AutomationTarget = serde_json::from_value(serde_json::json!({
            "projectWorktree": {"project_id":"project", "source_branch":"main", "agent_profile_id":"profile"}
        }))
        .unwrap();
        assert_eq!(snake, target);
        assert!(
            serde_json::from_value::<AutomationTarget>(serde_json::json!({
                "projectWorktree": {"projectId":"project", "agentProfileId":"profile"}
            }))
            .is_err()
        );
    }
}
