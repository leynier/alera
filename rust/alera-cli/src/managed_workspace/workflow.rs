use std::fs::File;
use std::path::Path;

use alera_core::runtime::{
    open_private_runtime_file, prepare_private_runtime_directory, PrepareWorkflowWorkspace,
    WorkflowWorkspacePhase as Phase, WorkflowWorkspaceRecord,
};

use super::*;
pub(crate) mod recovery;

/// Runs on the host's bounded blocking job lane, including setup copy traversal.
pub(crate) async fn prepare(
    store: &RuntimeStore,
    runtime_dir: &Path,
    request: PrepareWorkflowWorkspace,
) -> Result<WorkflowWorkspaceRecord> {
    let plan = store
        .workflow_plan_revision(&request.run_id, Some(request.revision))
        .await?;
    let project = store
        .find_project(&plan.plan.source_workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("workflow project not found"))?;
    let id = Uuid::new_v4().to_string();
    let branch = format!("alera/workflows/{id}");
    let name = format!("Workflow {}", &id[..8]);
    let path_request = ManagedWorkspaceCreateRequest {
        id: Some(id.clone()),
        project_id: project.id.clone(),
        name: Some(name.clone()),
        branch: branch.clone(),
        source_branch: None,
        reuse_existing_branch: false,
        workspace_root: None,
        path: None,
        parent_workspace_id: None,
        defer_setup: false,
        skip_setup: true,
        setup_script_directory: None,
    };
    // The full UUID avoids display-name collisions and is never caller-selected.
    let path =
        resolve_workspace_path(store, &project, &format!("workflow-{id}"), &path_request).await?;
    let now = Utc::now();
    let candidate = Workspace {
        id,
        instance_id: Uuid::new_v4().to_string(),
        host_id: LOCAL_HOST_ID.into(),
        project_id: project.id.clone(),
        name,
        branch: Some(branch),
        path,
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: vec![],
        tag_names: vec![],
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    };
    let record = store
        .reserve_workflow_workspace(&request, candidate)
        .await?;
    resume(
        store,
        runtime_dir,
        &record.identity.workspace.id,
        request.revision,
    )
    .await
}

pub(crate) async fn resume(
    store: &RuntimeStore,
    runtime_dir: &Path,
    id: &str,
    revision: i64,
) -> Result<WorkflowWorkspaceRecord> {
    let _lock = resource_lock(runtime_dir, id)?.ok_or_else(|| {
        anyhow!("workflow workspace preparation is already running; inspect or retry shortly")
    })?;
    let record = store.workflow_workspace(id).await?;
    store.validate_workflow_workspace(id, revision).await?;
    if record.phase == Phase::Attention {
        return Ok(record);
    }
    if record.phase == Phase::SetupRunning {
        return attention(store, &record, revision,
            "Setup was interrupted. Its outcome is unknown and it will not run again. Inspect the retained workspace and retry in a new attempt.").await;
    }
    let result = advance(store, record, revision).await;
    match result {
        Ok(record) => Ok(record),
        Err(error) => {
            let record = store.workflow_workspace(id).await?;
            attention(store, &record, revision, &error.to_string()).await
        }
    }
}

async fn advance(
    store: &RuntimeStore,
    mut record: WorkflowWorkspaceRecord,
    revision: i64,
) -> Result<WorkflowWorkspaceRecord> {
    let id = record.identity.workspace.id.clone();
    store.validate_workflow_workspace(&id, revision).await?;
    if record.identity.task_id.is_some() {
        let integration = store
            .workflow_integration_workspace(&record.identity.run_id)
            .await?;
        if integration.phase != Phase::Ready {
            bail!("workflow integration workspace is not ready");
        }
        verify_registered(store, &integration).await?;
        if !core_git::is_worktree_clean(&integration.identity.workspace.path)? {
            bail!("integration workspace has uncommitted changes; existing changes were preserved");
        }
    }
    if record.phase == Phase::Reserved {
        record = store
            .transition_workflow_workspace(
                &id,
                revision,
                Phase::Reserved,
                Phase::Creating,
                None,
                None,
            )
            .await?;
    }
    if record.phase == Phase::Creating {
        let resource = &record.identity;
        core_git::ensure_workflow_worktree(
            &resource.repo_path,
            &resource.workspace.path,
            &resource.base_sha,
            &id,
        )?;
        record = store
            .transition_workflow_workspace(
                &id,
                revision,
                Phase::Creating,
                Phase::Created,
                None,
                None,
            )
            .await?;
    }
    verify_registered(store, &record).await?;
    if record.phase == Phase::Ready {
        return Ok(record);
    }
    if record.identity.task_id.is_none() {
        if !core_git::is_worktree_clean(&record.identity.workspace.path)? {
            bail!("integration workspace is not clean; existing changes were preserved");
        }
        return store
            .transition_workflow_workspace(&id, revision, Phase::Created, Phase::Ready, None, None)
            .await;
    }
    let project = store
        .find_project(&record.identity.workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("workflow project disappeared"))?;
    record = store
        .transition_workflow_workspace(
            &id,
            revision,
            Phase::Created,
            Phase::SetupRunning,
            None,
            None,
        )
        .await?;
    let report = run_worktree_setup(store, &project, &record.identity.workspace).await;
    let succeeded = report.steps.iter().all(|step| step.succeeded);
    verify_registered(store, &record).await?;
    store
        .transition_workflow_workspace(
            &id,
            revision,
            Phase::SetupRunning,
            if succeeded {
                Phase::Ready
            } else {
                Phase::Attention
            },
            Some(&report),
            if succeeded {
                None
            } else {
                Some("Project setup failed. Inspect this attempt and retry in a new workspace.")
            },
        )
        .await
}

async fn verify_registered(store: &RuntimeStore, record: &WorkflowWorkspaceRecord) -> Result<()> {
    let expected = &record.identity.workspace;
    let actual = store
        .find_workspace(&expected.id)
        .await?
        .ok_or_else(|| anyhow!("workflow workspace metadata was removed"))?;
    if actual.instance_id != expected.instance_id
        || actual.host_id != LOCAL_HOST_ID
        || actual.project_id != expected.project_id
        || actual.path != expected.path
        || actual.branch != expected.branch
        || actual.kind != WorkspaceKind::Linked
        || actual.status != WorkspaceStatus::Active
    {
        bail!("workflow workspace identity or status changed");
    }
    core_git::verify_workflow_worktree(
        &record.identity.repo_path,
        &expected.path,
        &record.identity.base_sha,
        &expected.id,
    )?;
    Ok(())
}

async fn attention(
    store: &RuntimeStore,
    record: &WorkflowWorkspaceRecord,
    revision: i64,
    message: &str,
) -> Result<WorkflowWorkspaceRecord> {
    let message = message.chars().take(1000).collect::<String>();
    store
        .transition_workflow_workspace(
            &record.identity.workspace.id,
            revision,
            record.phase,
            Phase::Attention,
            None,
            Some(&message),
        )
        .await
}

fn resource_lock(runtime_dir: &Path, id: &str) -> Result<Option<File>> {
    Uuid::parse_str(id)?;
    let directory = runtime_dir.join("workflow-workspaces");
    prepare_private_runtime_directory(&directory)?;
    let file = open_private_runtime_file(&directory.join(format!("{id}.lock")))?;
    // Never unlink a lock inode: another request/process could otherwise acquire
    // a replacement inode while the original operation still owns its lock.
    match file.try_lock() {
        Ok(()) => Ok(Some(file)),
        Err(std::fs::TryLockError::WouldBlock) => Ok(None),
        Err(std::fs::TryLockError::Error(error)) => Err(error.into()),
    }
}

#[cfg(test)]
mod tests;
