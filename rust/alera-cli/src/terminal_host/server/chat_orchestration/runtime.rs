use std::sync::Arc;

use alera_core::runtime::{ChatOrchestrationChildTurn, RuntimeStore};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::broadcast;

use super::authorization::BoundChat;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::{
    AgentChatRuntime, CallerCtx, ChatOp, ChatRuntimeEvent, CreateChatInput, ReceiptKey, SendInput,
};

/// The hub ledger uses this boundary while each target host owns its chats.
#[async_trait]
pub(crate) trait ChatOrchestrationRuntime: Send + Sync {
    async fn create(
        &self,
        input: CreateChatInput,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value>;
    async fn list(
        &self,
        workspace_id: Option<&str>,
        include_archived: bool,
    ) -> HostResult<Vec<Value>>;
    async fn providers(&self, workspace_id: Option<&str>, refresh: bool) -> HostResult<Value>;
    async fn providers_for_host(
        &self,
        workspace_id: Option<&str>,
        host_id: Option<&str>,
        refresh: bool,
    ) -> HostResult<Value> {
        if host_id.is_some_and(|host| host != "local") {
            return Err(HostError::conflict(
                "host_unavailable",
                "The selected host's provider catalog is unavailable.",
                json!({}),
            ));
        }
        self.providers(workspace_id, refresh).await
    }
    async fn command(
        &self,
        chat_id: &str,
        operation: ChatOp,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value>;
    async fn send(&self, chat_id: &str, input: SendInput, caller: CallerCtx) -> HostResult<Value>;
    async fn snapshot(&self, chat_id: &str) -> HostResult<Value>;
    async fn validate_binding(&self, binding: &BoundChat) -> HostResult<Value>;
    async fn turn_for_client_message(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> HostResult<Option<Value>>;
    async fn child_turn(
        &self,
        chat_id: &str,
        turn_id: &str,
    ) -> HostResult<Option<ChatOrchestrationChildTurn>>;
    fn subscribe(&self) -> broadcast::Receiver<ChatRuntimeEvent>;
}

pub(crate) struct LocalChatOrchestrationRuntime {
    runtime: AgentChatRuntime,
    store: RuntimeStore,
}

impl LocalChatOrchestrationRuntime {
    pub(crate) fn new(store: RuntimeStore, runtime: AgentChatRuntime) -> Arc<Self> {
        Arc::new(Self { runtime, store })
    }
}

#[async_trait]
impl ChatOrchestrationRuntime for LocalChatOrchestrationRuntime {
    async fn create(
        &self,
        input: CreateChatInput,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        self.runtime.create(input, caller, receipt).await
    }
    async fn list(
        &self,
        workspace_id: Option<&str>,
        include_archived: bool,
    ) -> HostResult<Vec<Value>> {
        self.runtime.list(workspace_id, include_archived).await
    }
    async fn providers(&self, workspace_id: Option<&str>, refresh: bool) -> HostResult<Value> {
        self.runtime.providers(workspace_id, refresh).await
    }
    async fn command(
        &self,
        chat_id: &str,
        operation: ChatOp,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        self.runtime
            .command(chat_id, operation, caller, receipt)
            .await
    }
    async fn send(&self, chat_id: &str, input: SendInput, caller: CallerCtx) -> HostResult<Value> {
        self.runtime.send(chat_id, input, caller).await
    }
    async fn snapshot(&self, chat_id: &str) -> HostResult<Value> {
        self.runtime.snapshot(chat_id).await
    }
    async fn validate_binding(&self, binding: &BoundChat) -> HostResult<Value> {
        let record = self
            .store
            .agent_chat(&binding.chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let valid_credential = self
            .store
            .find_chat_orchestration_credential(&binding.credential_hash)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .is_some_and(|credential| {
                credential.chat_id == binding.chat_id && credential.generation == binding.generation
            });
        let valid_chat = record
            .is_some_and(|record| !record.archived && record.generation == binding.generation);
        if !valid_chat || !valid_credential {
            return Err(HostError::conflict(
                "chat_credential_invalid",
                "The chat credential is invalid or expired.",
                json!({}),
            ));
        }
        self.runtime.snapshot(&binding.chat_id).await
    }
    async fn turn_for_client_message(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> HostResult<Option<Value>> {
        self.store
            .agent_chat_turn_for_client_message(chat_id, client_message_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
    async fn child_turn(
        &self,
        chat_id: &str,
        turn_id: &str,
    ) -> HostResult<Option<ChatOrchestrationChildTurn>> {
        self.store
            .chat_orchestration_child_turn(chat_id, turn_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
    fn subscribe(&self) -> broadcast::Receiver<ChatRuntimeEvent> {
        self.runtime.subscribe()
    }
}
