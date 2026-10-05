use alera_core::runtime::{AutomationDefinition, Workspace};

use super::super::ServerActor;

impl ServerActor {
    /// Gives a workspace an automation run just created the definition's tags
    /// and section. A tag or section deleted since the automation was saved is
    /// skipped: a stale choice must never fail the run.
    pub(in crate::terminal_host::server) async fn apply_automation_workspace_placement(
        &self,
        definition: &AutomationDefinition,
        workspace: &Workspace,
    ) {
        let placement = &definition.workspace_placement;
        if placement.is_empty() {
            return;
        }
        if !placement.tag_ids.is_empty() {
            match self.runtime_store.list_tags().await {
                Ok(tags) => {
                    let mut ids = workspace.tag_ids.clone();
                    for id in &placement.tag_ids {
                        if tags.iter().any(|tag| &tag.id == id) && !ids.contains(id) {
                            ids.push(id.clone());
                        }
                    }
                    if let Err(error) = self
                        .runtime_store
                        .set_workspace_tags(&workspace.id, &ids)
                        .await
                    {
                        tracing::warn!(workspace_id = %workspace.id, "could not tag automation workspace: {error}");
                    }
                }
                Err(error) => tracing::warn!("could not list workspace tags: {error}"),
            }
        }
        if let Some(section_id) = placement.section_id.as_deref() {
            match self.runtime_store.list_workspace_sections().await {
                Ok(sections) if sections.iter().any(|section| section.id == section_id) => {
                    if let Err(error) = self
                        .runtime_store
                        .set_workspace_section(&workspace.id, Some(section_id))
                        .await
                    {
                        tracing::warn!(workspace_id = %workspace.id, "could not place automation workspace in its section: {error}");
                    }
                }
                Ok(_) => {}
                Err(error) => tracing::warn!("could not list workspace sections: {error}"),
            }
        }
        self.broadcast_workspaces_changed(Some(&workspace.project_id));
    }
}
