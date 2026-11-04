//! `tab.rename` on an agent chat tab renames the chat. The chat header owns
//! the title and writes it to its tab, so renaming only the tab record left
//! the chat header (and every client showing it) on the old title. This
//! covers desktop's tab menu, the CLI `tab rename` and MCP `rename_tab`.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_runtime::ChatOp;
use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn try_start_chat_tab_rename(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if request_type != "tab.rename" {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        let tab_id = require_string_key(payload, "id")?;
        let Some(tab) = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?
        else {
            return Ok(false);
        };
        let Some(chat_id) = (tab.kind == alera_core::runtime::AGENT_CHAT_TAB_KIND)
            .then(|| tab.payload["chatId"].as_str().map(str::to_owned))
            .flatten()
        else {
            return Ok(false);
        };
        let Some(runtime) = self.agent_chat_runtime() else {
            return Ok(false);
        };
        let local_chat = self
            .runtime_store
            .agent_chat(&chat_id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?
            .is_some();
        if !local_chat || !self.agent_chat_client_enabled(client_id) {
            return Ok(false);
        }
        let title = require_string_key(payload, "title")?;
        let ctx = self.agent_chat_caller(client_id);
        let store = self.runtime_store.clone();
        self.spawn_agent_chat_request(client_id, request_id, async move {
            runtime
                .command(&chat_id, ChatOp::Rename { title }, ctx, None)
                .await?;
            let mut tab = store
                .find_workspace_tab(&tab_id)
                .await
                .map_err(|error| HostError::from_anyhow(&error))?
                .ok_or_else(|| HostError::state("Workspace tab not found."))?;
            super::tab_compatibility::redact_private_tab_payload(&mut tab);
            Ok(json!(tab))
        });
        Ok(true)
    }
}
