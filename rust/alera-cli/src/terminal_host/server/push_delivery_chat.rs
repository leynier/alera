use chrono::Utc;
use serde_json::Value;

use crate::terminal_host::push_notifications::{PushEvent, PushLocation};
use alera_core::runtime::{ChatOrchestrationTaskStatus, AGENT_CHAT_TAB_KIND};

use super::{agent_chat_runtime::ChatRuntimeEvent, ServerActor};

impl ServerActor {
    pub(super) async fn queue_chat_runtime_push(&mut self, event: &ChatRuntimeEvent) {
        if let ChatRuntimeEvent::Deleted { chat_id, .. } = event {
            self.account_push.chat_tracker.forget_chat(chat_id);
            self.account_push
                .damper
                .forget_session(&format!("chat:{chat_id}"));
            return;
        }
        let ChatRuntimeEvent::Changed {
            chat_id,
            workspace_id,
            cursor,
            delta,
        } = event
        else {
            return;
        };
        let requests = self
            .account_push
            .chat_tracker
            .new_requests(chat_id, *cursor, delta);
        if requests.is_empty() || !self.chat_attention_push_enabled().await {
            return;
        }
        let Some(location) = self.chat_push_location(chat_id, workspace_id).await else {
            return;
        };
        for request in requests {
            if self.account_push.damper.should_deliver(
                &format!("chat:{chat_id}"),
                request.kind,
                request.created_at,
                true,
                Utc::now(),
            ) {
                self.enqueue_push_event(PushEvent::chat_request(
                    chat_id,
                    &request.request_id,
                    request.kind,
                    request.created_at,
                    location.clone(),
                ));
            }
        }
    }

    pub(super) async fn queue_chat_task_push(&mut self, change: &Value) {
        let Some(task_id) = change["taskId"].as_str() else {
            return;
        };
        let Ok(Some(task)) = self.runtime_store.chat_orchestration_task(task_id).await else {
            return;
        };
        if !self
            .account_push
            .chat_tracker
            .new_task_revision(task_id, task.revision)
            || !task.needs_attention()
            || !self.chat_attention_push_enabled().await
        {
            return;
        }
        if !self.account_push.damper.should_deliver(
            &format!("chat-task:{task_id}"),
            task.status.as_str(),
            task.updated_at,
            true,
            Utc::now(),
        ) {
            return;
        }
        let location = match (task.child_chat_id.as_deref(), task.workspace_id.as_deref()) {
            (Some(chat), Some(workspace)) => self.chat_push_location(chat, workspace).await,
            (_, Some(workspace)) => self.push_location(None, workspace.into(), None).await,
            _ => None,
        };
        self.enqueue_push_event(PushEvent::chat_task_attention(
            task_id,
            task.revision,
            task.status == ChatOrchestrationTaskStatus::NeedsInput,
            task.child_chat_id.as_deref(),
            task.updated_at,
            location,
        ));
    }

    async fn chat_attention_push_enabled(&self) -> bool {
        self.runtime_store
            .mobile_push_settings()
            .await
            .is_ok_and(|settings| settings.enabled && settings.attention)
    }

    async fn chat_push_location(&self, chat_id: &str, workspace_id: &str) -> Option<PushLocation> {
        let tabs = self
            .runtime_store
            .list_workspace_tabs(workspace_id)
            .await
            .ok()?;
        let tab = tabs.into_iter().find(|tab| {
            tab.kind == AGENT_CHAT_TAB_KIND && tab.payload["chatId"].as_str() == Some(chat_id)
        })?;
        self.push_location(None, workspace_id.into(), Some(tab.id))
            .await
    }
}
