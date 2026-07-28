use alera_core::runtime::WorkbenchLayoutRecord;
use serde_json::json;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn rollback_reopened_browser_tab(
        &mut self,
        workspace_id: &str,
        page_id: &str,
        previous_layout: Option<WorkbenchLayoutRecord>,
    ) -> HostResult<()> {
        let layout_result = match previous_layout {
            Some(layout) => self
                .runtime_store
                .upsert_workbench_layout(layout)
                .await
                .map(|_| ()),
            None => {
                self.runtime_store
                    .remove_workbench_layout(workspace_id)
                    .await
            }
        }
        .map_err(|error| HostError::state(error.to_string()));
        let tab_result = self
            .runtime_store
            .remove_workspace_tab(page_id)
            .await
            .map_err(|error| HostError::state(error.to_string()));
        if tab_result.is_ok() {
            self.handle_browser_tab_removed(page_id);
        }
        self.broadcast_workspace_tabs_changed(Some(workspace_id));
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "workbenchLayoutsChanged",
            json!({"workspaceId": workspace_id}),
        ));
        layout_result?;
        tab_result
    }
}
