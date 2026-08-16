//! Mobile terminal tab creation and attachment: the gateway-facing requests
//! that mint terminal tabs for phones, attach them to sessions, and claim the
//! viewport driver seat right after.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::int_or;
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
        let auto_close_on_success =
            payload.get("autoCloseOnSuccess").and_then(Value::as_bool) == Some(true);
        let mut tab_payload = json!({
            "terminalSessionId": session_id,
            "source": "mobile",
        });
        if auto_close_on_success {
            tab_payload["autoCloseOnSuccess"] = Value::Bool(true);
        }
        let tab = WorkspaceTabRecord {
            id: tab_id.clone(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".to_string(),
            title,
            created_at: now,
            updated_at: now,
            payload: tab_payload,
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
                self.broadcast_workspace_tabs_changed(Some(&workspace.id));
                self.claim_mobile_terminal_viewport(
                    client_id,
                    &session_id,
                    payload,
                    &mut attachment,
                );
                Ok(self.terminal_tab_response_for_client(client_id, tab, attachment))
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
    ///
    /// A phone that has not measured its terminal yet omits `cols`/`rows`, and
    /// that MUST leave the PTY alone rather than fall back to 80x24: defaulting
    /// resized the live session twice per tab open, once to a size nobody was
    /// looking at and again to the real one a layout later, so a full-screen
    /// agent redrew itself into the scrollback at a geometry it never had.
    pub(super) fn claim_mobile_terminal_viewport(
        &mut self,
        client_id: u64,
        session_id: &str,
        payload: &Value,
        attachment: &mut Value,
    ) {
        let viewport = match (payload.get("cols"), payload.get("rows")) {
            (Some(_), Some(_)) => Some((
                int_or(payload, "cols", 80) as u16,
                int_or(payload, "rows", 24) as u16,
            )),
            _ => None,
        };
        self.claim_mobile_driver(client_id, session_id, viewport);
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
        Ok(self.terminal_tab_response_for_client(client_id, tab, attachment))
    }

    pub(super) async fn restart_mobile_terminal(
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
            .restart_terminal(client_id, &attachment_payload)
            .await?;
        self.claim_mobile_terminal_viewport(client_id, &session_id, payload, &mut attachment);
        Ok(self.terminal_tab_response_for_client(client_id, tab, attachment))
    }

    pub(super) fn terminal_tab_response_for_client(
        &self,
        client_id: u64,
        tab: WorkspaceTabRecord,
        attachment: Value,
    ) -> Value {
        let tab = self
            .workspace_tab_for_client(client_id, tab)
            .expect("terminal tabs are supported by every client");
        json!({
            "tab": tab,
            "attachment": attachment,
        })
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
