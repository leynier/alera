use super::*;
use alera_core::runtime::{
    WorkflowCleanupClaim, WorkflowCleanupItem, WorkflowCleanupPreview, WorkflowCleanupState,
};

pub(crate) struct PreparedCleanup {
    pub claim: WorkflowCleanupClaim,
    _locks: Vec<File>,
}

/// Runs on the bounded blocking lane. Locks survive the actor's process check
/// and every Git/database retirement until this prepared operation is dropped.
pub(crate) async fn prepare(
    store: &RuntimeStore,
    runtime_dir: &Path,
    id: &str,
    digest: &str,
) -> Result<PreparedCleanup> {
    prepare_internal(store, runtime_dir, id, digest, false).await
}

pub(crate) async fn prepare_retry(
    store: &RuntimeStore,
    runtime_dir: &Path,
    id: &str,
    digest: &str,
) -> Result<PreparedCleanup> {
    prepare_internal(store, runtime_dir, id, digest, true).await
}

async fn prepare_internal(
    store: &RuntimeStore,
    runtime_dir: &Path,
    id: &str,
    digest: &str,
    retry: bool,
) -> Result<PreparedCleanup> {
    let preview = store.workflow_cleanup_preview(id).await?;
    if preview.digest != digest {
        bail!("cleanup confirmation does not match its preview");
    }
    let locks = lock_resources(store, runtime_dir, &preview).await?;
    if retry {
        store.resume_workflow_cleanup(id, digest).await?;
    }
    let claim = store.claim_workflow_cleanup(id, digest).await?;
    Ok(PreparedCleanup {
        claim,
        _locks: locks,
    })
}

async fn lock_resources(
    store: &RuntimeStore,
    runtime_dir: &Path,
    preview: &WorkflowCleanupPreview,
) -> Result<Vec<File>> {
    let integration = store
        .workflow_integration_workspace(&preview.run_id)
        .await?;
    let integration_id = &integration.identity.workspace.id;
    let mut locks = vec![resource_lock(runtime_dir, integration_id)?
        .ok_or_else(|| anyhow!("workflow integration is busy; retry cleanup after it settles"))?];
    let mut ids = preview
        .items
        .iter()
        .map(|item| item.identity.workspace.id.as_str())
        .collect::<Vec<_>>();
    ids.sort_unstable();
    for resource in ids {
        if resource != integration_id {
            locks.push(resource_lock(runtime_dir, resource)?.ok_or_else(|| {
                anyhow!("workflow resource is busy; retry cleanup after it settles")
            })?);
        }
    }
    Ok(locks)
}

pub(crate) async fn prepare_abandonment(
    store: &RuntimeStore,
    runtime_dir: &Path,
    id: &str,
    digest: &str,
) -> Result<Option<PreparedCleanup>> {
    let preview = store.workflow_cleanup_preview(id).await?;
    if preview.digest != digest {
        bail!("cleanup confirmation does not match its preview");
    }
    let locks = lock_resources(store, runtime_dir, &preview).await?;
    let status = store.workflow_cleanup_status(id).await?;
    if status.state == WorkflowCleanupState::Abandoned {
        return Ok(None);
    }
    if status.state != WorkflowCleanupState::Attention {
        bail!("only a cleanup needing attention can be abandoned");
    }
    Ok(Some(PreparedCleanup {
        claim: WorkflowCleanupClaim {
            preview,
            retired_workspace_ids: status.retired_workspace_ids,
        },
        _locks: locks,
    }))
}

pub(crate) async fn verify_abandonment_resource(
    store: &RuntimeStore,
    prepared: &PreparedCleanup,
    item: &WorkflowCleanupItem,
) -> Result<()> {
    let preview = &prepared.claim.preview;
    let workspace = &item.identity.workspace;
    store
        .require_retained_cleanup_resource(&preview.id, &preview.digest, &workspace.id)
        .await?;
    let actual = store
        .find_workspace(&workspace.id)
        .await?
        .ok_or_else(|| anyhow!("workflow workspace registration is missing"))?;
    if actual.instance_id != workspace.instance_id
        || actual.host_id != LOCAL_HOST_ID
        || actual.project_id != workspace.project_id
        || actual.path != workspace.path
        || actual.branch != workspace.branch
        || actual.kind != WorkspaceKind::Linked
    {
        bail!("cleanup workspace registration changed");
    }
    if workspace_has_active_automation_owner(store, &workspace.id).await? {
        bail!("workspace is owned by an active automation; stop it before abandoning cleanup");
    }
    core_git::verify_workflow_cleanup_abandonment(
        &item.identity.repo_path,
        &core_git::WorkflowCleanupRemoval {
            cleanup_id: preview.id.clone(),
            resource_id: workspace.id.clone(),
            path: workspace.path.clone(),
            base_sha: item.identity.base_sha.clone(),
            expected_head: item.git.head_sha.clone(),
            remove_branch: item.remove_branch,
        },
    )?;
    Ok(())
}

pub(crate) async fn retire(
    store: &RuntimeStore,
    prepared: &PreparedCleanup,
    item: &WorkflowCleanupItem,
) -> Result<()> {
    let preview = &prepared.claim.preview;
    let workspace = &item.identity.workspace;
    store
        .require_claimed_cleanup_resource(&preview.id, &preview.digest, &workspace.id)
        .await?;
    if let Some(actual) = store.find_workspace(&workspace.id).await? {
        if actual.instance_id != workspace.instance_id
            || actual.host_id != LOCAL_HOST_ID
            || actual.project_id != workspace.project_id
            || actual.path != workspace.path
            || actual.branch != workspace.branch
            || actual.kind != WorkspaceKind::Linked
        {
            bail!("cleanup workspace registration changed");
        }
    }
    if workspace_has_active_automation_owner(store, &workspace.id).await? {
        bail!("workspace is owned by an active automation; stop it before cleanup");
    }
    core_git::remove_workflow_cleanup_resource(
        &item.identity.repo_path,
        &core_git::WorkflowCleanupRemoval {
            cleanup_id: preview.id.clone(),
            resource_id: workspace.id.clone(),
            path: workspace.path.clone(),
            base_sha: item.identity.base_sha.clone(),
            expected_head: item.git.head_sha.clone(),
            remove_branch: item.remove_branch,
        },
    )?;
    store
        .record_workflow_cleanup_retirement(&preview.id, &preview.digest, &workspace.id)
        .await
}
