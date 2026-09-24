use alera_core::runtime::{RuntimeStore, WorkspaceRelocationIntent};
use anyhow::{bail, Context, Result};

use super::{RuntimeMutationCompletion, RuntimeMutationEffect};
use crate::terminal_host::server::checkout_buffer_guard_claims::CheckoutBufferGuardProof;

pub(super) async fn run(
    store: &RuntimeStore,
    intent: WorkspaceRelocationIntent,
    relocation_id: Option<String>,
    workspace_root: Option<String>,
    guard: &CheckoutBufferGuardProof,
) -> Result<RuntimeMutationCompletion> {
    let current = store
        .find_workspace(&intent.workspace_id)
        .await?
        .context("Workspace no longer exists")?;
    guard
        .verify_workspace(&current)
        .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
    let existing = match relocation_id.as_deref() {
        Some(id) => store.find_remote_workspace_relocation_intent(id).await?,
        None => {
            store
                .pending_remote_workspace_relocation(&current.project_id, &current.host_id)
                .await?
        }
    };
    let pending = if let Some(existing) = existing {
        if existing.source.id != current.id
            || existing.source.instance_id != current.instance_id
            || existing.source.project_id != current.project_id
            || existing.source.host_id != current.host_id
            || serde_json::to_value(&existing.intent)? != serde_json::to_value(&intent)?
            || existing.workspace_root != workspace_root
        {
            bail!("Resume the pending SSH relocation with its original task and choices");
        }
        existing
    } else {
        let setup_config = if intent.to_project_checkout {
            None
        } else {
            store.find_project_config(&current.project_id).await?
        };
        store
            .begin_remote_workspace_relocation_with_config(
                &relocation_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
                &current,
                intent,
                workspace_root,
                setup_config,
            )
            .await?
    };
    let source = pending.source.clone();
    let response = crate::remote_workspace_relocation::execute(
        store,
        pending,
        &crate::ssh_remote::LiveSshRemoteHost,
        || {
            guard
                .verify()
                .map_err(|error| anyhow::anyhow!(error.wire_message()))
        },
    )
    .await?;
    Ok(RuntimeMutationCompletion {
        response,
        effect: RuntimeMutationEffect::WorkspaceRelocated {
            project_id: source.project_id,
            workspace_id: source.id,
            source_path: source.path,
        },
        closed_tab_ids: Vec::new(),
        hand_on_relocate: None,
    })
}
