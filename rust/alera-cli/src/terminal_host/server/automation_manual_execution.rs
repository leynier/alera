use alera_core::runtime::{
    AutomationActor, AutomationOccurrence, AutomationOverlapDecision, AutomationRun,
    AutomationRunTrigger, AutomationState,
};
use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::requests::optional_string_key;
use super::ServerActor;

impl ServerActor {
    pub(in crate::terminal_host::server) async fn run_automation_now(
        &mut self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let actor = self
            .resolve_request_actor(client_id, payload, actor)
            .await?;
        let id = optional_string_key(payload, "id")
            .ok_or_else(|| HostError::format("automation id is required"))?;
        let mut definition = self
            .runtime_store
            .find_automation(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation not found: {id}")))?;
        if definition.state == AutomationState::Trashed {
            return Err(HostError::state(
                "Restore this automation before running it",
            ));
        }
        if payload
            .get("revision")
            .and_then(Value::as_i64)
            .is_some_and(|revision| revision != definition.revision)
        {
            return Err(HostError::state(
                "automation revision is stale; refresh before running",
            ));
        }
        let previous = if let Some(id) = payload["continueFromRunId"].as_str() {
            let previous = self
                .runtime_store
                .find_automation_run(id)
                .await
                .map_err(|e| HostError::state(e.to_string()))?
                .ok_or_else(|| HostError::state("Previous run not found"))?;
            if previous.automation_id != definition.id || !previous.status.is_final() {
                return Err(HostError::state(
                    "Run Again requires a finished run of this automation",
                ));
            }
            // A reusing automation returns to its bound target on its own,
            // and the reuse preface already describes the previous run.
            if definition.reuse_policy.reuses() {
                return self
                    .start_manual_run(client_id, payload, actor, definition, Some(previous))
                    .await;
            }
            let workspace = previous.workspace_id.as_deref().ok_or_else(|| {
                HostError::state("Previous workspace is missing; choose Start Fresh")
            })?;
            let profile = previous
                .target_identity
                .as_ref()
                .and_then(|i| i.profile_id.clone())
                .or_else(|| definition.target.agent_profile_id().map(str::to_string))
                .ok_or_else(|| {
                    HostError::state("Previous profile is missing; choose Start Fresh")
                })?;
            definition.target = alera_core::runtime::AutomationTarget::FreshTab {
                workspace_id: workspace.into(),
                agent_profile_id: profile,
            };
            let summary = previous
                .summary
                .as_deref()
                .unwrap_or("No summary recorded")
                .replace("{{", "{ {")
                .replace("}}", "} }");
            let error = previous
                .error
                .as_deref()
                .unwrap_or("None")
                .replace("{{", "{ {")
                .replace("}}", "} }");
            definition.prompt_template = format!("{}\n\nPrevious run {} summary: {summary}. Previous error: {error}. Inspect the preserved changes in this workspace before repeating actions.",definition.prompt_template,previous.id);
            Some(previous)
        } else {
            None
        };
        self.start_manual_run(client_id, payload, actor, definition, previous)
            .await
    }

    async fn start_manual_run(
        &mut self,
        _client_id: u64,
        payload: &Value,
        actor: AutomationActor,
        definition: alera_core::runtime::AutomationDefinition,
        previous: Option<AutomationRun>,
    ) -> HostResult<Value> {
        let readiness = self.automation_readiness(&definition, false).await;
        if readiness["ready"] != true {
            return Err(HostError::conflict(
                "automationNotReady",
                "Fix the highlighted fields before running",
                readiness,
            ));
        }
        self.ensure_target_valid(&definition).await?;
        let precheck = payload
            .get("precheck")
            .and_then(Value::as_bool)
            .unwrap_or(definition.precheck.is_some());
        let chosen_overlap = payload
            .get("overlap")
            .or_else(|| payload.get("overlapPolicy"))
            .and_then(Value::as_str)
            .map(parse_manual_overlap)
            .transpose()?;
        let chosen_overlap = chosen_overlap.unwrap_or(definition.overlap_policy);
        let occurrence = AutomationOccurrence {
            automation_id: definition.id.clone(),
            key: format!("manual|{}", Uuid::new_v4()),
            scheduled_at: Utc::now(),
            local_time: Utc::now().to_rfc3339(),
        };
        let mut run = self
            .runtime_store
            .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Manual)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_automation_run_changed(&run);
        run.continue_from_run_id = previous.as_ref().map(|r| r.id.clone());
        match self
            .target_identity(&definition.target, definition.reuse_policy)
            .await
        {
            Ok(identity) => run.target_identity = Some(identity),
            Err(reason) => {
                self.block_run(&run, &reason).await;
                return self.manual_run_value(run).await;
            }
        }
        run.overlap_policy = Some(chosen_overlap);
        run.precheck = Some(precheck);
        run = self
            .runtime_store
            .save_automation_run(&run)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let decision = self
            .start_automation_run(&definition, run.clone(), precheck)
            .await;
        let audit = match decision {
            AutomationOverlapDecision::Proceed => Some((
                "runNow",
                json!({
                    "precheck": precheck,
                    "overlap": chosen_overlap.as_str(),
                    "draftTest": definition.state == AutomationState::Draft,
                    "definitionRevision": definition.revision,
                }),
            )),
            AutomationOverlapDecision::Wait => Some((
                "runNowQueued",
                json!({ "overlap": chosen_overlap.as_str() }),
            )),
            AutomationOverlapDecision::Skip(_) | AutomationOverlapDecision::QueueLimit => None,
        };
        if let Some((kind, details)) = audit {
            self.runtime_store
                .insert_automation_audit_event(
                    Some(&definition.id),
                    Some(&run.id),
                    kind,
                    actor,
                    Some(definition.revision),
                    details,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
        }
        self.manual_run_value(run).await
    }

    async fn manual_run_value(&self, run: AutomationRun) -> HostResult<Value> {
        serde_json::to_value(
            self.runtime_store
                .find_automation_run(&run.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .unwrap_or(run),
        )
        .map_err(|error| HostError::state(error.to_string()))
    }
}

fn parse_manual_overlap(
    value: &str,
) -> Result<alera_core::runtime::AutomationOverlapPolicy, HostError> {
    match value {
        "skip" => Ok(alera_core::runtime::AutomationOverlapPolicy::Skip),
        "queue" => Ok(alera_core::runtime::AutomationOverlapPolicy::Queue),
        "runLatestOnce" => Ok(alera_core::runtime::AutomationOverlapPolicy::RunLatestOnce),
        "forceParallel" => Ok(alera_core::runtime::AutomationOverlapPolicy::ForceParallel),
        _ => Err(HostError::format(
            "overlap must be skip, queue, runLatestOnce, or forceParallel",
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::parse_manual_overlap;
    use alera_core::runtime::AutomationOverlapPolicy;

    #[test]
    fn manual_overlap_parser_accepts_every_contract_choice() {
        assert_eq!(
            parse_manual_overlap("skip").unwrap(),
            AutomationOverlapPolicy::Skip
        );
        assert_eq!(
            parse_manual_overlap("queue").unwrap(),
            AutomationOverlapPolicy::Queue
        );
        assert_eq!(
            parse_manual_overlap("runLatestOnce").unwrap(),
            AutomationOverlapPolicy::RunLatestOnce
        );
        assert_eq!(
            parse_manual_overlap("forceParallel").unwrap(),
            AutomationOverlapPolicy::ForceParallel
        );
        assert!(parse_manual_overlap("unknown").is_err());
    }
}
