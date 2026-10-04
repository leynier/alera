use alera_core::runtime::{
    automation_from_input, preview_occurrences, AutomationDefinition, AutomationState,
    RuntimeStore, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::{json, Value};

use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) async fn automation_authoring_request(
        &mut self,
        client_id: u64,
        kind: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        if kind == "automation.previewSchedule" {
            let schedule = serde_json::from_value(payload["schedule"].clone())
                .map_err(|e| HostError::format(format!("Invalid schedule: {e}")))?;
            let occurrences = preview_occurrences(
                "preview",
                &schedule,
                Utc::now(),
                payload["count"].as_u64().unwrap_or(3).clamp(1, 10) as usize,
            )
            .map_err(HostError::format)?;
            return Ok(json!({"occurrences":occurrences,"timezone":schedule.timezone()}));
        }
        let actor = self
            .resolve_policy_actor(
                client_id,
                payload,
                self.automation_actor(client_id, payload),
            )
            .await?;
        let definition = if let Some(id) = payload["id"].as_str() {
            let saved = self
                .runtime_store
                .find_automation(id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::state("Automation not found"))?;
            if payload["expectedRevision"]
                .as_i64()
                .is_some_and(|rev| rev != saved.revision)
            {
                return Err(HostError::conflict(
                    "automationRevisionConflict",
                    "This automation changed; refresh before saving",
                    json!({"revision":saved.revision}),
                ));
            }
            if kind == "automation.patch" && !saved.state.is_editable() {
                return Err(HostError::state(
                    "Clone this completed automation before editing it",
                ));
            }
            let mut merged = serde_json::to_value(&saved).map_err(state_error)?;
            if kind == "automation.patch" {
                let changes = payload["changes"]
                    .as_object()
                    .ok_or_else(|| HostError::format("changes must be an object"))?;
                for (key, value) in changes {
                    if !matches!(
                        key.as_str(),
                        "id" | "revision"
                            | "approvedRevision"
                            | "state"
                            | "createdBy"
                            | "createdAt"
                            | "creationRequestKey"
                            | "scheduleCursorAt"
                            | "stateBeforeTrash"
                    ) {
                        merged[key] = value.clone();
                    }
                }
            }
            serde_json::from_value(merged).map_err(state_error)?
        } else {
            if let Some(key) = payload["requestKey"].as_str() {
                if key.trim().is_empty() || key.len() > 128 {
                    return Err(HostError::format("requestKey must contain 1 to 128 bytes"));
                }
                if let Some(saved) = self
                    .runtime_store
                    .automation_by_request_key(key)
                    .await
                    .map_err(state_error)?
                {
                    return self.automation_catalog_item(&saved).await;
                }
            }
            match automation_from_input(payload.get("automation").unwrap_or(payload), actor.clone())
            {
                Ok(mut definition) => {
                    definition.creation_request_key =
                        payload["requestKey"].as_str().map(str::to_string);
                    definition
                }
                Err(error) if kind == "automation.readiness" => {
                    return Ok(
                        json!({"ready":false,"issues":[issue("invalidDefinition", &error.to_string(), validation_field(&error.to_string()), "error", "EditAutomation")],"occurrences":[]}),
                    )
                }
                Err(error) => return Err(HostError::format(error.to_string())),
            }
        };
        let readiness = self
            .automation_readiness(
                &definition,
                (kind == "automation.readiness" && payload["id"].is_null())
                    || (kind != "automation.readiness"
                        && definition.state == AutomationState::Active),
            )
            .await;
        if kind == "automation.readiness" {
            return Ok(readiness);
        }
        if definition.state == AutomationState::Active && readiness["ready"] != true {
            return Err(HostError::conflict(
                "automationNotReady",
                "Fix the highlighted fields before activating",
                readiness,
            ));
        }
        let saved = self
            .runtime_store
            .upsert_automation(definition, actor)
            .await
            .map_err(state_error)?;
        self.automations_active = self
            .runtime_store
            .has_pending_automation_work()
            .await
            .map_err(state_error)?;
        self.automation_wake.notify_one();
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationsChanged",
            json!({"automationId":saved.id}),
        ));
        self.automation_catalog_item(&saved).await
    }

    pub(super) async fn automation_readiness(
        &self,
        definition: &AutomationDefinition,
        require_future: bool,
    ) -> Value {
        let mut issues = Vec::new();
        if let Err(error) = RuntimeStore::validate_automation_definition(definition) {
            issues.push(issue(
                "invalidDefinition",
                &error.to_string(),
                validation_field(&error.to_string()),
                "error",
                "EditAutomation",
            ));
        }
        let occurrences = preview_occurrences(&definition.id, &definition.schedule, Utc::now(), 5)
            .unwrap_or_default();
        if require_future && occurrences.is_empty() {
            issues.push(issue(
                "noFutureOccurrences",
                "Choose a schedule with a future occurrence",
                "schedule",
                "error",
                "EditSchedule",
            ));
        }
        match self.automation_target_location(definition).await {
            Err(error) => issues.push(issue(
                "targetUnavailable",
                &error.wire_message(),
                "target",
                "error",
                "ChooseTarget",
            )),
            Ok(location) => {
                if definition
                    .project_id
                    .as_deref()
                    .is_some_and(|id| id != location.project.id)
                {
                    issues.push(issue(
                        "projectMismatch",
                        "The project must match the execution target",
                        "projectId",
                        "error",
                        "ChooseTarget",
                    ));
                }
                if let Err(error) = self
                    .ensure_dispatch_policy(definition, &definition.modified_by)
                    .await
                {
                    issues.push(issue(
                        "invalidTarget",
                        &error.wire_message(),
                        "target",
                        "error",
                        "ChooseTarget",
                    ));
                }
                if location.host_id != LOCAL_HOST_ID {
                    issues.push(issue(
                        "remoteAvailability",
                        "Remote availability is checked when the run starts",
                        "target",
                        "warning",
                        "CheckHost",
                    ));
                }
            }
        }
        match self.target_profile_id(definition).await {
            Ok(Some(id)) => match self.runtime_store.find_agent_profile(&id).await {
                Ok(Some(profile)) => {
                    if let Err(error) =
                        super::orchestration_profile_spawn::launch_for_profile(&profile)
                    {
                        issues.push(issue(
                            "invalidProfile",
                            &error,
                            "target",
                            "error",
                            "OpenAgentProfiles",
                        ));
                    } else if self
                        .automation_target_location(definition)
                        .await
                        .ok()
                        .is_some_and(|location| location.host_id == LOCAL_HOST_ID)
                    {
                        if let Err(error) =
                            super::automation_profile_readiness::profile_executable_ready(&profile)
                                .await
                        {
                            issues.push(issue(
                                "profileNotLaunchable",
                                &error,
                                "target",
                                "error",
                                "OpenAgentProfiles",
                            ));
                        }
                    }
                }
                _ => issues.push(issue(
                    "missingProfile",
                    "Choose an existing agent profile",
                    "target",
                    "error",
                    "OpenAgentProfiles",
                )),
            },
            _ => issues.push(issue(
                "missingProfile",
                "The target must have an agent profile",
                "target",
                "error",
                "OpenAgentProfiles",
            )),
        }
        if let alera_core::runtime::AutomationTarget::ExistingTab {
            conversation_id,
            tab_id,
            ..
        } = &definition.target
        {
            let capturable = self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .ok()
                .flatten()
                .is_some_and(|tab| {
                    conversation_id
                        .as_deref()
                        .is_some_and(|id| tab.payload["conversationId"].as_str() == Some(id))
                        && super::requests::terminal_session_id_from_tab(&tab).is_some()
                });
            if !capturable
                || conversation_id
                    .as_deref()
                    .is_none_or(|id| id.trim().is_empty())
            {
                issues.push(issue(
                    "missingConversation",
                    "Choose a live agent conversation",
                    "target",
                    "error",
                    "ChooseTarget",
                ));
            }
        }
        if let Some(origin) = definition.origin_workspace_id.as_deref() {
            if self
                .runtime_store
                .find_workspace(origin)
                .await
                .ok()
                .flatten()
                .is_none()
            {
                issues.push(issue(
                    "missingOrigin",
                    "The originating workspace no longer exists",
                    "originWorkspaceId",
                    "error",
                    "ChooseTarget",
                ));
            }
        }
        let ready = !issues.iter().any(|issue| issue["severity"] == "error");
        json!({"ready":ready,"issues":issues,"occurrences":occurrences,"timezone":definition.schedule.timezone()})
    }

    pub(super) async fn migrate_retired_automation_gates(&mut self) {
        let candidates = self
            .runtime_store
            .retired_gate_reactivation_candidates()
            .await
            .unwrap_or_default();
        for definition in candidates {
            let readiness = self.automation_readiness(&definition, true).await;
            let state = if readiness["ready"] == true {
                AutomationState::Active
            } else {
                AutomationState::Blocked
            };
            if self
                .runtime_store
                .set_automation_state(
                    &definition.id,
                    state,
                    definition.modified_by.clone(),
                    Some("Automation approval gates retired"),
                )
                .await
                .is_ok()
            {
                let _ = self.runtime_store.insert_automation_audit_event(Some(&definition.id), None, "retiredGatesMigrated", definition.modified_by, Some(definition.revision), json!({"reactivated":state == AutomationState::Active,"readiness":readiness})).await;
            }
        }
    }
}

fn issue(code: &str, message: &str, field: &str, severity: &str, action: &str) -> Value {
    json!({"code":code,"message":message,"field":field,"severity":severity,"action":action})
}
fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

fn validation_field(error: &str) -> &'static str {
    if error.contains("prompt") || error.contains("variable") || error.contains("delimiter") {
        "promptTemplate"
    } else if error.contains("cron") || error.contains("timezone") || error.contains("schedule") {
        "schedule"
    } else if error.contains("target") || error.contains("workspace") || error.contains("profile") {
        "target"
    } else {
        "automation"
    }
}
