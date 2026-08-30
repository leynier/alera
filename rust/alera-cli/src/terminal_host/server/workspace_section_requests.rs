use serde_json::{json, Value};

use super::ServerActor;
use crate::terminal_host::{
    host_error::{HostError, HostResult},
    protocol::event,
};

impl ServerActor {
    pub(super) async fn workspace_section_request(
        &mut self,
        client_id: u64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        let result = match verb {
            "workspaceSection.list" => {
                return serde_json::to_value(
                    self.runtime_store
                        .list_workspace_sections()
                        .await
                        .map_err(state_error)?,
                )
                .map_err(state_error)
            }
            "workspaceSection.create" => serde_json::to_value(
                self.runtime_store
                    .create_workspace_section(
                        required(payload, "name")?,
                        required(payload, "workspaceId")?,
                    )
                    .await
                    .map_err(state_error)?,
            )
            .map_err(state_error)?,
            "workspaceSection.setForWorkspace" => {
                let section = match payload.get("sectionId") {
                    Some(Value::Null) => None,
                    Some(Value::String(id)) if !id.is_empty() => Some(id.as_str()),
                    _ => return Err(HostError::format("sectionId must be a section id or null.")),
                };
                self.runtime_store
                    .set_workspace_section(required(payload, "workspaceId")?, section)
                    .await
                    .map_err(state_error)?;
                json!({})
            }
            "workspaceSection.remove" => {
                self.runtime_store
                    .remove_workspace_section(required(payload, "id")?)
                    .await
                    .map_err(state_error)?;
                json!({})
            }
            _ => return Err(HostError::format("Unknown section request.")),
        };
        self.broadcast_workspaces_changed(None);
        self.broadcast_authenticated(event("workspaceSectionsChanged", json!({})));
        Ok(result)
    }
}

fn required<'a>(payload: &'a Value, key: &str) -> HostResult<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::format(format!("{key} is required.")))
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
