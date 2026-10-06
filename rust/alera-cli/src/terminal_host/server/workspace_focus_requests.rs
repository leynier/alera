//! `workspace.focus`: asks the connected desktop app to select and show an
//! existing workspace.
//!
//! The host only validates and delivers. Selection belongs to the app, which
//! runs the same path as a click in the sidebar, so the request never creates,
//! wakes, or closes anything on its own.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::client_delivery::LocalClientRole;
use super::requests::require_string_key;
use super::{ClientKind, ServerActor};

pub(super) const WORKSPACE_FOCUS_REQUESTED_EVENT: &str = "workspaceFocusRequested";

const NO_APP_CONNECTED: &str =
    "No Alera desktop app is connected to this runtime. Open Alera and try again.";
const APP_WITHOUT_FOCUS: &str =
    "The Alera app connected to this runtime does not support workspace focus. Update Alera and try again.";

impl ServerActor {
    pub(super) async fn focus_workspace_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_authenticated_local_request(client_id, "workspace.focus")?;
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        if workspace.is_archived {
            return Err(HostError::state(format!(
                "Workspace {workspace_id} is archived. Unarchive it before focusing it."
            )));
        }
        let apps = self.connected_desktop_apps();
        if apps.is_empty() {
            return Err(HostError::state(NO_APP_CONNECTED));
        }
        let message = event(
            WORKSPACE_FOCUS_REQUESTED_EVENT,
            json!({"workspaceId": workspace.id, "projectId": workspace.project_id}),
        );
        let mut delivered = 0;
        let mut supported = 0;
        for (app_id, handles_focus) in apps {
            if !handles_focus {
                continue;
            }
            supported += 1;
            if self.try_client_write(app_id, message.clone()) {
                delivered += 1;
            }
        }
        if supported == 0 {
            return Err(HostError::state(APP_WITHOUT_FOCUS));
        }
        if delivered == 0 {
            return Err(HostError::state(NO_APP_CONNECTED));
        }
        Ok(json!({
            "workspaceId": workspace.id,
            "projectId": workspace.project_id,
            "name": workspace.name,
            "appClients": delivered,
        }))
    }

    /// Authenticated desktop app connections, with whether each one handles
    /// `workspaceFocusRequested`. CLI and phone connections never count.
    fn connected_desktop_apps(&self) -> Vec<(u64, bool)> {
        let mut apps: Vec<_> = self
            .clients
            .iter()
            .filter(|(_, client)| {
                client.authenticated
                    && client.kind == ClientKind::Local
                    && client.local_role == LocalClientRole::App
            })
            .map(|(id, client)| (*id, client.workspace_focus))
            .collect();
        apps.sort_unstable_by_key(|(id, _)| *id);
        apps
    }
}

#[cfg(test)]
#[path = "workspace_focus_requests_tests.rs"]
mod tests;
