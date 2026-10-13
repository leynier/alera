use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::catalog::provider_catalog;
use super::super::commands::{CallerCtx, ChatOp};
use super::super::restart_recovery;
use super::{chat_summary, AgentChatRuntime};

impl AgentChatRuntime {
    pub(crate) async fn list(
        &self,
        workspace_id: Option<&str>,
        include_archived: bool,
    ) -> HostResult<Vec<Value>> {
        let chats = match workspace_id {
            Some(workspace_id) => {
                self.inner
                    .deps
                    .store
                    .list_agent_chats(workspace_id, include_archived)
                    .await
            }
            None => {
                self.inner
                    .deps
                    .store
                    .list_all_agent_chats(include_archived)
                    .await
            }
        }
        .map_err(|error| HostError::state(error.to_string()))?;
        Ok(chats.iter().map(chat_summary).collect())
    }

    pub(crate) async fn providers(
        &self,
        workspace_id: Option<&str>,
        refresh: bool,
    ) -> HostResult<Value> {
        let cwd = match workspace_id {
            Some(id) => self
                .inner
                .deps
                .tabs
                .workspace(id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .map(|workspace| workspace.path),
            None => None,
        };
        Ok(provider_catalog(
            self.inner.deps.factory.as_ref(),
            &self.inner.deps.instances,
            cwd,
            refresh,
        )
        .await)
    }

    pub(crate) async fn for_workspace(&self, workspace_id: &str, op: ChatOp) {
        let chats = match self
            .inner
            .deps
            .store
            .list_agent_chats(workspace_id, false)
            .await
        {
            Ok(chats) => chats,
            Err(error) => {
                tracing::warn!(%error, "agent chat workspace lookup failed");
                return;
            }
        };
        for chat in chats {
            let _ = self
                .command(&chat.chat_id, op.clone(), CallerCtx::runtime(), None)
                .await;
        }
    }

    pub(crate) async fn recover_after_restart(&self) -> Result<Vec<String>, String> {
        restart_recovery::recover_after_restart(&self.inner.deps.store).await
    }
}
