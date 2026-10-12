use alera_core::runtime::{LaunchWorkflowTask, WorkflowLaunchInputs, WorkflowLaunchRecord};
use sha2::{Digest, Sha256};

use super::*;

pub(crate) enum PreparedLaunch {
    Replay(WorkflowLaunchRecord),
    Fresh {
        record: WorkflowLaunchRecord,
        token: String,
        // Keep both resources fenced until the actor finishes the launch.
        locks: [File; 2],
    },
}

/// Native filesystem checks stay on the bounded blocking lane, outside the actor.
pub(crate) async fn prepare(
    store: &RuntimeStore,
    runtime_dir: &Path,
    request: LaunchWorkflowTask,
) -> Result<PreparedLaunch> {
    if let Some(record) = store.workflow_launch_for_request(&request).await? {
        return Ok(PreparedLaunch::Replay(record));
    }
    let integration = store
        .workflow_integration_workspace(&request.run_id)
        .await?;
    let integration_lock = resource_lock(runtime_dir, &integration.identity.workspace.id)?
        .ok_or_else(|| anyhow!("workflow integration is busy; retry shortly"))?;
    let attempt_lock = resource_lock(runtime_dir, &request.workspace_id)?
        .ok_or_else(|| anyhow!("workflow attempt is busy; retry shortly"))?;
    if let Some(record) = store.workflow_launch_for_request(&request).await? {
        return Ok(PreparedLaunch::Replay(record));
    }
    store.validate_workflow_launch(&request).await?;
    let source = store.workflow_workspace(&request.workspace_id).await?;
    let integration = store
        .workflow_integration_workspace(&request.run_id)
        .await?;
    if integration.phase != Phase::Ready {
        bail!("workflow integration workspace is not ready");
    }
    verify_registered(store, &integration).await?;
    verify_registered(store, &source).await?;
    if !core_git::is_worktree_clean(&integration.identity.workspace.path)? {
        bail!("integration workspace has uncommitted changes; inspect it before launching");
    }
    if !core_git::is_worktree_clean(&source.identity.workspace.path)? {
        bail!("workflow attempt has uncommitted changes; inspect it before launching");
    }
    let token = format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
    crate::terminal_host::diagnostics::redaction::register_secret(&token);
    let hash = hex::encode(Sha256::digest(token.as_bytes()));
    let (record, created) = store.reserve_workflow_launch(&request, &hash).await?;
    if !created {
        return Ok(PreparedLaunch::Replay(record));
    }
    Ok(PreparedLaunch::Fresh {
        record,
        token,
        locks: [integration_lock, attempt_lock],
    })
}

/// Revalidates Git after the durable claim and before the actor can create a
/// tab or process. The caller keeps both resource locks for the whole launch.
pub(crate) async fn claim_and_validate(
    store: &RuntimeStore,
    record: &WorkflowLaunchRecord,
) -> Result<WorkflowLaunchInputs> {
    let frozen = store.claim_workflow_launch(&record.id).await?;
    revalidate_at_spawn_boundary(store, record).await?;
    Ok(frozen)
}

/// Repeats the native checks after the actor receives the durable claim. The
/// Alera resource locks do not prevent an IDE or another Git process from
/// changing either checkout while the claim is in flight.
pub(crate) async fn revalidate_at_spawn_boundary(
    store: &RuntimeStore,
    record: &WorkflowLaunchRecord,
) -> Result<()> {
    let source = store
        .workflow_workspace(&record.request.workspace_id)
        .await?;
    let integration = store
        .workflow_integration_workspace(&record.request.run_id)
        .await?;
    if integration.phase != Phase::Ready {
        bail!("workflow integration workspace is not ready");
    }
    verify_registered(store, &integration).await?;
    verify_registered(store, &source).await?;
    let source_tip = core_git::verify_workflow_worktree_tip(
        &source.identity.repo_path,
        &source.identity.workspace.path,
        &source.identity.base_sha,
        &source.identity.workspace.id,
    )?;
    if source_tip != source.identity.base_sha {
        bail!("workflow attempt tip changed after launch reservation; inspect it before retrying");
    }
    if !core_git::is_worktree_clean(&integration.identity.workspace.path)? {
        bail!("integration workspace changed after launch reservation; inspect it before retrying");
    }
    if !core_git::is_worktree_clean(&source.identity.workspace.path)? {
        bail!("workflow attempt changed after launch reservation; inspect it before retrying");
    }
    Ok(())
}
