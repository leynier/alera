use super::*;

pub(crate) async fn ensure_unowned(
    store: &RuntimeStore,
    workspace: &Workspace,
    project: &Project,
) -> Result<()> {
    if store
        .workflow_workspace_resource_owned(workspace, project)
        .await?
    {
        bail!(
            "Workflow resources require reviewed cleanup or setup through their recorded attempt"
        );
    }
    Ok(())
}
