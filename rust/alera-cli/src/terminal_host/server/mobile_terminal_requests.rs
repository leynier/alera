//! Mobile terminal tab creation and attachment: the gateway-facing requests
//! that mint terminal tabs for phones, attach them to sessions, and claim the
//! viewport driver seat right after.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{event, int_or};
use alera_core::runtime::{Workspace, WorkspaceTabRecord};
use chrono::Utc;
use uuid::Uuid;

use super::requests::{optional_string_key, require_string_key, terminal_session_id_from_tab};
use super::terminal_launch_defaults::default_terminal_launch;
use super::ServerActor;

impl ServerActor {
    pub(super) fn mobile_workspace_tabs_payload(&self, tabs: Vec<WorkspaceTabRecord>) -> Value {
        Value::Array(
            tabs.into_iter()
                .map(|tab| {
                    let runtime_title = self
                        .sessions
                        .values()
                        .find(|session| session.tab_id == tab.id)
                        .and_then(|session| session.runtime_title())
                        .map(str::to_string);
                    let mut value = json!(tab);
                    if let (Some(title), Some(object)) = (runtime_title, value.as_object_mut()) {
                        object.insert("runtimeTitle".to_string(), Value::String(title));
                    }
                    value
                })
                .collect(),
        )
    }

    pub(super) async fn create_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        let tab_id = Uuid::new_v4().to_string();
        let session_id = Uuid::new_v4().to_string();
        let title =
            optional_string_key(payload, "title").unwrap_or_else(|| "Mobile Terminal".into());
        let now = Utc::now();
        let tab = WorkspaceTabRecord {
            id: tab_id.clone(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".to_string(),
            title,
            created_at: now,
            updated_at: now,
            payload: json!({
                "terminalSessionId": session_id,
                "source": "mobile",
            }),
        };
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let attachment_payload = mobile_terminal_attachment_payload(
            &workspace,
            &tab.id,
            &session_id,
            payload,
            self.config.login_shell,
        )
        .await;
        match self.create_or_attach(client_id, &attachment_payload).await {
            Ok(mut attachment) => {
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                self.claim_mobile_terminal_viewport(
                    client_id,
                    &session_id,
                    payload,
                    &mut attachment,
                );
                Ok(json!({
                    "tab": tab,
                    "attachment": attachment,
                }))
            }
            Err(error) => {
                let _ = self.runtime_store.remove_workspace_tab(&tab.id).await;
                Err(error)
            }
        }
    }

    /// Claims the driver seat for the phone right after a mobile attach or
    /// create, and refreshes the attachment's driver field so the response
    /// reflects the post-claim state.
    fn claim_mobile_terminal_viewport(
        &mut self,
        client_id: u64,
        session_id: &str,
        payload: &Value,
        attachment: &mut Value,
    ) {
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        self.claim_mobile_driver(client_id, session_id, Some((cols, rows)));
        if let (Some(object), Some(session)) =
            (attachment.as_object_mut(), self.sessions.get(session_id))
        {
            object.insert("driver".to_string(), session.driver.payload());
        }
    }

    pub(super) async fn attach_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace tab not found: {tab_id}")))?;
        if tab.kind != "terminal" {
            return Err(HostError::state(format!(
                "Workspace tab is not a terminal: {}",
                tab.id
            )));
        }
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        let session_id = optional_string_key(payload, "sessionId")
            .or_else(|| terminal_session_id_from_tab(&tab))
            .unwrap_or_else(|| tab.id.clone());
        let attachment_payload = mobile_terminal_attachment_payload(
            &workspace,
            &tab.id,
            &session_id,
            payload,
            self.config.login_shell,
        )
        .await;
        let mut attachment = self
            .create_or_attach(client_id, &attachment_payload)
            .await?;
        self.claim_mobile_terminal_viewport(client_id, &session_id, payload, &mut attachment);
        Ok(json!({
            "tab": tab,
            "attachment": attachment,
        }))
    }
}

async fn mobile_terminal_attachment_payload(
    workspace: &Workspace,
    tab_id: &str,
    session_id: &str,
    payload: &Value,
    login_shell: bool,
) -> Value {
    json!({
        "sessionId": session_id,
        "workspaceId": workspace.id.clone(),
        "tabId": tab_id,
        "workingDirectory": workspace.path.clone(),
        "launch": default_terminal_launch(&workspace.path, login_shell)
            .await
            .launch
            .to_json(),
        "cols": int_or(payload, "cols", 80),
        "rows": int_or(payload, "rows", 24),
    })
}

pub(super) fn mobile_request_allowed(request_type: &str) -> bool {
    matches!(
        request_type,
        "status.get"
            | "mobile.status.get"
            | "project.list"
            | "hostDirectory.roots"
            | "hostDirectory.list"
            | "project.register"
            | "project.rename"
            | "project.remove.preview"
            | "project.remove"
            | "project.clone.start"
            | "project.clone.list"
            | "project.clone.cancel"
            | "projectConfig.effective"
            | "projectConfig.upsert"
            | "projectConfig.remove"
            | "project.branches.list"
            | "workspace.list"
            | "workspace.listAll"
            | "workspace.find"
            | "workspaceSidebar.snapshot"
            | "workbenchViewPrefs.get"
            | "workbenchViewPrefs.update"
            | "agentPresence.list"
            | "workspace.setPinned"
            | "workspace.rename"
            | "workspace.sleep"
            | "workspace.repositoryWebUrl"
            | "workspace.createManaged"
            | "workspace.removeManaged"
            | "tab.list"
            | "tab.find"
            | "tab.rename"
            | "tab.remove"
            | "mobile.runtimeSettings.get"
            | "mobile.runtimeSettings.update"
            | "agentQuota.snapshot"
            | "agentQuota.fetchClaudeTui"
            | "cliRegistration.status"
            | "cliRegistration.install"
            | "agentSkill.install"
            | "linkedReview.find"
            | "layout.find"
            | "workspaceTag.list"
            | "workspaceTag.create"
            | "workspaceTag.remove"
            | "workspaceTag.setForWorkspace"
            | "workspaceRelation.list"
            | "workspaceRelation.link"
            | "workspaceRelation.unlink"
            | "workspaceCascade.preview"
            | "terminal.create"
            | "terminal.attach"
            | "terminal.driver.list"
            | "write"
            | "resize"
            | "setOutputPaused"
            | "detach"
            | "terminate"
    )
}
