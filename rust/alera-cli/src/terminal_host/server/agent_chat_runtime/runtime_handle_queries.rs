use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::catalog::provider_catalog;
use super::super::commands::{CallerCtx, ChatOp};
use super::super::restart_recovery;
use super::super::session_skills::{skill_source_cwd, skills_response};
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
        let mut summaries = Vec::with_capacity(chats.len());
        for chat in chats {
            let mut summary = chat_summary(&chat);
            let attention = self
                .inner
                .deps
                .store
                .agent_chat_attention(&chat.chat_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            summary["readCursor"] = serde_json::json!(attention.read_cursor);
            summary["unread"] = serde_json::json!(attention.unread);
            summary["openChildTaskCount"] = serde_json::json!(attention.open_child_task_count);
            summary["childNeedsInput"] = serde_json::json!(attention.child_needs_input);
            summary["childFailed"] = serde_json::json!(attention.child_failed);
            if let Some(parent) = attention.parent_chat_id {
                summary["parentChatId"] = serde_json::json!(parent);
            }
            summary["pendingNativeOperation"] = self
                .inner
                .deps
                .store
                .pending_agent_chat_native_operation(&chat.chat_id)
                .await
                .map_err(|_| HostError::state("The native history operation could not be read."))?
                .as_ref()
                .map(super::super::session_native_history_recovery::native_operation_public_summary)
                .unwrap_or(Value::Null);
            summaries.push(summary);
        }
        Ok(summaries)
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
            self.inner.deps.factory.clone(),
            self.inner.deps.instances.clone(),
            cwd,
            refresh,
        )
        .await)
    }

    /// `agentChat.skills`: what the composer's `$` menu offers for a chat.
    pub(crate) async fn skills(
        &self,
        chat_id: &str,
        refresh: bool,
        ctx: CallerCtx,
    ) -> HostResult<Value> {
        let source = self
            .command(chat_id, ChatOp::SkillSource, ctx, None)
            .await?;
        let provider = source["provider"].as_str().unwrap_or_default().to_owned();
        let instance_id = source["providerInstanceId"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        let discovered = if source["sessionSkills"].is_array() || provider.is_empty() {
            None
        } else {
            self.inner
                .deps
                .factory
                .discover_skills(
                    &provider,
                    self.inner.deps.instances.find(&instance_id).as_ref(),
                    skill_source_cwd(&source),
                    refresh,
                )
                .await
        };
        Ok(skills_response(&source, || discovered))
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
        self.inner
            .deps
            .store
            .recover_agent_chat_native_operations()
            .await
            .map_err(|_| "Pending native history operations could not be recovered.".to_owned())?;
        restart_recovery::recover_after_restart(&self.inner.deps.store).await
    }
}
