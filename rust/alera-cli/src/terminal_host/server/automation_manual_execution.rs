use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationOccurrence, AutomationRunStatus,
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
        let actor = self.resolve_policy_actor(client_id, payload, actor).await?;
        let id = optional_string_key(payload, "id")
            .ok_or_else(|| HostError::format("automation id is required"))?;
        let definition = self
            .runtime_store
            .find_automation(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation not found: {id}")))?;
        let draft_test = payload
            .get("draftTest")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let exact_revision = payload.get("revision").and_then(Value::as_i64);
        if let Some(revision) = exact_revision {
            if revision != definition.revision {
                return Err(HostError::state(
                    "automation exact revision is stale; refresh before running",
                ));
            }
        }
        let human_actor = matches!(
            actor.kind,
            AutomationActorKind::HumanDesktop
                | AutomationActorKind::AuthenticatedMobile
                | AutomationActorKind::LocalCli
        );
        let exact_revision_approval =
            exact_revision.is_some_and(|revision| revision == definition.revision && human_actor);
        if !(exact_revision_approval
            || (definition.state == AutomationState::Active && definition.is_approved())
            || (draft_test && human_actor))
        {
            return Err(HostError::state(
                "automation must be active and approved, or run as an audited human draft test",
            ));
        }
        self.ensure_agent_policy(&definition, &actor, true).await?;
        let precheck = payload
            .get("precheck")
            .and_then(Value::as_bool)
            .ok_or_else(|| HostError::format("run now requires an explicit precheck decision"))?;
        let chosen_overlap = payload
            .get("overlap")
            .or_else(|| payload.get("overlapPolicy"))
            .and_then(Value::as_str)
            .map(parse_manual_overlap)
            .transpose()?;
        let Some(chosen_overlap) = chosen_overlap else {
            return Err(HostError::format(
                "run now requires an explicit overlap decision",
            ));
        };
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
        match self.target_identity(&definition).await {
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
                    "draftTest": draft_test,
                    "exactRevisionApproval": exact_revision_approval,
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
