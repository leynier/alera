use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceRelocationPhase, LOCAL_HOST_ID,
};
use anyhow::Result;
use std::path::Path;

/// A changed default directory must not orphan a worktree created by a verified relocation.
pub(crate) async fn verify(
    store: &RuntimeStore,
    workspace: &Workspace,
    project: &Project,
) -> Result<bool> {
    if workspace.host_id != LOCAL_HOST_ID || project.kind != ProjectKind::GitRepository {
        return Ok(false);
    }
    let Some(journal) = store.find_relocated_worktree_ownership(workspace).await? else {
        return Ok(false);
    };
    let Some(checkout) = store.find_workspace_checkout(&workspace.id).await? else {
        return Ok(false);
    };
    if journal.phase != WorkspaceRelocationPhase::Completed
        || journal.repository_path != project.repo_path
        || journal.source.path != project.repo_path
        || journal.destination.id != workspace.id
        || journal.destination.project_id != workspace.project_id
        || journal.destination.host_id != workspace.host_id
        || checkout.path != workspace.path
        || checkout.repository_path.as_deref() != Some(project.repo_path.as_str())
    {
        return Ok(false);
    }
    let path = workspace.path.clone();
    let repository = project.repo_path.clone();
    tokio::task::spawn_blocking(move || -> Result<bool> {
        let metadata = match std::fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(_) => return Ok(false),
        };
        if !metadata.is_dir() || metadata.file_type().is_symlink() {
            return Ok(false);
        }
        let canonical = std::fs::canonicalize(&path)?;
        // The journal recorded a canonical destination. Replaced ancestors cannot redirect it.
        if canonical != Path::new(&path) || canonical == std::fs::canonicalize(&repository)? {
            return Ok(false);
        }
        let Some(parent) = Path::new(&path).parent() else {
            return Ok(false);
        };
        if !canonical.starts_with(std::fs::canonicalize(parent)?) {
            return Ok(false);
        }
        Ok(
            alera_core::git::is_workspace_relocation_worktree(&repository, &path, &journal.id)
                .unwrap_or(false),
        )
    })
    .await?
}
