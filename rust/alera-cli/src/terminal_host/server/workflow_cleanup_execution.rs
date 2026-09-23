use std::sync::{Arc, OnceLock};

use alera_core::runtime::RuntimeStore;
use tokio::sync::{mpsc::UnboundedSender, Semaphore};

use super::workflow_launch_requests::WorkflowLaunchCommand;
use super::ServerCommand;

#[cfg(test)]
#[path = "workflow_cleanup_recovery_tests.rs"]
mod tests;

#[cfg(test)]
pub(super) static CLEANUP_TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

pub(super) fn cleanup_queue() -> Arc<Semaphore> {
    static CLEANUPS: OnceLock<Arc<Semaphore>> = OnceLock::new();
    CLEANUPS.get_or_init(|| Arc::new(Semaphore::new(1))).clone()
}

/// The blocking job owns the queue permit and all resource locks until Git,
/// metadata and durable failure recording finish, even if its client leaves.
pub(super) async fn execute(
    store: &RuntimeStore,
    directory: &std::path::Path,
    events: &UnboundedSender<ServerCommand>,
    id: &str,
    digest: &str,
    retry: bool,
) -> anyhow::Result<serde_json::Value> {
    let prepared = if retry {
        crate::managed_workspace::workflow::cleanup::prepare_retry(store, directory, id, digest)
            .await?
    } else {
        crate::managed_workspace::workflow::cleanup::prepare(store, directory, id, digest).await?
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
                        cleanup_id: id.into(),
                        digest: digest.into(),
                        workspace_id: item.identity.workspace.id.clone(),
                        reply,
                    },
                ))
                .map_err(|_| anyhow::anyhow!("runtime closed before cleanup inspection"))?;
            done.await
                .map_err(|_| anyhow::anyhow!("runtime closed during cleanup inspection"))?
                .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
            crate::managed_workspace::workflow::cleanup::retire(store, &prepared, item).await?;
        }
        Ok::<_, anyhow::Error>(serde_json::to_value(
            store.workflow_cleanup_status(id).await?,
        )?)
    }
    .await;
    if let Err(error) = &outcome {
        store
            .mark_workflow_cleanup_attention(id, digest, &error.to_string())
            .await?;
    }
    outcome
}

pub(super) async fn reconcile(
    store: &RuntimeStore,
    directory: &std::path::Path,
    events: &UnboundedSender<ServerCommand>,
) -> anyhow::Result<()> {
    // An already-running explicit cleanup owns its recovery; never duplicate it.
    let Ok(_permit) = cleanup_queue().try_acquire_owned() else {
        return Ok(());
    };
    let mut cursor = String::new();
    loop {
        let page = store.pending_workflow_cleanup_page(&cursor).await?;
        for (id, digest) in &page {
            if let Err(error) = execute(store, directory, events, id, digest, false).await {
                // A busy external lock can leave Applying intact. Do not spin or
                // mark another operation's failure; the saved confirmation stays retryable.
                tracing::warn!("workflow cleanup recovery needs attention for {id}: {error}");
            }
        }
        if page.len() < 25 {
            return Ok(());
        }
        cursor = page.last().expect("full cleanup page").0.clone();
    }
}

/// Explicitly releases only intact, unretired claims. The caller owns the same
/// bounded queue as removal; prepared owns all resource locks until settlement.
pub(super) async fn abandon(
    store: &RuntimeStore,
    directory: &std::path::Path,
    events: &UnboundedSender<ServerCommand>,
    id: &str,
    digest: &str,
) -> anyhow::Result<serde_json::Value> {
    let prepared = crate::managed_workspace::workflow::cleanup::prepare_abandonment(
        store, directory, id, digest,
    )
    .await?;
    if let Some(prepared) = prepared {
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
                        cleanup_id: id.into(),
                        digest: digest.into(),
                        workspace_id: item.identity.workspace.id.clone(),
                        reply,
                    },
                ))
                .map_err(|_| anyhow::anyhow!("runtime closed before cleanup inspection"))?;
            done.await
                .map_err(|_| anyhow::anyhow!("runtime closed during cleanup inspection"))?
                .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
            crate::managed_workspace::workflow::cleanup::verify_abandonment_resource(
                store, &prepared, item,
            )
            .await?;
        }
        store.abandon_workflow_cleanup(id, digest).await?;
    }
    Ok(serde_json::to_value(
        store.workflow_cleanup_status(id).await?,
    )?)
}
