use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::{AutomationCleanupPolicy, AutomationTarget};

pub const AUTOMATION_REUSE_WORKSPACE_EXISTING_TAB_ERROR: &str =
    "Reuse Workspace does not apply to an existing tab target; choose Reuse Conversation or New Each Run";
pub const AUTOMATION_REUSE_CLEANUP_ERROR: &str =
    "Cleanup on success would remove what a reusing automation returns to; choose Preserve cleanup or New Each Run";

/// Where a run after the first one is delivered.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationReusePolicy {
    #[default]
    NewEachRun,
    ReuseWorkspace,
    ReuseConversation,
}

impl AutomationReusePolicy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::NewEachRun => "newEachRun",
            Self::ReuseWorkspace => "reuseWorkspace",
            Self::ReuseConversation => "reuseConversation",
        }
    }

    pub fn is_default(&self) -> bool {
        *self == Self::NewEachRun
    }

    pub fn reuses(self) -> bool {
        self != Self::NewEachRun
    }
}

/// The workspace, and for conversation reuse the tab, a reusing automation
/// returns to. The runtime writes it after a dispatch; clients never do.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationBoundTarget {
    pub workspace_id: String,
    #[serde(default)]
    pub tab_id: Option<String>,
    #[serde(default)]
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub agent_profile_id: Option<String>,
    pub bound_run_id: String,
    pub bound_at: DateTime<Utc>,
    #[serde(default)]
    pub last_run_id: Option<String>,
    #[serde(default)]
    pub last_verified_at: Option<DateTime<Utc>>,
}

/// How one run reached its target under a reuse policy.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AutomationRunReuse {
    /// Created the target and bound the automation to it.
    Bound,
    /// Pasted into the bound, idle conversation.
    Conversation,
    /// Relaunched the bound conversation in a new tab of the same workspace.
    ResumedConversation,
    /// Opened a new tab in the bound workspace.
    Workspace,
}

impl AutomationRunReuse {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bound => "bound",
            Self::Conversation => "conversation",
            Self::ResumedConversation => "resumedConversation",
            Self::Workspace => "workspace",
        }
    }
}

pub fn validate_reuse(
    policy: AutomationReusePolicy,
    target: &AutomationTarget,
    cleanup: Option<AutomationCleanupPolicy>,
) -> Result<()> {
    if policy == AutomationReusePolicy::ReuseWorkspace
        && matches!(target, AutomationTarget::ExistingTab { .. })
    {
        bail!(AUTOMATION_REUSE_WORKSPACE_EXISTING_TAB_ERROR);
    }
    if policy.reuses() && cleanup == Some(AutomationCleanupPolicy::OnSuccess) {
        bail!(AUTOMATION_REUSE_CLEANUP_ERROR);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_tab() -> AutomationTarget {
        AutomationTarget::FreshTab {
            workspace_id: "workspace".into(),
            agent_profile_id: "profile".into(),
        }
    }

    fn existing_tab() -> AutomationTarget {
        AutomationTarget::ExistingTab {
            workspace_id: "workspace".into(),
            tab_id: "tab".into(),
            conversation_id: Some("conversation".into()),
        }
    }

    #[test]
    fn policy_serializes_camel_case_and_defaults_to_new_each_run() {
        assert_eq!(
            AutomationReusePolicy::default(),
            AutomationReusePolicy::NewEachRun
        );
        for policy in [
            AutomationReusePolicy::NewEachRun,
            AutomationReusePolicy::ReuseWorkspace,
            AutomationReusePolicy::ReuseConversation,
        ] {
            assert_eq!(serde_json::to_value(policy).unwrap(), policy.as_str());
            assert_eq!(policy.reuses(), !policy.is_default());
        }
        for reuse in [
            AutomationRunReuse::Bound,
            AutomationRunReuse::Conversation,
            AutomationRunReuse::ResumedConversation,
            AutomationRunReuse::Workspace,
        ] {
            assert_eq!(serde_json::to_value(reuse).unwrap(), reuse.as_str());
        }
    }

    #[test]
    fn bound_target_reads_without_optional_fields() {
        let bound: AutomationBoundTarget = serde_json::from_value(serde_json::json!({
            "workspaceId": "workspace",
            "boundRunId": "run",
            "boundAt": "2026-10-11T00:00:00Z",
        }))
        .unwrap();
        assert_eq!(bound.tab_id, None);
        assert_eq!(bound.last_run_id, None);
        let encoded = serde_json::to_value(&bound).unwrap();
        assert_eq!(encoded["workspaceId"], "workspace");
        assert!(encoded["tabId"].is_null());
    }

    #[test]
    fn reuse_rejects_workspace_reuse_of_an_existing_tab_and_cleanup_on_success() {
        let workspace = AutomationReusePolicy::ReuseWorkspace;
        let conversation = AutomationReusePolicy::ReuseConversation;
        assert!(validate_reuse(workspace, &existing_tab(), None)
            .unwrap_err()
            .to_string()
            .contains("Reuse Workspace"));
        assert!(validate_reuse(conversation, &existing_tab(), None).is_ok());
        assert!(validate_reuse(workspace, &fresh_tab(), None).is_ok());
        let cleanup = Some(AutomationCleanupPolicy::OnSuccess);
        assert!(validate_reuse(conversation, &fresh_tab(), cleanup)
            .unwrap_err()
            .to_string()
            .contains("Cleanup"));
        assert!(validate_reuse(AutomationReusePolicy::NewEachRun, &fresh_tab(), cleanup).is_ok());
        assert!(validate_reuse(
            conversation,
            &fresh_tab(),
            Some(AutomationCleanupPolicy::Preserve)
        )
        .is_ok());
    }
}
