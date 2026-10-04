use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{AutomationDefinition, AutomationState};
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn automation_catalog_item(
        &self,
        definition: &AutomationDefinition,
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
        value["targetHostId"] = json!(location.as_ref().map(|loc| &loc.host_id));
        value["targetSummary"] = json!(location
            .as_ref()
            .map(|loc| format!("{} · {}", loc.project.name, loc.path)));
        let readiness = self.automation_readiness(definition, false).await;
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
        let runs = self
            .runtime_store
            .list_automation_runs(Some(&definition.id), 100)
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        let active = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        let reserved = self
            .runtime_store
            .reserved_automation_runs()
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        value["activeRunCount"] = json!(active
            .iter()
            .filter(|run| run.automation_id == definition.id)
            .count());
        let attention_run = reserved
            .iter()
            .find(|run| run.automation_id == definition.id)
            .or_else(|| {
                active.iter().find(|run| {
                    run.automation_id == definition.id
                        && run.status == alera_core::runtime::AutomationRunStatus::WaitingForUser
                })
            })
            .or_else(|| {
                runs.first().filter(|run| {
                    matches!(
                        run.status,
                        alera_core::runtime::AutomationRunStatus::Failure
                            | alera_core::runtime::AutomationRunStatus::Timeout
                            | alera_core::runtime::AutomationRunStatus::Blocked
                    )
                })
            });
        value["lastRun"] = runs.first().map(|run| json!({"id":run.id,"status":run.status,"finishedAt":run.finished_at,"summary":run.summary})).unwrap_or(Value::Null);
        value["attention"] = if definition.state == AutomationState::Blocked {
            json!({"code":"blocked","message":runs.iter().find_map(|run| run.error.as_deref()).unwrap_or("Check the execution target and schedule"),"since":definition.updated_at})
        } else {
            attention_run.map(|run| json!({"code":if run.owner_reserved {"ownerReserved"} else if run.status == alera_core::runtime::AutomationRunStatus::WaitingForUser {"waitingForUser"} else {"runFailed"},"message":run.error.as_deref().unwrap_or("This run needs attention"),"since":run.updated_at})).unwrap_or(Value::Null)
        };
        Ok(value)
    }
}
