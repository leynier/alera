use super::*;

pub(crate) async fn ensure_unowned(
    store: &RuntimeStore,
    workspace: &Workspace,
    project: &Project,
) -> Result<()> {
    let mut after = 0;
    loop {
        let page = store.workflow_resource_ownership_page(after).await?;
        let Some((last, _)) = page.last() else {
            return Ok(());
        };
        after = *last;
        let workspace = workspace.clone();
        let repo_path = project.repo_path.clone();
        // Retained ownership outlives metadata IDs. Page the registry and keep
        // canonical filesystem/Git identity checks off the runtime actor.
        let owned = tokio::task::spawn_blocking(move || -> Result<bool> {
            for (_, identity) in page {
                if identity.workspace.id == workspace.id
                    || path_equals(&identity.workspace.path, &workspace.path)
                    || (identity.workspace.branch == workspace.branch
                        && path_equals(&identity.repo_path, &repo_path))
                    || (Path::new(&workspace.path).exists()
                        && core_git::is_registered_workflow_worktree(
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
            bail!("Workflow resources require reviewed cleanup or setup through their recorded attempt");
        }
    }
}
