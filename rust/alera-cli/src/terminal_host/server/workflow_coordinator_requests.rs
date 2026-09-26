use alera_core::runtime::WorkflowProposalDraft;
use serde_json::{json, Value};

use super::{ClientKind, ServerActor, ServerCommand};

#[cfg(test)]
#[path = "workflow_coordinator_requests/tests.rs"]
mod tests;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(in crate::terminal_host::server) fn start_workflow_coordinator_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        if self
            .clients
            .get(&client_id)
            .is_none_or(|client| client.kind != ClientKind::Local)
        {
            return Err(HostError::state(
                "workflow coordinators require a local host connection",
            ));
        }
        if payload.as_object().is_none_or(|map| map.len() != 1) {
            return Err(HostError::format(
                "coordinator launch requires only a proposal id",
            ));
        }
        let id = payload
            .get("id")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty() && id.len() <= 160)
            .ok_or_else(|| HostError::format("proposal id is required"))?
            .to_owned();
        if self.workflow_workspace_jobs >= 32 {
            return Err(HostError::state(
                "workflow operations are busy; retry shortly",
            ));
        }
        self.workflow_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = store
                .workflow_proposal(&id)
                .await
                .map(Box::new)
                .map_err(|error| HostError::state(error.to_string()));
            let _ = inbox.send(ServerCommand::WorkflowLaunch(crate::terminal_host::server::workflow_launch_requests::WorkflowLaunchCommand::CoordinatorPrepared {
                client_id,
                request_id,
                result,
            }));
        });
        Ok(())
    }

    pub(in crate::terminal_host::server) async fn handle_workflow_coordinator_prepared(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Box<WorkflowProposalDraft>>,
    ) {
        let result = match result {
            Ok(draft) => self.launch_workflow_coordinator(*draft).await,
            Err(error) => Err(error),
        };
        self.handle_workflow_workspace_finished(client_id, request_id, result, true)
            .await;
    }

    async fn launch_workflow_coordinator(
        &mut self,
        draft: WorkflowProposalDraft,
    ) -> HostResult<Value> {
        let (receipt, created) = self
            .runtime_store
            .reserve_workflow_coordinator(&draft)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if !created {
            return serde_json::to_value(receipt)
                .map_err(|error| HostError::state(error.to_string()));
        }
        let profile = draft
            .selection
            .profiles
            .get(&draft.selection.coordinator_profile_id)
            .ok_or_else(|| HostError::state("workflow coordinator profile is unavailable"))?
            .clone();
        let prompt = format!(
            "Propose a workflow plan only. Do not edit repository files, start workers, approve decisions, or integrate results. Read the frozen selection with `alera orchestration plans proposal --id {}`. Inspect the source at exact commit {} without changing the checkout; ignore uncommitted changes. Follow the recipe coordinator instructions and role contracts. Build a concrete bounded task DAG covering every required stage and role. Submit the JSON task array using `alera orchestration plans submit-proposal --id {} --stdin`. Preserve correction references when present. Stop after submission and wait for human review.",
            draft.id, draft.selection.source_sha, draft.id,
        );
        let payload =
            json!({"workspaceId": receipt.workspace_id, "profileId": profile.id, "prompt": prompt});
        let permit =
            crate::terminal_host::server::workflow_launch_requests::WorkflowLaunchPermit::coordinator(receipt.clone());
        let result = self
            .launch_agent_profile_snapshot(
                None,
                &payload,
                Some((profile, receipt.tab_id.clone())),
                Some(&permit),
            )
            .await;
        let error = result.err().map(|_| "Coordinator launch failed. Inspect the retained launch record before creating another proposal.");
        let receipt = self
            .runtime_store
            .settle_workflow_coordinator(&draft.id, &receipt.tab_id, error)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(receipt).map_err(|error| HostError::state(error.to_string()))
    }
}
