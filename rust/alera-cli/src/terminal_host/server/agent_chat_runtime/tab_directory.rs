//! The workspace a chat runs in and the title of its tab. Creating, removing
//! and restoring the tab itself goes through the store's chat API, which does
//! it in the same transaction as the chat.

use std::path::PathBuf;

use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord, AGENT_CHAT_TAB_KIND};
use async_trait::async_trait;
use serde_json::{json, Value};

#[derive(Debug, Clone)]
pub(crate) struct ChatWorkspace {
    pub path: PathBuf,
    pub host_id: String,
    pub archived: bool,
}

#[async_trait]
pub(crate) trait TabDirectory: Send + Sync + 'static {
    async fn workspace(&self, workspace_id: &str) -> Result<Option<ChatWorkspace>, String>;
    /// Returns the workspace of a tab that still exists.
    async fn rename_tab(&self, tab_id: &str, title: &str) -> Result<Option<String>, String>;
    async fn update_tab(
        &self,
        tab_id: &str,
        title: Option<&str>,
        payload: Option<Value>,
    ) -> Result<Option<String>, String>;
}

pub(crate) fn chat_tab_payload(
    chat_id: &str,
    provider: &str,
    provider_instance_id: &str,
    model: Option<&str>,
) -> Value {
    let mut payload = json!({
        "chatId": chat_id,
        "provider": provider,
        "providerInstanceId": provider_instance_id,
    });
    if let Some(model) = model {
        payload["model"] = json!(model);
    }
    payload
}

pub(crate) fn chat_tab_record(
    tab_id: &str,
    workspace_id: &str,
    title: &str,
    payload: Value,
) -> WorkspaceTabRecord {
    let now = chrono::Utc::now();
    WorkspaceTabRecord {
        id: tab_id.to_string(),
        workspace_id: workspace_id.to_string(),
        kind: AGENT_CHAT_TAB_KIND.to_string(),
        title: title.to_string(),
        created_at: now,
        updated_at: now,
        payload,
    }
}

#[async_trait]
impl TabDirectory for RuntimeStore {
    async fn workspace(&self, workspace_id: &str) -> Result<Option<ChatWorkspace>, String> {
        Ok(self
            .find_workspace(workspace_id)
            .await
            .map_err(|error| error.to_string())?
            .map(|workspace| ChatWorkspace {
                path: PathBuf::from(workspace.path),
                host_id: workspace.host_id,
                archived: workspace.is_archived,
            }))
    }

    async fn rename_tab(&self, tab_id: &str, title: &str) -> Result<Option<String>, String> {
        if self
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| error.to_string())?
            .is_none()
        {
            return Ok(None);
        }
        self.rename_workspace_tab(tab_id, title)
            .await
            .map(|tab| Some(tab.workspace_id))
            .map_err(|error| error.to_string())
    }

    async fn update_tab(
        &self,
        tab_id: &str,
        title: Option<&str>,
        payload: Option<Value>,
    ) -> Result<Option<String>, String> {
        let Some(mut tab) = self
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| error.to_string())?
        else {
            return Ok(None);
        };
        if let Some(title) = title {
            if title.trim().is_empty() {
                return Err("Tab title cannot be empty".into());
            }
            tab.title = title.to_string();
        }
        if let Some(payload) = payload {
            tab.payload = payload;
        }
        let workspace_id = tab.workspace_id.clone();
        self.upsert_workspace_tab(tab)
            .await
            .map_err(|error| error.to_string())?;
        Ok(Some(workspace_id))
    }
}
