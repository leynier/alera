use super::AUTOMATION_DEFAULT_NAME_TEMPLATE;
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
}

impl AutomationTarget {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::ProjectCheckout { .. } => "projectCheckout",
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
            Self::ManagedWorkspace { .. } | Self::ProjectCheckout { .. } => None,
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
}
