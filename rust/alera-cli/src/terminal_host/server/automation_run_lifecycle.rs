use alera_core::runtime::{
    AutomationDefinition, AutomationRun, AutomationRunStatus, AutomationState, AutomationTarget,
    AutomationTargetIdentity,
};
use chrono::{Duration, Utc};
use serde_json::{json, Value};

use super::super::requests::terminal_session_id_from_tab;
use super::{managed_actor, ServerActor};
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) async fn target_identity(
        &self,
        definition: &AutomationDefinition,
    ) -> Result<AutomationTargetIdentity, String> {
        match &definition.target {
            AutomationTarget::ExistingTab {
                workspace_id,
                tab_id,
                conversation_id,
            } => {
                let Some(conversation_id) = conversation_id else {
                    return Err("automation conversation continuity cannot be proven".to_string());
                };
                let tab = self
                    .runtime_store
                    .find_workspace_tab(tab_id)
                    .await
                    .map_err(|error| error.to_string())?
                    .ok_or_else(|| "automation existing tab is missing".to_string())?;
                if tab.workspace_id != *workspace_id {
                    return Err("automation existing tab workspace changed".to_string());
                }
                let session_id = terminal_session_id_from_tab(&tab).ok_or_else(|| {
                    "automation existing tab has no terminal identity".to_string()
                })?;
                Ok(AutomationTargetIdentity {
                    workspace_id: Some(workspace_id.clone()),
                    tab_id: Some(tab_id.clone()),
                    session_id: Some(session_id.clone()),
                    profile_id: tab
                        .payload
                        .get("agentProfileId")
                        .and_then(Value::as_str)
                        .map(str::to_string),
                    conversation_id: Some(conversation_id.clone()),
                    terminal_handle: Some(session_id),
                })
            }
            AutomationTarget::FreshTab {
                workspace_id,
                agent_profile_id,
            } => Ok(AutomationTargetIdentity {
                workspace_id: Some(workspace_id.clone()),
                tab_id: None,
                session_id: None,
                profile_id: Some(agent_profile_id.clone()),
                conversation_id: None,
                terminal_handle: None,
            }),
            AutomationTarget::ManagedWorkspace {
                source_workspace_id,
                agent_profile_id,
                ..
            } => Ok(AutomationTargetIdentity {
                workspace_id: Some(source_workspace_id.clone()),
                tab_id: None,
                session_id: None,
                profile_id: Some(agent_profile_id.clone()),
                conversation_id: None,
                terminal_handle: None,
            }),
        }
    }

    pub(super) async fn dispatch_existing_tab(
        &mut self,
        run: &mut AutomationRun,
        workspace_id: &str,
        tab_id: &str,
        conversation_id: Option<&str>,
        prompt: &str,
    ) -> HostResult<()> {
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("automation existing tab is missing"))?;
        if tab.workspace_id != workspace_id {
            return Err(HostError::state(
                "automation existing tab workspace changed",
            ));
        }
        let session_id = terminal_session_id_from_tab(&tab)
            .ok_or_else(|| HostError::state("automation existing tab has no terminal identity"))?;
        let Some(expected) = conversation_id else {
            return Err(HostError::state(
                "automation conversation continuity cannot be proven",
            ));
        };
        {
            let actual = tab.payload.get("conversationId").and_then(Value::as_str);
            if actual != Some(expected) {
                return Err(HostError::state("automation conversation identity changed"));
            }
        }
        if !self.sessions.contains_key(&session_id) {
            return Err(HostError::state(
                "automation existing tab has no live PTY after restart",
            ));
        }
        if !self.agent_presence.is_injection_ready(&session_id) {
            run.status = AutomationRunStatus::Pending;
            run.retry_after = Some(Utc::now() + Duration::seconds(5));
            run.started_at = None;
            run.updated_at = Utc::now();
            self.runtime_store
                .save_automation_run(run)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            return Ok(());
        }
        self.queue_orchestration_paste(&session_id, prompt, Vec::new(), true)?;
        run.workspace_id = Some(workspace_id.to_string());
        run.tab_id = Some(tab_id.to_string());
        run.session_id = Some(session_id);
        Ok(())
    }

    pub(super) async fn block_run(&mut self, run: &AutomationRun, reason: &str) {
        let _ = self
            .runtime_store
            .update_automation_run_status(
                &run.id,
                AutomationRunStatus::Blocked,
                Some(reason.to_string()),
            )
            .await;
        let _ = self
            .runtime_store
            .set_automation_state(
                &run.automation_id,
                AutomationState::Blocked,
                managed_actor(),
                Some(reason),
            )
            .await;
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationAttentionRequired",
            json!({ "automationId": run.automation_id, "runId": run.id, "reason": reason }),
        ));
        if let Ok(Some(definition)) = self.runtime_store.find_automation(&run.automation_id).await {
            self.queue_automation_push(
                run,
                &definition,
                AutomationRunStatus::Blocked,
                Some(reason),
            )
            .await;
        }
    }

    pub(super) async fn fail_run(&mut self, run: &AutomationRun, reason: String) {
        if run.trigger == alera_core::runtime::AutomationRunTrigger::Scheduled {
            if let Ok(Some(definition)) =
                self.runtime_store.find_automation(&run.automation_id).await
            {
                if run.attempt_count < definition.retry_max_attempts {
                    let multiplier = 1_i64 << run.attempt_count.saturating_sub(1).min(5);
                    let retry_after = Utc::now()
                        + Duration::seconds(
                            definition.retry_backoff_seconds.saturating_mul(multiplier),
                        );
                    if self
                        .runtime_store
                        .schedule_automation_retry(
                            &run.id,
                            retry_after,
                            reason.clone(),
                            managed_actor(),
                        )
                        .await
                        .is_ok()
                    {
                        self.broadcast_authenticated(crate::terminal_host::protocol::event(
                            "automationRunChanged",
                            json!({ "automationId": run.automation_id, "runId": run.id, "retryAt": retry_after }),
                        ));
                        return;
                    }
                }
            }
        }
        let _ = self
            .runtime_store
            .update_automation_run_status(
                &run.id,
                AutomationRunStatus::Failure,
                Some(reason.clone()),
            )
            .await;
        if run.trigger == alera_core::runtime::AutomationRunTrigger::Scheduled {
            if let Ok(Some(definition)) =
                self.runtime_store.find_automation(&run.automation_id).await
            {
                if self
                    .runtime_store
                    .count_automation_failure_streak(&run.automation_id)
                    .await
                    .unwrap_or_default()
                    >= definition.circuit_failure_threshold
                {
                    let _ = self
                        .runtime_store
                        .set_automation_circuit_opened(
                            &run.automation_id,
                            true,
                            managed_actor(),
                            Some("automation circuit breaker opened"),
                        )
                        .await;
                    let _ = self
                        .runtime_store
                        .set_automation_state(
                            &run.automation_id,
                            AutomationState::Blocked,
                            managed_actor(),
                            Some("automation circuit breaker opened"),
                        )
                        .await;
                }
            }
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationAttentionRequired",
            json!({ "automationId": run.automation_id, "runId": run.id, "reason": reason }),
        ));
        if let Ok(Some(definition)) = self.runtime_store.find_automation(&run.automation_id).await {
            self.queue_automation_push(
                run,
                &definition,
                AutomationRunStatus::Failure,
                Some(&reason),
            )
            .await;
        }
    }

    pub(super) async fn expire_inactive_automation_runs(&mut self) {
        let now = Utc::now();
        let runs = match self.runtime_store.list_active_automation_runs().await {
            Ok(runs) => runs,
            Err(_) => return,
        };
        for run in runs {
            if run.cancel_requested_at.is_some() && run.started_at.is_none() {
                let _ = self
                    .runtime_store
                    .update_automation_run_status(
                        &run.id,
                        AutomationRunStatus::Cancelled,
                        Some("automation cancellation requested before dispatch".to_string()),
                    )
                    .await;
                continue;
            }
            let Some(started) = run.started_at else {
                continue;
            };
            let Ok(Some(definition)) = self.runtime_store.find_automation(&run.automation_id).await
            else {
                continue;
            };
            let reference = run.last_heartbeat_at.unwrap_or(started);
            let absolute_deadline = run
                .absolute_deadline_at
                .or_else(|| Some(started + Duration::hours(24)));
            let absolute_expired = absolute_deadline.is_some_and(|deadline| now >= deadline);
            let inactivity_expired = run.status != AutomationRunStatus::WaitingForUser
                && now.signed_duration_since(reference).num_seconds()
                    > definition.inactivity_timeout_seconds;
            let cancellation_expired = run
                .cancel_requested_at
                .is_some_and(|requested| now.signed_duration_since(requested).num_seconds() >= 30);
            if absolute_expired || inactivity_expired || cancellation_expired {
                let status = if cancellation_expired {
                    AutomationRunStatus::Cancelled
                } else {
                    AutomationRunStatus::Timeout
                };
                if cancellation_expired && run.owned_tab && !run.taken_over {
                    if let Some(tab_id) = &run.tab_id {
                        self.terminate_sessions_for_tab(tab_id).await;
                    }
                    if let Some(tab_id) = &run.setup_tab_id {
                        self.terminate_sessions_for_tab(tab_id).await;
                    }
                }
                let _ = self
                    .runtime_store
                    .update_automation_run_status(
                        &run.id,
                        status,
                        Some(if cancellation_expired {
                            "automation cancellation grace elapsed".to_string()
                        } else if absolute_expired {
                            "automation absolute 24-hour maximum exceeded".to_string()
                        } else {
                            "automation inactivity timeout exceeded".to_string()
                        }),
                    )
                    .await;
                self.broadcast_authenticated(crate::terminal_host::protocol::event(
                    "automationAttentionRequired",
                    json!({ "automationId": run.automation_id, "runId": run.id, "reason": "timeout" }),
                ));
                self.queue_automation_push(
                    &run,
                    &definition,
                    status,
                    Some(if cancellation_expired {
                        "automation cancellation grace elapsed"
                    } else if absolute_expired {
                        "automation absolute 24-hour maximum exceeded"
                    } else {
                        "automation inactivity timeout exceeded"
                    }),
                )
                .await;
                if status == AutomationRunStatus::Timeout
                    && run.trigger == alera_core::runtime::AutomationRunTrigger::Scheduled
                    && self
                        .runtime_store
                        .count_automation_failure_streak(&run.automation_id)
                        .await
                        .unwrap_or_default()
                        >= definition.circuit_failure_threshold
                {
                    let _ = self
                        .runtime_store
                        .set_automation_circuit_opened(
                            &run.automation_id,
                            true,
                            managed_actor(),
                            Some("automation circuit breaker opened after timeout"),
                        )
                        .await;
                    let _ = self
                        .runtime_store
                        .set_automation_state(
                            &run.automation_id,
                            AutomationState::Blocked,
                            managed_actor(),
                            Some("automation circuit breaker opened"),
                        )
                        .await;
                }
            }
        }
    }
}

pub(super) fn is_non_retryable_dispatch_error(error: &HostError) -> bool {
    is_non_retryable_reason(&error.wire_message())
}

pub(super) fn is_non_retryable_reason(reason: &str) -> bool {
    let message = reason.to_ascii_lowercase();
    message.starts_with("automation existing tab ")
        || message.contains("conversation continuity")
        || message.contains("conversation identity")
        || message.contains("interactive authentication")
        || message.contains("authentication required")
        || message.contains("login required")
        || message.contains("ssh authentication")
        || message.contains("ssh target is missing")
}

#[cfg(test)]
mod tests {
    use super::is_non_retryable_reason;

    #[test]
    fn continuity_and_authentication_failures_are_not_retryable() {
        for reason in [
            "automation existing tab is missing",
            "automation conversation continuity cannot be proven",
            "remote interactive authentication required",
            "SSH target is missing: remote",
        ] {
            assert!(is_non_retryable_reason(reason), "{reason}");
        }
        assert!(!is_non_retryable_reason("agent process exited with code 1"));
    }
}
