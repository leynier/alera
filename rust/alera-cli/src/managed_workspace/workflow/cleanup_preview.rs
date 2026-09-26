use super::*;
use alera_core::runtime::{WorkflowCleanupItem, WorkflowCleanupPreview};
use serde::Deserialize;

#[cfg(test)]
mod tests;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CleanupSelection {
    pub id: String,
    pub run_id: String,
    pub resources: Vec<CleanupResourceSelection>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CleanupResourceSelection {
    pub workspace_id: String,
    pub remove_branch: bool,
}

/// Inspection is off actor and never claims resources or authorizes removal.
pub(crate) async fn preview(
    store: &RuntimeStore,
    selection: CleanupSelection,
) -> Result<WorkflowCleanupPreview> {
    Uuid::parse_str(&selection.id)?;
    if selection.run_id.is_empty()
        || selection.run_id.len() > 160
        || selection.resources.is_empty()
        || selection.resources.len() > 25
    {
        bail!("select between one and 25 resources from one workflow");
    }
    let mut selected = std::collections::BTreeMap::new();
    for resource in selection.resources {
        Uuid::parse_str(&resource.workspace_id)?;
        if selected
            .insert(resource.workspace_id, resource.remove_branch)
            .is_some()
        {
            bail!("cleanup selection contains duplicate resources");
        }
    }
    let exists: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowCleanup WHERE id=?)")
            .bind(&selection.id)
            .fetch_one(store.pool())
            .await?;
    if exists {
        let saved = store.workflow_cleanup_preview(&selection.id).await?;
        let original = saved
            .items
            .iter()
            .map(|item| (item.identity.workspace.id.clone(), item.remove_branch))
            .collect::<std::collections::BTreeMap<_, _>>();
        if saved.run_id != selection.run_id || original != selected {
            bail!("cleanup preview id already has different contents");
        }
        return Ok(saved);
    }
    let mut items = Vec::with_capacity(selected.len());
    for (id, remove_branch) in selected {
        let record = store.workflow_workspace(&id).await?;
        if record.identity.run_id != selection.run_id {
            bail!("cleanup selection contains foreign resources");
        }
        store.require_workspace_outside_cleanup(&id).await?;
        let identity = record.identity;
        let actual = store
            .find_workspace(&id)
            .await?
            .ok_or_else(|| anyhow!("workflow workspace registration is missing"))?;
        let expected = &identity.workspace;
        if actual.instance_id != expected.instance_id
            || actual.host_id != LOCAL_HOST_ID
            || actual.project_id != expected.project_id
            || actual.path != expected.path
            || actual.branch != expected.branch
            || actual.kind != WorkspaceKind::Linked
        {
            bail!("cleanup workspace registration changed");
        }
        let git = core_git::preview_workflow_cleanup(
            &identity.repo_path,
            &expected.path,
            &identity.base_sha,
            &id,
        )?;
        items.push(WorkflowCleanupItem {
            identity,
            git,
            remove_branch,
        });
    }
    store
        .publish_workflow_cleanup_preview(&selection.id, &selection.run_id, items)
        .await
}
