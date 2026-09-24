use std::path::Path;

use anyhow::Result;

use super::{Project, RuntimeStore, Workspace};
use crate::git;

impl RuntimeStore {
    /// Retained workflow ownership survives deletion or re-registration of a
    /// workspace row, so a matching ID alone is not an authorization check.
    pub async fn workflow_workspace_resource_owned(
        &self,
        workspace: &Workspace,
        project: &Project,
    ) -> Result<bool> {
        let mut after = 0;
        loop {
            let page = self.workflow_resource_ownership_page(after).await?;
            let Some((last, _)) = page.last() else {
                return Ok(false);
            };
            after = *last;
            let workspace = workspace.clone();
            let repo_path = project.repo_path.clone();
            // Canonical filesystem and Git registration checks must not block
            // the runtime actor. A lookup error fails the caller closed.
            let owned = tokio::task::spawn_blocking(move || -> Result<bool> {
                for (_, identity) in page {
                    if identity.workspace.id == workspace.id
                        || path_equals(&identity.workspace.path, &workspace.path)
                        || (identity.workspace.branch == workspace.branch
                            && path_equals(&identity.repo_path, &repo_path))
                        || (Path::new(&workspace.path).exists()
                            && git::is_registered_workflow_worktree(
                                &repo_path,
                                &workspace.path,
                                &identity.workspace.id,
                            )?)
                    {
                        return Ok(true);
                    }
                }
                Ok(false)
            })
            .await??;
            if owned {
                return Ok(true);
            }
        }
    }
}

fn path_equals(left: &str, right: &str) -> bool {
    canonical_path(left) == canonical_path(right)
}

fn canonical_path(path: &str) -> String {
    let target = Path::new(path);
    if let Ok(resolved) = std::fs::canonicalize(target) {
        return resolved.to_string_lossy().trim_end_matches('/').to_string();
    }
    if let (Some(parent), Some(name)) = (target.parent(), target.file_name()) {
        if let Ok(resolved_parent) = std::fs::canonicalize(parent) {
            return resolved_parent
                .join(name)
                .to_string_lossy()
                .trim_end_matches('/')
                .to_string();
        }
    }
    path.trim_end_matches('/').to_string()
}
