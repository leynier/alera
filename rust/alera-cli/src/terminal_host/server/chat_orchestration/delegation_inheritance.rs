//! What a new child chat inherits from the agent that delegates to it: the
//! provider instance, the model on that instance, and the reasoning effort
//! when nothing about the selection changed. A person's delegation and a
//! delegation to an existing chat inherit nothing.

use serde_json::{json, Value};

use super::authorization::OrchestrationCaller;
use super::delegation_options::delegation_effort;
use super::models::{DelegateInput, ParsedTarget};
use super::service::ChatOrchestrationService;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const EFFORT_EXPLICIT: &str = "explicit";
pub(super) const EFFORT_INHERITED: &str = "inherited";

/// The effort a new child starts with, and where it came from.
#[derive(Debug, Clone, Default, PartialEq)]
pub(super) struct ChildEffort {
    pub effort: Option<String>,
    pub source: Option<&'static str>,
}

impl ChildEffort {
    pub(super) fn inherited(&self) -> bool {
        self.source == Some(EFFORT_INHERITED)
    }

    /// Records the effort in the task's launch options.
    pub(super) fn record(&self, options: &mut Value) {
        if let (Some(effort), Some(source), Some(options)) =
            (&self.effort, self.source, options.as_object_mut())
        {
            options.insert("reasoningEffort".into(), json!(effort));
            options.insert("reasoningEffortSource".into(), json!(source));
        }
    }
}

impl ChatOrchestrationService {
    /// Fills `input.agent` from the delegating agent's chat and returns the
    /// new child's effort. A new chat without a provider instance fails
    /// before any workspace is prepared.
    pub(super) async fn inherit_agent(
        &self,
        input: &mut DelegateInput,
        caller: &OrchestrationCaller,
    ) -> HostResult<ChildEffort> {
        let explicit = delegation_effort(input.agent.options.as_ref())?;
        let new_chat = !matches!(input.target, ParsedTarget::Chat { .. });
        let mut effort = ChildEffort {
            source: explicit.as_ref().map(|_| EFFORT_EXPLICIT),
            effort: explicit,
        };
        if let (true, Some(bound)) = (new_chat, &caller.bound) {
            let parent = self.runtime.snapshot(&bound.chat_id).await?;
            let parent_instance = parent["providerInstanceId"].as_str().map(ToOwned::to_owned);
            let parent_model = parent["session"]["model"].as_str().map(ToOwned::to_owned);
            let same_instance = input.agent.provider_instance_id.is_none()
                || input.agent.provider_instance_id == parent_instance;
            if input.agent.provider_instance_id.is_none() {
                input.agent.provider_instance_id = parent_instance.clone();
            }
            let same_model =
                same_instance && (input.agent.model.is_none() || input.agent.model == parent_model);
            if same_instance && input.agent.model.is_none() {
                input.agent.model = parent_model;
            }
            // `{}` clears the effort; only absent options inherit it.
            let options_absent = input.agent.options.as_ref().is_none_or(Value::is_null);
            if same_model && options_absent && self.same_host(&parent, &input.target).await {
                if let Some(parent_effort) = parent["session"]["reasoningEffort"].as_str() {
                    effort = ChildEffort {
                        effort: Some(parent_effort.to_owned()),
                        source: Some(EFFORT_INHERITED),
                    };
                }
            }
        }
        if new_chat && input.agent.provider_instance_id.is_none() {
            return Err(HostError::conflict(
                "providerUnavailable",
                "A providerInstanceId is required for a new chat target.",
                json!({}),
            ));
        }
        Ok(effort)
    }

    /// Whether the new child runs on the host of the parent chat.
    async fn same_host(&self, parent: &Value, target: &ParsedTarget) -> bool {
        let host_of = |workspace: Option<String>| async move {
            let workspace = workspace?;
            self.store
                .find_workspace(&workspace)
                .await
                .ok()
                .flatten()
                .map(|workspace| workspace.host_id)
        };
        let parent_host = host_of(parent["workspaceId"].as_str().map(ToOwned::to_owned)).await;
        let target_host = match target {
            ParsedTarget::Workspace { workspace_id } => host_of(Some(workspace_id.clone())).await,
            ParsedTarget::NewWorkspace(target) => Some(target.spec.host_id.clone()),
            ParsedTarget::Chat { .. } => None,
        };
        parent_host.is_some() && parent_host == target_host
    }
}

/// Whether an error from creating the child is its refusal of the effort.
pub(super) fn effort_refused(error: &HostError) -> bool {
    error.wire_message().to_lowercase().contains("effort")
}
