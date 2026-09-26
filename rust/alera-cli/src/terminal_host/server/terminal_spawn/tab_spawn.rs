use super::*;

impl ServerActor {
    pub(in crate::terminal_host::server) async fn upsert_workspace_tab_and_spawn(
        &mut self,
        tab: WorkspaceTabRecord,
    ) -> HostResult<WorkspaceTabRecord> {
        self.upsert_workspace_tab_and_spawn_with_permit(tab, None)
            .await
    }

    pub(in crate::terminal_host::server) async fn upsert_workspace_tab_and_spawn_with_permit(
        &mut self,
        mut tab: WorkspaceTabRecord,
        permit: Option<&WorkflowLaunchPermit>,
    ) -> HostResult<WorkspaceTabRecord> {
        if spawns_on_create(&tab)
            && self
                .runtime_store
                .pending_workspace_checkout_relocation(&tab.workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .is_some()
        {
            return Err(HostError::state(
                "Recover the checkout relocation before starting this terminal",
            ));
        }
        self.initialize_agent_title_if_new(&mut tab).await?;
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let saved = match self
            .ensure_spawn_on_create_terminal_with_permit(&saved, permit)
            .await
        {
            Ok(rewritten) => rewritten.unwrap_or(saved),
            Err(error) => {
                let _ = self.runtime_store.remove_workspace_tab(&saved.id).await;
                self.terminate_sessions_for_tab(&saved.id).await;
                return Err(error);
            }
        };
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        Ok(saved)
    }
}
