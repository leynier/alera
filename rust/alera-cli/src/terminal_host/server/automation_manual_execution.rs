use alera_core::runtime::{
    AutomationActor, AutomationOccurrence, AutomationRunStatus, AutomationRunTrigger,
    AutomationState,
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
        let actor = self.resolve_policy_actor(client_id, payload, actor).await?;
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
        let readiness = self.automation_readiness(&definition, false).await;
        if readiness["ready"] != true {
            return Err(HostError::conflict(
                "automationNotReady",
                "Fix the highlighted fields before running",
                readiness,
            ));
        }
        self.ensure_dispatch_policy(&definition, &actor).await?;
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
        run.continue_from_run_id = previous.as_ref().map(|r| r.id.clone());
        match self.target_identity(&definition.target).await {
            Ok(identity) => run.target_identity = Some(identity),
            Err(reason) => {
                self.block_run(&run, &reason).await;
                return serde_json::to_value(
                    self.runtime_store
                        .find_automation_run(&run.id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                        .unwrap_or(run),
                )
                .map_err(|error| HostError::state(error.to_string()));
            }
        }
        run.overlap_policy = Some(chosen_overlap);
        run.precheck = Some(precheck);
        run = self
            .runtime_store
            .save_automation_run(&run)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let active_runs = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .into_iter()
            .filter(|active| active.automation_id == definition.id && active.id != run.id)
            .collect::<Vec<_>>();
        if !active_runs.is_empty() {
            match chosen_overlap {
                alera_core::runtime::AutomationOverlapPolicy::Skip => {
                    let run = self
                        .runtime_store
                        .update_automation_run_status(
                            &run.id,
                            AutomationRunStatus::OverlapSkipped,
                            Some("manual overlap decision skipped the run".to_string()),
                        )
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    return serde_json::to_value(run)
                        .map_err(|error| HostError::state(error.to_string()));
                }
                alera_core::runtime::AutomationOverlapPolicy::Queue => {
                    let pending = active_runs
                        .iter()
                        .filter(|active| active.status == AutomationRunStatus::Pending)
                        .count();
                    if pending >= definition.queue_cap.clamp(1, 10) as usize {
                        let run = self
                            .runtime_store
                            .update_automation_run_status(
                                &run.id,
                                AutomationRunStatus::QueueLimitSkipped,
                                Some("manual queue cap reached".to_string()),
                            )
                            .await
                            .map_err(|error| HostError::state(error.to_string()))?;
                        return serde_json::to_value(run)
                            .map_err(|error| HostError::state(error.to_string()));
                    }
                    let run = self
                        .runtime_store
                        .find_automation_run(&run.id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                        .unwrap_or(run);
                    self.runtime_store
                        .insert_automation_audit_event(
                            Some(&definition.id),
                            Some(&run.id),
                            "runNowQueued",
                            actor.clone(),
                            Some(definition.revision),
                            json!({ "overlap": chosen_overlap.as_str() }),
                        )
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    return serde_json::to_value(run)
                        .map_err(|error| HostError::state(error.to_string()));
                }
                alera_core::runtime::AutomationOverlapPolicy::RunLatestOnce => {
                    for active in active_runs
                        .iter()
                        .filter(|active| active.status == AutomationRunStatus::Pending)
                    {
                        let _ = self
                            .runtime_store
                            .update_automation_run_status(
                                &active.id,
                                AutomationRunStatus::OverlapSkipped,
                                Some("a newer manual run replaced this queued run".to_string()),
                            )
                            .await;
                    }
                    let run = self
                        .runtime_store
                        .find_automation_run(&run.id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                        .unwrap_or(run);
                    self.runtime_store
                        .insert_automation_audit_event(
                            Some(&definition.id),
                            Some(&run.id),
                            "runNowQueued",
                            actor.clone(),
                            Some(definition.revision),
                            json!({ "overlap": chosen_overlap.as_str() }),
                        )
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    return serde_json::to_value(run)
                        .map_err(|error| HostError::state(error.to_string()));
                }
                alera_core::runtime::AutomationOverlapPolicy::ForceParallel => {}
            }
        }
        self.start_automation_run(&definition, run.clone(), precheck)
            .await;
        self.runtime_store
            .insert_automation_audit_event(
                Some(&definition.id),
                Some(&run.id),
                "runNow",
                actor,
                Some(definition.revision),
                json!({
                    "precheck": precheck,
                    "overlap": chosen_overlap.as_str(),
                    "draftTest": definition.state == AutomationState::Draft,
                    "definitionRevision": definition.revision,
                }),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
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
