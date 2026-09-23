use alera_core::runtime::AutomationRun;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn requested_remote_automation_cleanup(
        &self,
        client_id: u64,
        workspace_id: &str,
        payload: &Value,
    ) -> HostResult<Option<Box<alera_core::runtime::RemoteAutomationCleanup>>> {
        let Some(value) = payload.get("remoteAutomationCleanup") else {
            return Ok(None);
        };
        self.require_authenticated_local_request(client_id, "workspace.removeShared")?;
        if payload.get("automationCleanupRunId").is_some() {
            return Err(HostError::format(
                "Choose either Home or owner automation cleanup verification",
            ));
        }
        let scope: alera_core::runtime::RemoteAutomationCleanup =
            serde_json::from_value(value.clone()).map_err(|error| {
                HostError::format(format!("Invalid owner automation cleanup scope: {error}"))
            })?;
        let workspace = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Remote automation task no longer exists"))?;
        self.runtime_store
            .require_remote_automation_cleanup(&scope, &workspace)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(Some(Box::new(scope)))
    }

    pub(super) async fn recover_automation_shared_cleanups(&mut self) {
        let now = chrono::Utc::now();
        let ids = match self.runtime_store.due_automation_shared_cleanups(now).await {
            Ok(ids) => ids,
            Err(error) => {
                tracing::warn!(%error, "Could not inspect interrupted automation cleanups");
                return;
            }
        };
        for id in ids {
            match self
                .runtime_store
                .claim_automation_shared_cleanup(&id, now)
                .await
            {
                Ok(Some(attempt)) => self.resume_automation_shared_cleanup(attempt).await,
                Ok(None) => {}
                Err(error) => {
                    tracing::warn!(%error, "Could not reserve interrupted automation cleanup")
                }
            }
        }
    }

    pub(super) async fn requested_automation_shared_cleanup(
        &self,
        workspace_id: &str,
        payload: &Value,
    ) -> HostResult<Option<Box<AutomationRun>>> {
        let Some(value) = payload.get("automationCleanupRunId") else {
            return Ok(None);
        };
        let id = value
            .as_str()
            .filter(|id| !id.trim().is_empty())
            .ok_or_else(|| HostError::format("automationCleanupRunId must be a nonempty string"))?;
        let run = self
            .runtime_store
            .find_automation_run(id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Automation run no longer exists"))?;
        let workspace = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Automation task no longer exists"))?;
        self.runtime_store
            .require_automation_shared_workspace_cleanup(&run, &workspace)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(Some(Box::new(run)))
    }
}

#[cfg(test)]
#[path = "automation_shared_cleanup_requests_tests.rs"]
mod tests;
