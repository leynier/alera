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
#[path = "runtime_handle_queries.rs"]
mod runtime_handle_queries;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct CreateChatInput {
    pub workspace_id: String,
    pub provider: Option<String>,
    pub provider_instance_id: Option<String>,
    pub model: Option<String>,
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
                        .unwrap_or_else(|_| Err(HostError::state("The chat session stopped.")))
                }
                Err(mpsc::error::SendError(returned)) => {
                    self.inner.sessions.lock().unwrap().remove(chat_id);
                    envelope = returned;
                }
            }
        }
        Err(HostError::state("The chat session is unavailable."))
    }

    pub(crate) async fn create(
        &self,
        input: CreateChatInput,
        ctx: CallerCtx,
        receipt_key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        let instance_id = input
            .provider_instance_id
            .clone()
            .or_else(|| input.provider.clone())
            .ok_or_else(|| HostError::format("provider or providerInstanceId is required"))?;
        let provider = self
            .inner
            .deps
            .instances
            .provider_of(&instance_id, input.provider.as_deref())
            .ok_or_else(|| {
                conflict(
                    "providerUnavailable",
                    format!("Unknown provider instance {instance_id}"),
                )
            })?;
        let traits = provider_traits(&provider)
            .ok_or_else(|| conflict("providerUnavailable", "Unknown provider"))?;
        let workspace = self
            .inner
            .deps
            .tabs
            .workspace(&input.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Unknown workspace {}", input.workspace_id)))?;
        if workspace.host_id != "local" {
            return Err(HostError::conflict(
                "host_unavailable",
                "The local chat runtime cannot start a chat on a remote host.",
                json!({"hostId": workspace.host_id}),
            ));
        }
        if workspace.archived {
            return Err(HostError::state(
                "Unarchive the workspace before starting a chat.",
            ));
        }
        let runtime_mode = input
            .runtime_mode
            .clone()
            .unwrap_or_else(|| "approval-required".into());
        let interaction_mode = input
            .interaction_mode
            .clone()
            .unwrap_or_else(|| "default".into());
        if !traits.runtime_modes.contains(&runtime_mode.as_str()) {
            return Err(super::commands::unsupported(format!(
                "{provider} does not support the {runtime_mode} runtime mode."
            )));
        }
        if !traits
            .interaction_modes
            .contains(&interaction_mode.as_str())
        {
            return Err(super::commands::unsupported(format!(
                "{provider} does not support the {interaction_mode} interaction mode."
            )));
        }
        let model = input.model.clone().or_else(|| {
            self.inner
                .deps
                .instances
                .find(&instance_id)
                .and_then(|instance| instance.default_model)
        });
        let chat_id = uuid::Uuid::new_v4().to_string();
        let tab_id = new_id("tab");
        let title = input
            .title
            .clone()
            .map(|title| title.trim().chars().take(200).collect())
            .filter(|title: &String| !title.is_empty())
            .unwrap_or_else(|| traits.label.to_string());
        let capabilities = super::provider_traits::capabilities_json(&provider, None);
        let snapshot = Header::from_snapshot(json!({
            "chatId": chat_id.clone(),
            "workspaceId": input.workspace_id.clone(),
            "tabId": tab_id.clone(),
            "providerInstanceId": instance_id.clone(),
            "provider": provider.clone(),
            "title": title.clone(),
            "cursor": 0,
            "session": {
                "status": "stopped",
                "model": model.clone(),
                "runtimeMode": runtime_mode.clone(),
                "interactionMode": interaction_mode.clone(),
                "cwd": workspace.path.to_string_lossy(),
                "generation": 1,
                "capabilities": capabilities,
            },
            "lineage": super::header::lineage_from_metadata(input.metadata.as_ref()),
            "turns": [], "items": [], "pendingRequests": [], "queue": []
        }))
        .map_err(HostError::state)?
        .to_snapshot();
        let stamp = chrono::Utc::now();
        let record = AgentChatRecord {
            chat_id: chat_id.clone(),
            tab_id: tab_id.clone(),
            workspace_id: input.workspace_id.clone(),
            provider_instance_id: instance_id.clone(),
            provider: provider.clone(),
            native_thread_id: None,
            generation: 1,
            archived: false,
            archived_at: None,
            cursor: 0,
            created_at: stamp,
            updated_at: stamp,
            metadata: input.metadata.clone(),
            snapshot,
        };
        let tab = chat_tab_record(
            &tab_id,
            &input.workspace_id,
            &title,
            chat_tab_payload(&chat_id, &provider, &instance_id, model.as_deref()),
        );
        let receipt = receipt_key.as_ref().map(|key| AgentChatReceipt {
            caller_scope: receipt_scope(&ctx.scope, &key.verb),
            request_id: key.request_id.clone(),
            digest: key.digest.clone(),
            receipt: json!({"chatId": chat_id, "tabId": tab_id}),
        });
        let created = self
            .inner
            .deps
            .store
            .create_agent_chat(&record, &tab, receipt.as_ref())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        match created {
            AgentChatCreateOutcome::Replay(response) => return Ok(response),
            AgentChatCreateOutcome::ReceiptConflict => {
                return Err(conflict(
                    "request_conflict",
                    "This requestId was already used for a different request.",
                ))
            }
            AgentChatCreateOutcome::Created(_) => {}
        }
        self.inner
            .deps
            .sink
            .emit(ChatRuntimeEvent::ChatsChanged {
                workspace_id: Some(input.workspace_id.clone()),
            })
            .await;
        self.inner
            .deps
            .sink
            .emit(ChatRuntimeEvent::TabsChanged {
                workspace_id: input.workspace_id,
            })
            .await;
        let _ = self
            .command(&chat_id, ChatOp::Recover { mode: None }, ctx, None)
            .await;
        self.created_response(&chat_id).await
    }

    async fn created_response(&self, chat_id: &str) -> HostResult<Value> {
        let snapshot = self.snapshot(chat_id).await?;
        Ok(json!({"chatId": chat_id, "tabId": snapshot["tabId"], "snapshot": snapshot}))
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
        "provider": chat.provider,
        "providerInstanceId": chat.provider_instance_id,
        "model": snapshot["session"]["model"],
        "status": snapshot["session"]["status"],
        "archived": chat.archived,
        "cursor": chat.cursor,
        "updatedAt": chat.updated_at,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;

    #[tokio::test]
    async fn creating_and_sending_a_chat_uses_a_canonical_header() {
        let harness = TestHarness::new().await;
        let chat_id = harness.create_chat("ws-a", "approval-required").await;
        assert!(uuid::Uuid::parse_str(&chat_id).is_ok());
        let response = harness.send_human(&chat_id, "message-1", "hello").await;
        assert_eq!(response["delivery"], "started");
        harness.finish().await;
    }

    #[tokio::test]
    async fn reopening_a_cached_archived_chat_updates_the_session_actor() {
        let harness = TestHarness::new().await;
        let chat_id = harness.create_chat("ws-a", "approval-required").await;
        assert!(uuid::Uuid::parse_str(&chat_id).is_ok());

        harness
            .runtime
            .command(&chat_id, ChatOp::Close, CallerCtx::runtime(), None)
            .await
            .unwrap();
        assert_eq!(
            harness.runtime.snapshot(&chat_id).await.unwrap()["archived"],
            Value::Bool(true)
        );

        let reopened = harness
            .runtime
            .reopen(&chat_id, CallerCtx::runtime(), None)
            .await
            .unwrap();
        assert_eq!(reopened["snapshot"]["archived"], Value::Bool(false));
        assert_eq!(
            harness.runtime.snapshot(&chat_id).await.unwrap()["archived"],
            Value::Bool(false)
        );
        harness.finish().await;
    }
}
