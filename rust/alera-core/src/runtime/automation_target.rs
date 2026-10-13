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
    /// A new worktree and branch created on this computer for each run. With a
    /// parent workspace the project comes from that workspace and the
    /// worktree is nested under it. The legacy `managedWorkspace` and
    /// `projectWorktree` spellings still deserialize into this variant.
    #[serde(alias = "managedWorkspace", alias = "projectWorktree")]
    Worktree {
        #[serde(default, alias = "project_id", skip_serializing_if = "Option::is_none")]
        project_id: Option<String>,
        #[serde(
            default,
            alias = "sourceWorkspaceId",
            alias = "source_workspace_id",
            alias = "parent_workspace_id",
            skip_serializing_if = "Option::is_none"
        )]
        parent_workspace_id: Option<String>,
        #[serde(alias = "source_branch")]
        source_branch: String,
        #[serde(default = "default_name_template", alias = "name_template")]
        name_template: String,
        #[serde(alias = "agent_profile_id")]
        agent_profile_id: String,
    },
}

/// The fields a [`AutomationTarget::Worktree`] runs with, with empty ids
/// read as absent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AutomationWorktreeSpec<'a> {
    pub project_id: Option<&'a str>,
    pub parent_workspace_id: Option<&'a str>,
    pub source_branch: &'a str,
    pub name_template: &'a str,
    pub agent_profile_id: &'a str,
}

impl AutomationTarget {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::ProjectCheckout { .. } => "projectCheckout",
            Self::ExistingTab { .. } => "existingTab",
            Self::FreshTab { .. } => "freshTab",
            Self::Worktree { .. } => "worktree",
        }
    }

    pub fn workspace_id(&self) -> Option<&str> {
        match self {
            Self::ExistingTab { workspace_id, .. } | Self::FreshTab { workspace_id, .. } => {
                Some(workspace_id)
            }
            Self::Worktree { .. } | Self::ProjectCheckout { .. } => None,
        }
    }

    pub fn agent_profile_id(&self) -> Option<&str> {
        match self {
            Self::ExistingTab { .. } => None,
            Self::FreshTab {
                agent_profile_id, ..
            }
            | Self::Worktree {
                agent_profile_id, ..
            }
            | Self::ProjectCheckout {
                agent_profile_id, ..
            } => Some(agent_profile_id),
        }
    }

    /// The workspace a run reads from: the target workspace of a tab target or
    /// the parent of a worktree target.
    pub fn source_workspace_id(&self) -> Option<&str> {
        match self.worktree() {
            Some(spec) => spec.parent_workspace_id,
            None => self.workspace_id(),
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

    pub fn worktree(&self) -> Option<AutomationWorktreeSpec<'_>> {
        match self {
            Self::Worktree {
                project_id,
                parent_workspace_id,
                source_branch,
                name_template,
                agent_profile_id,
            } => Some(AutomationWorktreeSpec {
                project_id: non_empty(project_id.as_deref()),
                parent_workspace_id: non_empty(parent_workspace_id.as_deref()),
                source_branch,
                name_template,
                agent_profile_id,
            }),
            _ => None,
        }
    }

    /// The project a target names directly, without going through a workspace.
    pub fn direct_project_id(&self) -> Option<&str> {
        self.project_checkout()
            .map(|(project_id, _)| project_id)
            .or_else(|| self.worktree().and_then(|spec| spec.project_id))
    }
}

impl AutomationTarget {
    /// Project targets carry every field they run with, and the definition's
    /// project, when set, must be the one they name.
    pub(super) fn validate_project_target(&self, definition_project: Option<&str>) -> Result<()> {
        let (kind, project) = match self {
            Self::ProjectCheckout {
                project_id,
                host_id,
                name_template,
                agent_profile_id,
            } => {
                if [project_id, host_id, name_template, agent_profile_id]
                    .iter()
                    .any(|value| value.trim().is_empty())
                {
                    bail!("Project checkout automations require a project, host, task name template and agent profile");
                }
                ("checkout", project_id.as_str())
            }
            Self::Worktree {
                source_branch,
                name_template,
                agent_profile_id,
                ..
            } => {
                if [source_branch, name_template, agent_profile_id]
                    .iter()
                    .any(|value| value.trim().is_empty())
                {
                    bail!("Worktree automations require a source branch, task name template and agent profile");
                }
                let spec = self.worktree().expect("worktree target");
                if spec.project_id.is_none() && spec.parent_workspace_id.is_none() {
                    bail!("Worktree automations require a project or a parent workspace");
                }
                let Some(project) = spec.project_id else {
                    return Ok(());
                };
                ("worktree", project)
            }
            _ => return Ok(()),
        };
        if definition_project.is_some_and(|id| id != project) {
            bail!("Automation project does not match its project {kind} target");
        }
        Ok(())
    }
}

fn non_empty(value: Option<&str>) -> Option<&str> {
    value.filter(|value| !value.trim().is_empty())
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
    fn worktree_contract_names_a_project_and_a_source_branch() {
        let target: AutomationTarget = serde_json::from_value(serde_json::json!({
            "worktree": {"projectId":"project", "sourceBranch":"main", "agentProfileId":"profile"}
        }))
        .unwrap();
        assert_eq!(target.kind(), "worktree");
        let spec = target.worktree().unwrap();
        assert_eq!(spec.project_id, Some("project"));
        assert_eq!(spec.parent_workspace_id, None);
        assert_eq!(spec.source_branch, "main");
        assert_eq!(target.direct_project_id(), Some("project"));
        assert_eq!(target.agent_profile_id(), Some("profile"));
        assert!(target.workspace_id().is_none());
        assert!(target.source_workspace_id().is_none());
        assert!(target.project_checkout().is_none());
        assert_eq!(
            serde_json::to_value(&target).unwrap(),
            serde_json::json!({"worktree": {
                "projectId": "project",
                "sourceBranch": "main",
                "nameTemplate": AUTOMATION_DEFAULT_NAME_TEMPLATE,
                "agentProfileId": "profile",
            }})
        );
        assert!(
            serde_json::from_value::<AutomationTarget>(serde_json::json!({
                "worktree": {"projectId":"project", "agentProfileId":"profile"}
            }))
            .is_err()
        );
    }

    #[test]
    fn legacy_worktree_spellings_read_as_worktree_and_write_the_new_name() {
        let project: AutomationTarget = serde_json::from_value(serde_json::json!({
            "projectWorktree": {"project_id":"project", "source_branch":"main", "agent_profile_id":"profile"}
        }))
        .unwrap();
        assert_eq!(project.worktree().unwrap().project_id, Some("project"));
        assert_eq!(
            serde_json::to_value(&project).unwrap()["worktree"]["projectId"],
            "project"
        );
        let managed: AutomationTarget = serde_json::from_value(serde_json::json!({
            "managedWorkspace": {"sourceWorkspaceId":"parent", "sourceBranch":"main", "agentProfileId":"profile", "nameTemplate":"n"}
        }))
        .unwrap();
        let spec = managed.worktree().unwrap();
        assert_eq!(spec.parent_workspace_id, Some("parent"));
        assert_eq!(spec.project_id, None);
        assert_eq!(managed.source_workspace_id(), Some("parent"));
        assert_eq!(managed.direct_project_id(), None);
        let encoded = serde_json::to_value(&managed).unwrap();
        assert_eq!(
            encoded,
            serde_json::json!({"worktree": {
                "parentWorkspaceId": "parent",
                "sourceBranch": "main",
                "nameTemplate": "n",
                "agentProfileId": "profile",
            }})
        );
        let round_trip: AutomationTarget = serde_json::from_value(encoded).unwrap();
        assert_eq!(round_trip, managed);
        let snake: AutomationTarget = serde_json::from_value(serde_json::json!({
            "managedWorkspace": {"source_workspace_id":"parent", "source_branch":"main", "agent_profile_id":"profile", "name_template":"n"}
        }))
        .unwrap();
        assert_eq!(snake, managed);
    }

    #[test]
    fn worktree_validation_requires_a_project_or_a_parent() {
        let target = |project: Option<&str>, parent: Option<&str>| AutomationTarget::Worktree {
            project_id: project.map(str::to_string),
            parent_workspace_id: parent.map(str::to_string),
            source_branch: "main".into(),
            name_template: "n".into(),
            agent_profile_id: "profile".into(),
        };
        assert!(target(None, None).validate_project_target(None).is_err());
        assert!(target(Some(" "), None)
            .validate_project_target(None)
            .is_err());
        assert!(target(None, Some("parent"))
            .validate_project_target(None)
            .is_ok());
        assert!(target(None, Some("parent"))
            .validate_project_target(Some("any"))
            .is_ok());
        assert!(target(Some("p"), None)
            .validate_project_target(Some("p"))
            .is_ok());
        assert!(target(Some("p"), None)
            .validate_project_target(Some("q"))
            .is_err());
    }
}
