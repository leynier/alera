use std::time::Duration;

use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationCleanupAttempt, AutomationRun,
};
use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::workspace_buffer_guard_request::request_with_workspace_buffer_guard;

use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) async fn start_automation_shared_cleanup(&mut self, run: &AutomationRun) {
        let Some(workspace_id) = run.workspace_id.as_deref() else {
            return;
        };
        let preparation = self
            .requested_automation_shared_cleanup(
                workspace_id,
                &json!({"automationCleanupRunId":run.id}),
            )
            .await;
        if let Err(error) = preparation {
            self.record_shared_cleanup_outcome(run, "cleanupPreserved", json!(error.to_string()))
                .await;
            return;
        }
        let workspace = match self.runtime_store.find_workspace(workspace_id).await {
            Ok(Some(workspace)) => workspace,
            _ => return,
        };
        if let Err(error) = self
            .runtime_store
            .request_automation_shared_cleanup(run, &workspace, chrono::Utc::now())
            .await
        {
            self.record_shared_cleanup_outcome(run, "cleanupPreserved", json!(error.to_string()))
                .await;
            return;
        }
        self.automations_active = true;
        self.automation_wake.notify_one();
        match self
            .runtime_store
            .claim_automation_shared_cleanup(&run.id, chrono::Utc::now())
            .await
        {
            Ok(Some(attempt)) => self.resume_automation_shared_cleanup(attempt).await,
            Ok(None) => {}
            Err(error) => tracing::warn!(%error, "Could not claim automation cleanup"),
        }
    }

    pub(super) async fn resume_automation_shared_cleanup(
        &mut self,
        attempt: AutomationCleanupAttempt,
    ) {
        let run = &attempt.run;
        let workspace = &attempt.workspace;
        match self
            .runtime_store
            .workspace_retirement_receipt(&workspace.id, &workspace.instance_id)
            .await
        {
            Ok(Some(_)) => {
                if self
                    .runtime_store
                    .settle_automation_shared_cleanup(&attempt, false, None, chrono::Utc::now())
                    .await
                    .unwrap_or(false)
                {
                    self.record_shared_cleanup_outcome(run, "cleanupCompleted", Value::Null)
                        .await;
                }
                return;
            }
            Err(error) => {
                tracing::warn!(%error, "Could not inspect automation cleanup receipt");
                return;
            }
            Ok(None) => {}
        }
        if let Err(error) = self
            .runtime_store
            .require_automation_shared_workspace_cleanup(run, workspace)
            .await
        {
            if self
                .runtime_store
                .settle_automation_shared_cleanup(
                    &attempt,
                    error.downcast_ref::<sqlx::Error>().is_some(),
                    Some(&error.to_string()),
                    chrono::Utc::now(),
                )
                .await
                .unwrap_or(false)
            {
                self.record_shared_cleanup_outcome(
                    run,
                    "cleanupPreserved",
                    json!(error.to_string()),
                )
                .await;
            }
            return;
        }
        // The authenticated loopback client uses the same cross-client buffer
        // handshake and verified shutdown queue as a manual task retirement.
        let payload = json!({
            "id":workspace.id,
            "expectedInstanceId":workspace.instance_id,
            "closeSessions":true,
            "deleteBranch":false,
            "automationCleanupRunId":run.id,
        });
        if !self
            .record_shared_cleanup_outcome(run, "cleanupRequested", payload.clone())
            .await
        {
            return;
        }
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = tokio::time::timeout(Duration::from_secs(90), async {
                let mut client = RuntimeHostRpcClient::connect(&directory)
                    .await?
                    .ok_or_else(|| {
                        anyhow!("The runtime is unavailable for verified task cleanup")
                    })?;
                request_with_workspace_buffer_guard(&mut client, "removeShared", &payload).await
            })
            .await
            .map_err(|_| anyhow!("Automatic task cleanup timed out; retirement must be verified"))
            .and_then(|result| result)
            .map_err(|error| error.to_string());
            let _ = inbox.send(ServerCommand::AutomationSharedCleanupFinished {
                attempt: Box::new(attempt),
                result,
            });
        });
    }

    pub(super) async fn finish_automation_shared_cleanup(
        &mut self,
        attempt: &AutomationCleanupAttempt,
        result: Result<Value, String>,
    ) {
        let run = &attempt.run;
        let instance_id = &attempt.workspace.instance_id;
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        if !self
            .runtime_store
            .settle_automation_shared_cleanup(
                attempt,
                true,
                result.as_ref().err().map(String::as_str),
                chrono::Utc::now(),
            )
            .await
            .unwrap_or(false)
        {
            self.schedule_shutdown_if_idle();
            return;
        }
        self.automation_wake.notify_one();
        let retired = if let Some(workspace_id) = run.workspace_id.as_deref() {
            self.runtime_store
                .workspace_retirement_receipt(workspace_id, instance_id)
                .await
                .ok()
                .flatten()
                .is_some()
        } else {
            false
        };
        let (event, detail) = if retired {
            ("cleanupCompleted", Value::Null)
        } else {
            // A lost RPC response can race a committed removal. Do not report
            // preservation or closed processes until a receipt proves it.
            (
                "cleanupUnverified",
                json!(result
                    .err()
                    .unwrap_or_else(|| "Task retirement receipt is missing".into())),
            )
        };
        self.record_shared_cleanup_outcome(run, event, detail).await;
        self.schedule_shutdown_if_idle();
    }

    async fn record_shared_cleanup_outcome(
        &self,
        run: &AutomationRun,
        event: &str,
        detail: Value,
    ) -> bool {
        if let Err(error) = self
            .runtime_store
            .insert_automation_audit_event(
                Some(&run.automation_id),
                Some(&run.id),
                event,
                AutomationActor {
                    kind: AutomationActorKind::ManagedAgent,
                    id: run.actor_id.clone(),
                    label: Some("automation cleanup guard".into()),
                },
                None,
                detail,
            )
            .await
        {
            tracing::warn!(run_id = %run.id, %error, "Failed to record automation task cleanup outcome");
            return false;
        }
        true
    }
}
