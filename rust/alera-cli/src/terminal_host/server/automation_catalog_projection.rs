use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{
    AutomationDefinition, AutomationRun, AutomationRunStatus, AutomationState,
};
use serde_json::{json, Value};
use std::collections::HashMap;

/// Reads shared by every item of one catalog listing, so a long list does not
/// reload the active runs or probe an agent profile's PATH once per item.
pub(super) struct AutomationCatalogContext {
    active: Vec<AutomationRun>,
    reserved: Vec<AutomationRun>,
    pub(super) profile_readiness: HashMap<String, Result<(), String>>,
}

impl ServerActor {
    pub(super) async fn automation_catalog_context(&self) -> HostResult<AutomationCatalogContext> {
        Ok(AutomationCatalogContext {
            active: self
                .runtime_store
                .list_active_automation_runs()
                .await
                .map_err(|e| HostError::state(e.to_string()))?,
            reserved: self
                .runtime_store
                .reserved_automation_runs()
                .await
                .map_err(|e| HostError::state(e.to_string()))?,
            profile_readiness: HashMap::new(),
        })
    }

    pub(super) async fn automation_catalog_item(
        &self,
        definition: &AutomationDefinition,
    ) -> HostResult<Value> {
        let mut context = self.automation_catalog_context().await?;
        self.automation_catalog_item_in(definition, &mut context)
            .await
    }

    /// "Workspace API · tab Codex", with "(missing)" for whatever the binding
    /// names that no longer exists.
    async fn bound_target_summary(&self, definition: &AutomationDefinition) -> Option<String> {
        let binding = definition.bound_target.as_ref()?;
        let Some(workspace) = self
            .runtime_store
            .find_workspace(&binding.workspace_id)
            .await
            .ok()
            .flatten()
        else {
            return Some("Workspace (missing)".into());
        };
        let Some(tab_id) = binding.tab_id.as_deref() else {
            return Some(format!("Workspace {}", workspace.name));
        };
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .ok()
            .flatten()
            .filter(|tab| tab.workspace_id == workspace.id);
        Some(match tab {
            Some(tab) => format!("Workspace {} · tab {}", workspace.name, tab.title),
            None => format!("Workspace {} · tab (missing)", workspace.name),
        })
    }

    pub(super) async fn automation_catalog_item_in(
        &self,
        definition: &AutomationDefinition,
        context: &mut AutomationCatalogContext,
    ) -> HostResult<Value> {
        let mut value =
            serde_json::to_value(definition).map_err(|e| HostError::state(e.to_string()))?;
        let associated_id = definition
            .origin_workspace_id
            .as_deref()
            .or(definition.target.source_workspace_id());
        let workspace = match associated_id {
            Some(id) => self.runtime_store.find_workspace(id).await.ok().flatten(),
            None => None,
        };
        let location = self.automation_target_location(definition).await.ok();
        let project_id = location.as_ref().map(|loc| loc.project.id.as_str());
        value["association"] = json!({"workspaceId":workspace.as_ref().map(|w| &w.id),"sectionId":workspace.as_ref().and_then(|w| w.section_id.as_ref()),"projectId":project_id,"source":if definition.origin_workspace_id.is_some() {"origin"} else if workspace.is_some() {"targetWorkspace"} else {"project"}});
        value["reusePolicy"] = json!(definition.reuse_policy.as_str());
        value["boundTarget"] = json!(definition.bound_target);
        value["boundTargetSummary"] = json!(self.bound_target_summary(definition).await);
        value["targetHostId"] = json!(location.as_ref().map(|loc| &loc.host_id));
        value["targetSummary"] = json!(location
            .as_ref()
            .map(|loc| format!("{} · {}", loc.project.name, loc.path)));
        let readiness = self
            .automation_readiness_in(definition, false, Some(&mut context.profile_readiness))
            .await;
        value["nextRunAt"] = if definition.state == AutomationState::Active {
            readiness["occurrences"]
                .as_array()
                .and_then(|a| a.first())
                .map(|o| o["scheduledAt"].clone())
                .unwrap_or(Value::Null)
        } else {
            Value::Null
        };
        value["readiness"] = readiness;
        let last_run = self
            .runtime_store
            .list_automation_runs(Some(&definition.id), 1)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .into_iter()
            .next();
        value["activeRunCount"] = json!(context
            .active
            .iter()
            .filter(|run| run.automation_id == definition.id)
            .count());
        let attention_run = context
            .reserved
            .iter()
            .find(|run| run.automation_id == definition.id)
            .or_else(|| {
                context.active.iter().find(|run| {
                    run.automation_id == definition.id
                        && run.status == AutomationRunStatus::WaitingForUser
                })
            })
            .or_else(|| {
                last_run.as_ref().filter(|run| {
                    matches!(
                        run.status,
                        AutomationRunStatus::Failure
                            | AutomationRunStatus::Timeout
                            | AutomationRunStatus::Blocked
                    )
                })
            });
        value["lastRun"] = last_run.as_ref().map(|run| json!({"id":run.id,"status":run.status,"finishedAt":run.finished_at,"summary":run.summary})).unwrap_or(Value::Null);
        value["attention"] = if definition.state == AutomationState::Blocked {
            let message = self
                .runtime_store
                .latest_automation_run_error(&definition.id)
                .await
                .ok()
                .flatten();
            json!({"code":"blocked","message":message.as_deref().unwrap_or("Check the execution target and schedule"),"since":definition.updated_at})
        } else {
            attention_run.map(|run| json!({"code":if run.owner_reserved {"ownerReserved"} else if run.status == AutomationRunStatus::WaitingForUser {"waitingForUser"} else {"runFailed"},"message":run.error.as_deref().unwrap_or("This run needs attention"),"since":run.updated_at})).unwrap_or(Value::Null)
        };
        Ok(value)
    }
}
