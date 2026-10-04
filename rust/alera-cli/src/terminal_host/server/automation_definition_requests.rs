use alera_core::runtime::{AutomationActor, AutomationDefinition, AutomationState};
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn automation_list_request(&self, payload: &Value) -> HostResult<Value> {
        let include_trashed = payload
            .get("includeTrashed")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let candidates = self
            .runtime_store
            .list_automations(include_trashed)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let state = payload.get("state").and_then(Value::as_str);
        let project_id = payload.get("projectId").and_then(Value::as_str);
        let profile_id = payload.get("profileId").and_then(Value::as_str);
        let tag = payload.get("tag").and_then(Value::as_str);
        let search = payload
            .get("search")
            .and_then(Value::as_str)
            .map(|value| value.trim().to_ascii_lowercase());
        let mut items = Vec::new();
        for mut definition in candidates {
            if state.is_some_and(|value| value != definition.state.as_str()) {
                continue;
            }
            let definition_project_id = self.automation_definition_project(&definition).await?;
            if project_id.is_some_and(|value| definition_project_id.as_deref() != Some(value)) {
                continue;
            }
            if tag.is_some_and(|value| !definition.tag_ids.iter().any(|tag_id| tag_id == value)) {
                continue;
            }
            let target_profile = self.target_profile_id(&definition).await.ok().flatten();
            if profile_id.is_some_and(|value| target_profile.as_deref() != Some(value)) {
                continue;
            }
            if search.as_deref().is_some_and(|value| {
                !definition.name.to_ascii_lowercase().contains(value)
                    && !definition.slug.to_ascii_lowercase().contains(value)
                    && !definition.description.to_ascii_lowercase().contains(value)
            }) {
                continue;
            }
            // Existing-tab and fresh-tab definitions may intentionally omit a
            // project id because the target workspace is the source of truth.
            // Surface that effective project in list items so desktop/mobile
            // filters can offer and apply the same value the server used.
            if definition.project_id.is_none() {
                definition.project_id = definition_project_id.clone();
            }
            let item = self.automation_catalog_item(&definition).await?;
            if payload["workspaceId"]
                .as_str()
                .is_some_and(|id| item["association"]["workspaceId"].as_str() != Some(id))
                || payload["sectionId"]
                    .as_str()
                    .is_some_and(|id| item["association"]["sectionId"].as_str() != Some(id))
                || payload["hostId"]
                    .as_str()
                    .is_some_and(|id| item["targetHostId"].as_str() != Some(id))
            {
                continue;
            }
            if let Some(bucket) = payload["bucket"].as_str() {
                let matches = match bucket {
                    "all" => true,
                    "completed" => definition.state == AutomationState::Archived,
                    "needsAttention" => {
                        definition.state == AutomationState::Blocked
                            || item["readiness"]["ready"] == false
                            || !item["attention"].is_null()
                    }
                    _ => definition.state.as_str() == bucket,
                };
                if !matches {
                    continue;
                }
            }
            items.push(item);
        }
        Ok(json!({
            "kind": "automations",
            "items": items,
            "effectivePolicies": [],
            "filters": {
                "state": payload.get("state"),
                "projectId": payload.get("projectId"),
                "profileId": payload.get("profileId"),
                "tag": payload.get("tag"),
                "search": payload.get("search"),
            },
        }))
    }

    pub(super) async fn automation_show_request(&self, payload: &Value) -> HostResult<Value> {
        let id = require_string_key(payload, "id")?;
        let automation = self
            .runtime_store
            .find_automation(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation not found: {id}")))?;
        let runs = self
            .runtime_store
            .list_automation_runs(Some(&id), 100)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let audit = self
            .runtime_store
            .list_automation_audit_events(Some(&id), 100)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let preview =
            alera_core::runtime::preview_occurrences(&id, &automation.schedule, Utc::now(), 6)
                .unwrap_or_default();
        Ok(json!({
            "automation": self.automation_catalog_item(&automation).await?,
            "runs": runs,
            "audit": audit,
            "occurrences": preview,
            "effectivePolicies": [],
        }))
    }

    pub(super) async fn automation_upsert_request(
        &mut self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let actor = self.resolve_policy_actor(client_id, payload, actor).await?;
        let value = payload.get("automation").unwrap_or(payload);
        let definition: AutomationDefinition = serde_json::from_value(value.clone())
            .map_err(|error| HostError::format(format!("invalid automation: {error}")))?;
        let editing_active = self
            .runtime_store
            .find_automation(&definition.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .is_some_and(|existing| existing.state == AutomationState::Active);
        if definition.state == AutomationState::Active || editing_active {
            let readiness = self.automation_readiness(&definition, true).await;
            if readiness["ready"] != true {
                return Err(HostError::conflict(
                    "automationNotReady",
                    "Fix the highlighted fields before activating",
                    readiness,
                ));
            }
        }
        let saved = self
            .runtime_store
            .upsert_automation(definition, actor)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automations_active = self
            .runtime_store
            .has_pending_automation_work()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automation_wake.notify_one();
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationsChanged",
            json!({}),
        ));
        serde_json::to_value(saved).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_state_request(
        &mut self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
        state: AutomationState,
    ) -> HostResult<Value> {
        let actor = self.resolve_policy_actor(client_id, payload, actor).await?;
        let id = require_string_key(payload, "id")?;
        let reason = payload.get("reason").and_then(Value::as_str);
        let definition = self
            .runtime_store
            .find_automation(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation not found: {id}")))?;
        if state == AutomationState::Active {
            let readiness = self.automation_readiness(&definition, true).await;
            if readiness["ready"] != true {
                return Err(HostError::conflict(
                    "automationNotReady",
                    "Fix the highlighted fields before activating",
                    readiness,
                ));
            }
        }
        if state == AutomationState::Paused {
            let active_runs = self
                .runtime_store
                .list_active_automation_runs()
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .into_iter()
                .filter(|run| run.automation_id == id)
                .collect::<Vec<_>>();
            if !active_runs.is_empty() {
                let choice = payload
                    .get("activeRuns")
                    .and_then(Value::as_str)
                    .ok_or_else(|| {
                        HostError::format(
                            "pausing an automation with active runs requires activeRuns=continue-active or cancel-active",
                        )
                    })?;
                match choice {
                    "continue-active" => {}
                    "cancel-active" => {
                        let bound_run_id = payload.get("run").and_then(Value::as_str);
                        if actor.kind == alera_core::runtime::AutomationActorKind::ManagedAgent
                            && active_runs
                                .iter()
                                .any(|run| Some(run.id.as_str()) != bound_run_id)
                        {
                            return Err(HostError::state(
                                "managed agents can cancel only their bound automation run",
                            ));
                        }
                        for run in active_runs {
                            self.runtime_store
                                .request_automation_cancel(&run.id, actor.clone())
                                .await
                                .map_err(|error| HostError::state(error.to_string()))?;
                        }
                    }
                    _ => {
                        return Err(HostError::format(
                            "activeRuns must be continue-active or cancel-active",
                        ));
                    }
                }
            }
        }
        let saved = self
            .runtime_store
            .set_automation_state(&id, state, actor, reason)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automations_active = self
            .runtime_store
            .has_pending_automation_work()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automation_wake.notify_one();
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationsChanged",
            json!({}),
        ));
        serde_json::to_value(saved).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_approve_request(
        &mut self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let mut response = self
            .automation_state_request(client_id, payload, actor, AutomationState::Active)
            .await?;
        response["deprecation"] =
            json!("approve is deprecated; use resume. No approval is required.");
        Ok(response)
    }

    pub(super) async fn automation_runs_request(&self, payload: &Value) -> HostResult<Value> {
        let automation_id = payload.get("automationId").and_then(Value::as_str);
        let limit = payload.get("limit").and_then(Value::as_i64).unwrap_or(100);
        let runs = self
            .runtime_store
            .list_automation_runs(automation_id, limit)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(json!({ "kind": "automationRuns", "items": runs }))
    }

    pub(super) async fn automation_run_show_request(&self, payload: &Value) -> HostResult<Value> {
        let id = require_string_key(payload, "id")?;
        let run = self
            .runtime_store
            .find_automation_run(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation run not found: {id}")))?;
        let automation = self
            .runtime_store
            .find_automation(&run.automation_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let attempts = self
            .runtime_store
            .automation_attempts(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(json!({ "run": run, "automation": automation, "attempts": attempts }))
    }
}
