use alera_core::runtime::{
    AutomationReusePolicy, AutomationRun, AutomationRunStatus, AutomationRunTrigger,
    AutomationState, AutomationTarget, AutomationTargetIdentity,
};
use chrono::{Duration, Utc};
use serde_json::json;
use std::future::Future;
use std::pin::Pin;

use super::super::requests::terminal_session_id_from_tab;
use super::super::terminal_startup_commands::agent_profile_id;
use super::{managed_actor, ServerActor};
use crate::terminal_host::host_error::HostError;

impl ServerActor {
    pub(in crate::terminal_host::server) async fn target_identity(
        &self,
        target: &AutomationTarget,
        reuse_policy: AutomationReusePolicy,
    ) -> Result<AutomationTargetIdentity, String> {
        let workspace_id = target.source_workspace_id();
        // Fence prechecks and managed source reads as well as eventual PTY
        // creation. Cleanup checks live owners after publishing this claim.
        if let Some(workspace_id) = workspace_id {
            self.runtime_store
                .require_workspace_outside_cleanup(workspace_id)
                .await
                .map_err(|error| error.to_string())?;
        }
        match target {
            AutomationTarget::ProjectCheckout {
                agent_profile_id, ..
            } => Ok(AutomationTargetIdentity {
                workspace_id: None,
                tab_id: None,
                session_id: None,
                profile_id: Some(agent_profile_id.clone()),
                conversation_id: None,
                terminal_handle: None,
            }),
            AutomationTarget::ExistingTab {
                workspace_id,
                tab_id,
                conversation_id,
            } if reuse_policy == AutomationReusePolicy::ReuseConversation => {
                // The resolver may move a reusing run to another tab of the
                // workspace, so a missing tab or conversation is not an error.
                let tab = self
                    .runtime_store
                    .find_workspace_tab(tab_id)
                    .await
                    .ok()
                    .flatten()
                    .filter(|tab| tab.workspace_id == *workspace_id);
                let session_id = tab.as_ref().and_then(terminal_session_id_from_tab);
                Ok(AutomationTargetIdentity {
                    workspace_id: Some(workspace_id.clone()),
                    tab_id: Some(tab_id.clone()),
                    session_id: session_id.clone(),
                    profile_id: tab.as_ref().and_then(agent_profile_id).map(str::to_string),
                    conversation_id: conversation_id.clone(),
                    terminal_handle: session_id,
                })
            }
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
                    profile_id: agent_profile_id(&tab).map(str::to_string),
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
            AutomationTarget::Worktree {
                agent_profile_id, ..
            } => Ok(AutomationTargetIdentity {
                workspace_id: workspace_id.map(str::to_string),
                tab_id: None,
                session_id: None,
                profile_id: Some(agent_profile_id.clone()),
                conversation_id: None,
                terminal_handle: None,
            }),
        }
    }

    // `block_run` and `fail_run` are awaited from most dispatch steps.
    // Returning the future boxed keeps it out of each caller's poll frame,
    // which an unoptimized build would otherwise grow once per call site.
    pub(in crate::terminal_host::server) fn block_run<'a>(
        &'a mut self,
        run: &'a AutomationRun,
        reason: &'a str,
    ) -> Pin<Box<impl Future<Output = ()> + 'a>> {
        Box::pin(self.block_run_inner(run, reason))
    }

    pub(in crate::terminal_host::server) fn fail_run<'a>(
        &'a mut self,
        run: &'a AutomationRun,
        reason: String,
    ) -> Pin<Box<impl Future<Output = ()> + 'a>> {
        Box::pin(self.fail_run_inner(run, reason))
    }

    async fn block_run_inner(&mut self, run: &AutomationRun, reason: &str) {
        let _ = self
            .set_automation_run_status(
                &run.id,
                AutomationRunStatus::Blocked,
                Some(reason.to_string()),
            )
            .await;
        // Only the scheduler re-fires on its own; a blocked manual run must not pause it.
        if run.trigger == AutomationRunTrigger::Scheduled {
            self.block_automation_definition_if_active(
                &run.automation_id,
                managed_actor(),
                Some(reason),
            )
            .await;
        }
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

    async fn fail_run_inner(&mut self, run: &AutomationRun, reason: String) {
        let mut recovering = self
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .ok()
            .flatten()
            .unwrap_or_else(|| run.clone());
        if recovering.status.is_final() || recovering.taken_over {
            return;
        }
        if recovering.attempt_count > 0
            && (recovering.tab_id.is_some() || recovering.session_id.is_some())
            && recovering.recovery.is_none()
        {
            recovering.recovery = Some(alera_core::runtime::AutomationRecovery {
                status: "retryingWithContext".into(),
                attempt: recovering.attempt_count,
                max_attempts: recovering
                    .definition_snapshot
                    .as_ref()
                    .map_or(3, |d| d.retry_max_attempts),
                interrupted_at: Some(Utc::now()),
                code: Some("launchInterrupted".into()),
            });
            let _ = self.runtime_store.save_automation_run(&recovering).await;
        }
        let run = &recovering;
        if !run.taken_over && !run.status.is_final() {
            if let Some(definition) = run.definition_snapshot.clone().or(self
                .runtime_store
                .find_automation(&run.automation_id)
                .await
                .ok()
                .flatten())
            {
                if run.attempt_count < definition.retry_max_attempts
                    && run.absolute_deadline_at.is_none_or(|at| at > Utc::now())
                {
                    let multiplier = 1_i64 << run.attempt_count.saturating_sub(1).min(5);
                    let retry_after = Utc::now()
                        + Duration::seconds(
                            definition.retry_backoff_seconds.saturating_mul(multiplier),
                        );
                    if let Ok(retrying) = self
                        .runtime_store
                        .schedule_automation_retry(
                            &run.id,
                            retry_after,
                            reason.clone(),
                            managed_actor(),
                        )
                        .await
                    {
                        self.broadcast_automation_run_changed(&retrying);
                        return;
                    }
                }
            }
        }
        let mut exhausted = run.clone();
        if let Some(recovery) = exhausted.recovery.as_mut() {
            recovery.status = "exhausted".into();
        }
        let _ = self.runtime_store.save_automation_run(&exhausted).await;
        let _ = self
            .set_automation_run_status(&run.id, AutomationRunStatus::Failure, Some(reason.clone()))
            .await;
        if run.trigger == alera_core::runtime::AutomationRunTrigger::Scheduled {
            if let Ok(Some(definition)) =
                self.runtime_store.find_automation(&run.automation_id).await
            {
                if self
                    .runtime_store
                    .count_automation_failure_streak(
                        &run.automation_id,
                        definition.circuit_failure_threshold,
                    )
                    .await
                    .unwrap_or_default()
                    >= definition.circuit_failure_threshold
                {
                    self.open_automation_circuit(
                        &run.automation_id,
                        managed_actor(),
                        "automation circuit breaker opened",
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

    pub(in crate::terminal_host::server) async fn expire_inactive_automation_runs(&mut self) {
        let now = Utc::now();
        let runs = match self.runtime_store.list_active_automation_runs().await {
            Ok(runs) => runs,
            Err(_) => return,
        };
        for run in runs {
            // A precheck reserves its run before any dispatch attempt starts.
            // Its completion owns finalization while the command is in flight.
            if self.automation_precheck_jobs.contains(&run.id) {
                continue;
            }
            if self.resume_remote_automation_precheck(&run).await {
                continue;
            }
            if self.retain_unverified_precheck(&run).await {
                continue;
            }
            if run.cancel_requested_at.is_some() && run.started_at.is_none() {
                let _ = self
                    .set_automation_run_status(
                        &run.id,
                        AutomationRunStatus::Cancelled,
                        Some("automation cancellation requested before dispatch".to_string()),
                    )
                    .await;
                continue;
            }
            if self.recover_interrupted_automation_precheck(&run).await {
                continue;
            }
            let Some(started) = run.started_at else {
                continue;
            };
            let Some(definition) = run.definition_snapshot.clone().or(self
                .runtime_store
                .find_automation(&run.automation_id)
                .await
                .ok()
                .flatten())
            else {
                continue;
            };
            let reference = run.inactivity_reference().unwrap_or(started);
            let absolute_deadline = run
                .absolute_deadline_at
                .or_else(|| Some(started + Duration::hours(24)));
            let absolute_expired = absolute_deadline.is_some_and(|deadline| now >= deadline);
            let inactivity_expired = !run.owner_reserved
                && run.status != AutomationRunStatus::Pending
                && run.status != AutomationRunStatus::WaitingForUser
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
                if !run.owner_reserved {
                    let reason = if cancellation_expired {
                        "cancelled"
                    } else {
                        "timedOut"
                    };
                    self.terminate_owned_automation_sessions(&run, reason).await;
                }
                let _ = self
                    .set_automation_run_status(
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
                        .count_automation_failure_streak(
                            &run.automation_id,
                            definition.circuit_failure_threshold,
                        )
                        .await
                        .unwrap_or_default()
                        >= definition.circuit_failure_threshold
                {
                    self.open_automation_circuit(
                        &run.automation_id,
                        managed_actor(),
                        "automation circuit breaker opened after timeout",
                    )
                    .await;
                }
            }
        }
    }

    pub(in crate::terminal_host::server) async fn open_automation_circuit(
        &mut self,
        automation_id: &str,
        actor: alera_core::runtime::AutomationActor,
        reason: &str,
    ) {
        if let Err(error) = self
            .runtime_store
            .open_automation_circuit(automation_id, actor, Some(reason))
            .await
        {
            tracing::warn!(automation_id, "could not open automation circuit: {error}");
            return;
        }
        self.broadcast_automation_changed(Some(automation_id));
        self.automations_active = true;
        self.automation_wake.notify_one();
    }

    pub(in crate::terminal_host::server) async fn block_automation_definition_if_active(
        &mut self,
        automation_id: &str,
        actor: alera_core::runtime::AutomationActor,
        reason: Option<&str>,
    ) {
        let Ok(Some(definition)) = self.runtime_store.find_automation(automation_id).await else {
            return;
        };
        if definition.state != AutomationState::Active {
            return;
        }
        if self
            .runtime_store
            .set_automation_state(automation_id, AutomationState::Blocked, actor, reason)
            .await
            .is_ok()
        {
            self.broadcast_automation_changed(Some(automation_id));
        }
    }

    async fn terminate_owned_automation_sessions(&mut self, run: &AutomationRun, reason: &str) {
        if !run.owned_tab || run.taken_over {
            return;
        }
        if let Some(tab_id) = &run.tab_id {
            self.terminate_sessions_for_tab(tab_id).await;
            self.release_bound_tab_for_run(run, reason).await;
        }
        if let Some(tab_id) = &run.setup_tab_id {
            self.terminate_sessions_for_tab(tab_id).await;
        }
    }
}

pub(super) fn is_non_retryable_dispatch_error(error: &HostError) -> bool {
    is_non_retryable_reason(&error.wire_message())
}

pub(super) fn is_non_retryable_reason(reason: &str) -> bool {
    let message = reason.to_ascii_lowercase();
    message.starts_with("automation existing tab ")
        || message.starts_with("runtime restarted during automation precheck;")
        || message.contains("conversation continuity")
        || message.contains("conversation identity")
        || message.contains("interactive authentication")
        || message.contains("authentication required")
        || message.contains("login required")
        || message.contains("ssh authentication")
        || message.contains("ssh target is missing")
}

#[cfg(test)]
#[path = "automation_run_lifecycle_tests.rs"]
mod expire_tests;

#[cfg(test)]
#[path = "automation_circuit_tests.rs"]
mod circuit_tests;

#[cfg(test)]
#[path = "automation_dispatch_error_tests.rs"]
mod tests;
