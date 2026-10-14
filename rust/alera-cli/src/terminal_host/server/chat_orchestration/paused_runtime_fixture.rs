use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use alera_core::runtime::ChatOrchestrationChildTurn;
use async_trait::async_trait;
use serde_json::Value;
use tokio::sync::{broadcast, Notify};

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::server::agent_chat_runtime::{
    CallerCtx, ChatOp, ChatRuntimeEvent, CreateChatInput, ReceiptKey, SendInput,
};

use super::{BoundChat, ChatOrchestrationRuntime};

pub(super) struct CommandGate {
    pub arrived: Notify,
    pub release: Notify,
    pub operations: Mutex<Vec<Value>>,
    chat_id: Option<String>,
    scope: String,
    operation: Option<&'static str>,
    armed: AtomicBool,
}

impl CommandGate {
    pub fn new(chat_id: &str, scope: &str) -> Arc<Self> {
        Arc::new(Self {
            arrived: Notify::new(),
            release: Notify::new(),
            operations: Mutex::new(Vec::new()),
            chat_id: Some(chat_id.into()),
            scope: scope.into(),
            operation: None,
            armed: AtomicBool::new(true),
        })
    }

    pub fn for_operation(chat_id: Option<&str>, scope: &str, operation: &'static str) -> Arc<Self> {
        Arc::new(Self {
            arrived: Notify::new(),
            release: Notify::new(),
            operations: Mutex::new(Vec::new()),
            chat_id: chat_id.map(str::to_owned),
            scope: scope.into(),
            operation: Some(operation),
            armed: AtomicBool::new(true),
        })
    }

    pub fn set_armed(&self, armed: bool) {
        self.armed.store(armed, Ordering::Release);
    }

    async fn pause(&self, chat_id: &str, scope: &str, encoded: Value) {
        let selected = self.operation.is_none_or(|name| {
            encoded.as_str() == Some(name)
                || encoded.get(name).is_some()
                || encoded["WithinCeiling"]["operation"].get(name).is_some()
        });
        if self
            .chat_id
            .as_deref()
            .is_none_or(|target| chat_id == target)
            && scope == self.scope
            && selected
            && self.armed.swap(false, Ordering::AcqRel)
        {
            self.operations.lock().unwrap().push(encoded);
            self.arrived.notify_one();
            tokio::time::timeout(super::test_support::TEST_DEADLINE, self.release.notified())
                .await
                .expect("runtime gate was not released before the fixture deadline");
        }
    }
}

pub(super) struct PausedChatRuntime {
    inner: Arc<dyn ChatOrchestrationRuntime>,
    gate: Arc<CommandGate>,
    pending_operation: Option<(String, Value)>,
    pub snapshot_calls: AtomicUsize,
    pub sent_messages: Mutex<Vec<(String, String)>>,
}

impl PausedChatRuntime {
    pub fn new(inner: Arc<dyn ChatOrchestrationRuntime>, gate: Arc<CommandGate>) -> Arc<Self> {
        Arc::new(Self {
            inner,
            gate,
            pending_operation: None,
            snapshot_calls: AtomicUsize::new(0),
            sent_messages: Mutex::new(Vec::new()),
        })
    }

    pub fn with_pending_operation(
        inner: Arc<dyn ChatOrchestrationRuntime>,
        chat_id: &str,
        state: &str,
    ) -> Arc<Self> {
        Arc::new(Self {
            inner,
            gate: CommandGate::for_operation(None, "unused", "unused"),
            pending_operation: Some((
                chat_id.into(),
                serde_json::json!({"state": state, "kind": "rewind"}),
            )),
            snapshot_calls: AtomicUsize::new(0),
            sent_messages: Mutex::new(Vec::new()),
        })
    }

    fn pending_snapshot(&self, chat_id: &str, mut snapshot: Value) -> Value {
        if let Some((parent, operation)) = &self.pending_operation {
            if parent == chat_id {
                snapshot["pendingNativeOperation"] = operation.clone();
            }
        }
        snapshot
    }
}

#[async_trait]
impl ChatOrchestrationRuntime for PausedChatRuntime {
    async fn create(
        &self,
        input: CreateChatInput,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        self.inner.create(input, caller, receipt).await
    }
    async fn list(&self, workspace_id: Option<&str>, archived: bool) -> HostResult<Vec<Value>> {
        self.inner.list(workspace_id, archived).await
    }
    async fn providers(&self, workspace_id: Option<&str>, refresh: bool) -> HostResult<Value> {
        self.inner.providers(workspace_id, refresh).await
    }
    async fn providers_for_host(
        &self,
        workspace_id: Option<&str>,
        host_id: Option<&str>,
        refresh: bool,
    ) -> HostResult<Value> {
        self.inner
            .providers_for_host(workspace_id, host_id, refresh)
            .await
    }
    async fn command(
        &self,
        chat_id: &str,
        operation: ChatOp,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        let encoded = serde_json::to_value(&operation).unwrap();
        self.gate.pause(chat_id, &caller.scope, encoded).await;
        self.inner
            .command(chat_id, operation, caller, receipt)
            .await
    }
    async fn send(&self, chat_id: &str, input: SendInput, caller: CallerCtx) -> HostResult<Value> {
        self.gate
            .pause(chat_id, &caller.scope, serde_json::json!({"Send": input}))
            .await;
        self.sent_messages
            .lock()
            .unwrap()
            .push((chat_id.to_owned(), input.client_message_id.clone()));
        self.inner.send(chat_id, input, caller).await
    }
    async fn snapshot(&self, chat_id: &str) -> HostResult<Value> {
        self.gate
            .pause(chat_id, "runtime", serde_json::json!("Snapshot"))
            .await;
        self.snapshot_calls.fetch_add(1, Ordering::AcqRel);
        Ok(self.pending_snapshot(chat_id, self.inner.snapshot(chat_id).await?))
    }
    async fn validate_binding(&self, binding: &BoundChat) -> HostResult<Value> {
        Ok(self.pending_snapshot(
            &binding.chat_id,
            self.inner.validate_binding(binding).await?,
        ))
    }
    async fn turn_for_client_message(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> HostResult<Option<Value>> {
        self.inner
            .turn_for_client_message(chat_id, client_message_id)
            .await
    }
    async fn child_turn(
        &self,
        chat_id: &str,
        turn_id: &str,
    ) -> HostResult<Option<ChatOrchestrationChildTurn>> {
        self.inner.child_turn(chat_id, turn_id).await
    }
    fn subscribe(&self) -> broadcast::Receiver<ChatRuntimeEvent> {
        self.inner.subscribe()
    }
}
