//! Cloneable host handle for persistent agent-chat session actors.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
#[cfg(test)]
use std::time::Duration;

use alera_core::runtime::{
    AgentChatCreateOutcome, AgentChatReceipt, AgentChatRecord, RuntimeStore,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::{broadcast, mpsc, oneshot};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, CallerCtx, ChatEnvelope, ChatOp, ReceiptKey};
use super::events::{ChatEventSink, ChatRuntimeEvent, EventFanout};
use super::header::Header;
use super::ids::{new_id, receipt_scope};
use super::provider_factory::{ProviderFactory, ProviderLaunchHook};
use super::provider_traits::provider_traits;
use super::session::{ChatSession, SessionDeps, DEFAULT_FLUSH_DELAY};
use super::tab_directory::{chat_tab_payload, chat_tab_record, TabDirectory};
use super::{ChatActivity, InstanceDirectory};

const SESSION_QUEUE: usize = 64;

#[path = "runtime_handle_commands.rs"]
mod runtime_handle_commands;
#[path = "runtime_handle_create.rs"]
mod runtime_handle_create;
#[path = "runtime_handle_queries.rs"]
mod runtime_handle_queries;

#[cfg(test)]
#[path = "runtime_handle_tests.rs"]
mod tests;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct CreateChatInput {
    pub workspace_id: String,
    pub provider: Option<String>,
    pub provider_instance_id: Option<String>,
    pub model: Option<String>,
    #[serde(default)]
    pub reasoning_effort: Option<String>,
    pub runtime_mode: Option<String>,
    pub interaction_mode: Option<String>,
    pub title: Option<String>,
    pub metadata: Option<Value>,
}

struct Inner {
    deps: SessionDeps,
    fanout: Arc<EventFanout>,
    sessions: Mutex<HashMap<String, mpsc::Sender<ChatEnvelope>>>,
    spawn_lock: tokio::sync::Mutex<()>,
}

#[derive(Clone)]
pub(crate) struct AgentChatRuntime {
    inner: Arc<Inner>,
}

impl AgentChatRuntime {
    pub(crate) fn new(
        store: RuntimeStore,
        factory: Arc<dyn ProviderFactory>,
        tabs: Arc<dyn TabDirectory>,
        host_sink: Box<dyn ChatEventSink>,
        instances: Arc<InstanceDirectory>,
    ) -> Self {
        let fanout = Arc::new(EventFanout::new(host_sink));
        let deps = SessionDeps {
            store,
            factory,
            hooks: Default::default(),
            sink: fanout.clone(),
            tabs,
            activity: Arc::new(ChatActivity::default()),
            instances,
            flush_delay: DEFAULT_FLUSH_DELAY,
        };
        Self {
            inner: Arc::new(Inner {
                deps,
                fanout,
                sessions: Mutex::new(HashMap::new()),
                spawn_lock: tokio::sync::Mutex::new(()),
            }),
        }
    }

    #[cfg(test)]
    pub(crate) fn with_flush_delay(self, delay: Duration) -> Self {
        let mut inner = Arc::try_unwrap(self.inner)
            .ok()
            .expect("runtime is not shared yet");
        inner.deps.flush_delay = delay;
        Self {
            inner: Arc::new(inner),
        }
    }

    pub(crate) fn activity(&self) -> Arc<ChatActivity> {
        self.inner.deps.activity.clone()
    }

    pub(crate) fn subscribe(&self) -> broadcast::Receiver<ChatRuntimeEvent> {
        self.inner.fanout.subscribe()
    }

    pub(crate) fn register_launch_hook(&self, hook: Arc<dyn ProviderLaunchHook>) {
        if let Ok(mut hooks) = self.inner.deps.hooks.write() {
            hooks.push(hook);
        }
    }

    pub(crate) fn store(&self) -> &RuntimeStore {
        &self.inner.deps.store
    }

    #[cfg(test)]
    pub(crate) fn instances(&self) -> Arc<InstanceDirectory> {
        self.inner.deps.instances.clone()
    }

    pub(super) async fn publish_runtime_event(&self, event: ChatRuntimeEvent) {
        self.inner.deps.sink.emit(event).await;
    }

    async fn session(&self, chat_id: &str) -> HostResult<mpsc::Sender<ChatEnvelope>> {
        if let Some(sender) = self.live_sender(chat_id) {
            return Ok(sender);
        }
        let _guard = self.inner.spawn_lock.lock().await;
        if let Some(sender) = self.live_sender(chat_id) {
            return Ok(sender);
        }
        let session = ChatSession::load(chat_id, self.inner.deps.clone())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let (tx, rx) = mpsc::channel(SESSION_QUEUE);
        tokio::spawn(session.run(rx));
        self.inner
            .sessions
            .lock()
            .unwrap()
            .insert(chat_id.to_owned(), tx.clone());
        Ok(tx)
    }

    fn live_sender(&self, chat_id: &str) -> Option<mpsc::Sender<ChatEnvelope>> {
        let mut sessions = self.inner.sessions.lock().unwrap();
        match sessions.get(chat_id) {
            Some(sender) if !sender.is_closed() => Some(sender.clone()),
            Some(_) => {
                sessions.remove(chat_id);
                None
            }
            None => None,
        }
    }

    pub(crate) async fn command(
        &self,
        chat_id: &str,
        op: ChatOp,
        ctx: CallerCtx,
        receipt_key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(key) = &receipt_key {
            if let Some(response) =
                ChatSession::check_receipt(self.inner.deps.store.clone(), &ctx, key).await?
            {
                return Ok(response);
            }
        }
        let mut envelope = ChatEnvelope {
            op,
            ctx,
            receipt_key,
            reply: oneshot::channel().0,
        };
        for _ in 0..2 {
            let sender = self.session(chat_id).await?;
            let (reply, response) = oneshot::channel();
            envelope.reply = reply;
            match sender.send(envelope).await {
                Ok(()) => {
                    return response
                        .await
                        .unwrap_or_else(|_| Err(HostError::state("The chat session stopped.")));
                }
                Err(mpsc::error::SendError(returned)) => {
                    self.inner.sessions.lock().unwrap().remove(chat_id);
                    envelope = returned;
                }
            }
        }
        Err(HostError::state("The chat session is unavailable."))
    }

    pub(crate) async fn reopen(
        &self,
        chat_id: &str,
        ctx: CallerCtx,
        receipt_key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        let record = self
            .inner
            .deps
            .store
            .agent_chat(chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| conflict("chatNotFound", "Unknown chat"))?;
        if !record.archived {
            return Err(conflict("chatNotArchived", "This chat is already open."));
        }
        let workspace = self
            .inner
            .deps
            .tabs
            .workspace(&record.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("The chat workspace no longer exists."))?;
        if workspace.host_id != "local" {
            return Err(HostError::conflict(
                "host_unavailable",
                "The local chat runtime cannot reopen a chat on a remote host.",
                json!({"hostId": workspace.host_id}),
            ));
        }
        let tab_id = new_id("tab");
        let snapshot = self
            .command(chat_id, ChatOp::Reopen { tab_id }, ctx, receipt_key)
            .await?;
        Ok(json!({
            "chatId": chat_id,
            "tabId": snapshot["tabId"],
            "snapshot": snapshot,
        }))
    }
}

pub(crate) fn chat_summary(chat: &AgentChatRecord) -> Value {
    let snapshot = &chat.snapshot;
    json!({
        "chatId": chat.chat_id,
        "workspaceId": chat.workspace_id,
        "tabId": chat.tab_id,
        "title": snapshot["title"],
        "provider": snapshot["provider"],
        "providerInstanceId": snapshot["providerInstanceId"],
        "model": snapshot["session"]["model"],
        "status": snapshot["session"]["status"],
        "archived": chat.archived,
        "cursor": chat.cursor,
        "updatedAt": chat.updated_at,
    })
}
