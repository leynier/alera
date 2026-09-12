use super::workflow_launch_requests::WorkflowLaunchCommand;
use super::{ClientKind, ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::Value;
use std::sync::{Arc, OnceLock};
use tokio::sync::Semaphore;

impl ServerActor {
    pub(super) fn start_workflow_cleanup_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.start_workflow_cleanup_operation(client_id, request_id, payload, false)
    }

    pub(super) fn start_workflow_cleanup_retry(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.start_workflow_cleanup_operation(client_id, request_id, payload, true)
    }

    fn start_workflow_cleanup_operation(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
        retry: bool,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        if self
            .clients
            .get(&client_id)
            .is_none_or(|client| client.kind != ClientKind::Local)
        {
            return Err(HostError::state(
                "workflow cleanup requires a local host connection",
            ));
        }
        let map = payload
            .as_object()
            .filter(|map| map.len() == 2)
            .ok_or_else(|| HostError::format("cleanup requires only its preview id and digest"))?;
        let field = |key| {
            map.get(key)
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 160)
                .ok_or_else(|| HostError::format("invalid cleanup confirmation"))
        };
        let id = field("id")?.to_owned();
        let digest = field("digest")?.to_owned();
        uuid::Uuid::parse_str(&id).map_err(|_| HostError::format("invalid cleanup preview id"))?;
        static CLEANUPS: OnceLock<Arc<Semaphore>> = OnceLock::new();
        let permit = CLEANUPS
            .get_or_init(|| Arc::new(Semaphore::new(1)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("cleanup is busy; retry shortly"))?;
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        tokio::spawn(async move {
            let events = inbox.clone();
            let result = tokio::task::spawn_blocking(move || {
                let _permit = permit;
                runtime.block_on(async {
                    let prepared = if retry {
                        crate::managed_workspace::workflow::cleanup::prepare_retry(
                            &store, &directory, &id, &digest,
                        )
                        .await?
                    } else {
                        crate::managed_workspace::workflow::cleanup::prepare(
                            &store, &directory, &id, &digest,
                        )
                        .await?
                    };
                    let outcome = async {
                        for item in &prepared.claim.preview.items {
                            if prepared
                                .claim
                                .retired_workspace_ids
                                .contains(&item.identity.workspace.id)
                            {
                                continue;
                            }
                            let (reply, done) = tokio::sync::oneshot::channel();
                            events
                                .send(ServerCommand::WorkflowLaunch(
                                    WorkflowLaunchCommand::InspectCleanupOwners {
                                        cleanup_id: id.clone(),
                                        digest: digest.clone(),
                                        workspace_id: item.identity.workspace.id.clone(),
                                        reply,
                                    },
                                ))
                                .map_err(|_| {
                                    anyhow::anyhow!("runtime closed before cleanup inspection")
                                })?;
                            done.await
                                .map_err(|_| {
                                    anyhow::anyhow!("runtime closed during cleanup inspection")
                                })?
                                .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
                            crate::managed_workspace::workflow::cleanup::retire(
                                &store, &prepared, item,
                            )
                            .await?;
                        }
                        Ok::<_, anyhow::Error>(serde_json::to_value(
                            store.workflow_cleanup_status(&id).await?,
                        )?)
                    }
                    .await;
                    if let Err(error) = &outcome {
                        store
                            .mark_workflow_cleanup_attention(&id, &digest, &error.to_string())
                            .await?;
                    }
                    outcome
                })
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))
            .and_then(|result| result.map_err(|error| HostError::state(error.to_string())));
            let _ = inbox.send(ServerCommand::WorkflowWorkspaceFinished {
                client_id,
                request_id,
                result,
                mutated: true,
            });
        });
        Ok(())
    }
}
