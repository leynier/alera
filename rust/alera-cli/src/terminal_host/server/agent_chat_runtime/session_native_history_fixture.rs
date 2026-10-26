use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::Duration;

use alera_provider_protocol::*;
use async_trait::async_trait;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp, ReceiptKey, SendInput};
use super::super::events::NullSink;
use super::super::provider_factory::{
    BoxedProvider, ProviderFactory, ProviderInstanceConfig, ProviderLaunch,
};
use super::super::{AgentChatRuntime, CreateChatInput, InstanceDirectory};
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::server::chat_orchestration::mock_provider::{
    MockProviderControl, MockProviderFactory,
};
use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;

#[derive(Default)]
pub(super) struct NativeRecords {
    pub(super) starts: Mutex<Vec<SessionStartInput>>,
    pub(super) turns: Mutex<Vec<TurnInput>>,
    pub(super) rollbacks: Mutex<Vec<NativeRollbackInput>>,
    pub(super) files: Mutex<Vec<NativeRewindFilesInput>>,
    pub(super) fail_rollback: AtomicBool,
    pub(super) legacy_only: AtomicBool,
    pub(super) files_changed: Mutex<Option<Vec<String>>>,
}

#[derive(Default)]
pub(super) struct NativeFactory {
    pub(super) inner: MockProviderFactory,
    pub(super) records: Arc<NativeRecords>,
}

#[async_trait]
impl ProviderFactory for NativeFactory {
    async fn spawn(&self, launch: &ProviderLaunch) -> Result<BoxedProvider, ProviderError> {
        Ok(Box::new(NativeProvider {
            inner: self.inner.spawn(launch).await?,
            records: self.records.clone(),
            provider: if launch.provider == "claudeAgent" {
                ProviderKind::Claude
            } else {
                ProviderKind::Codex
            },
            instance_id: launch.provider_instance_id.clone(),
            session: None,
        }))
    }
    async fn availability(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> Result<(), String> {
        self.inner.availability(provider, instance).await
    }
}

struct NativeProvider {
    inner: BoxedProvider,
    records: Arc<NativeRecords>,
    provider: ProviderKind,
    instance_id: String,
    session: Option<ProviderSession>,
}

#[async_trait]
impl Provider for NativeProvider {
    fn kind(&self) -> ProviderKind {
        self.provider.clone()
    }
    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            rollback: true,
            native_turn_ids: true,
            ..self.inner.capabilities()
        }
    }
    fn native_history_capabilities(&self) -> NativeHistoryCapabilities {
        let legacy = self.records.legacy_only.load(Ordering::SeqCst);
        NativeHistoryCapabilities {
            file_checkpointing: true,
            rewind_files: true,
            rollback_before_turn: !legacy,
            rollback_remove_turns: legacy,
            ..Default::default()
        }
    }
    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.inner.initialize().await
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        self.records.starts.lock().unwrap().push(input.clone());
        let mut session = self.inner.start_session(input).await?;
        session.provider = self.provider.clone();
        session.provider_instance_id = self.instance_id.clone();
        self.session = Some(session.clone());
        Ok(session)
    }
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        self.records.turns.lock().unwrap().push(input.clone());
        self.inner.send_turn(input).await
    }
    async fn rollback_session(
        &mut self,
        input: NativeRollbackInput,
    ) -> Result<NativeRollbackResult, ProviderError> {
        self.records.rollbacks.lock().unwrap().push(input.clone());
        if self.records.fail_rollback.load(Ordering::SeqCst) {
            return Err(ProviderError::Closed);
        }
        Ok(NativeRollbackResult {
            thread_id: input.thread_id,
            native_thread_id: self.session.as_ref().unwrap().native_thread_id.clone(),
            boundary: input.boundary,
            native_response: json!({"raw":"private-provider-reply"}),
        })
    }
    async fn rewind_files(
        &mut self,
        input: NativeRewindFilesInput,
    ) -> Result<NativeRewindFilesResult, ProviderError> {
        self.records.files.lock().unwrap().push(input.clone());
        Ok(NativeRewindFilesResult {
            thread_id: input.thread_id,
            native_thread_id: self.session.as_ref().unwrap().native_thread_id.clone(),
            native_user_message_id: input.native_user_message_id,
            can_rewind: Some(true),
            error: None,
            files_changed: self.records.files_changed.lock().unwrap().clone(),
            insertions: None,
            deletions: None,
            skipped_links: None,
            native_response: json!({"raw":"private-provider-reply"}),
        })
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.inner.interrupt(input).await
    }
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.inner.respond(response).await
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        let mut event = self.inner.next_event().await?;
        if let Some(event) = event.as_mut() {
            event.provider = self.provider.clone();
            event.provider_instance_id = self.instance_id.clone();
        }
        Ok(event)
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        self.inner.close().await
    }
}

pub(super) fn runtime(harness: &TestHarness, factory: Arc<NativeFactory>) -> AgentChatRuntime {
    AgentChatRuntime::new(
        harness.store.clone(),
        factory,
        Arc::new(harness.store.clone()),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    )
    .with_flush_delay(Duration::ZERO)
}

pub(super) async fn fixture(
    provider: &str,
) -> (TestHarness, AgentChatRuntime, Arc<NativeFactory>, String) {
    let harness = TestHarness::new().await;
    let factory = Arc::new(NativeFactory::default());
    let runtime = runtime(&harness, factory.clone());
    let created = runtime
        .create(
            CreateChatInput {
                workspace_id: "ws-a".into(),
                provider_instance_id: Some(provider.into()),
                ..Default::default()
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let chat = created["chatId"].as_str().unwrap().to_owned();
    (harness, runtime, factory, chat)
}

pub(super) async fn command(
    runtime: &AgentChatRuntime,
    chat: &str,
    op: ChatOp,
    id: &str,
) -> HostResult<Value> {
    let verb = match &op {
        ChatOp::NativeRewind { .. } => "agentChat.rewind",
        ChatOp::NativeRewindFiles { .. } => "agentChat.rewindFiles",
        ChatOp::NativeHistoryReconcile { .. } => "agentChat.nativeHistory.reconcile",
        ChatOp::NativeFileCheckpoints { .. } => "agentChat.fileCheckpoints",
        _ => "test.command",
    };
    let key = ReceiptKey {
        verb: verb.into(),
        request_id: id.into(),
        digest: super::super::ids::payload_digest(&serde_json::to_value(&op).unwrap()),
    };
    runtime
        .command(chat, op, CallerCtx::runtime(), Some(key))
        .await
}

pub(super) async fn control(factory: &NativeFactory, chat: &str) -> Arc<MockProviderControl> {
    tokio::time::timeout(Duration::from_secs(5), factory.inner.control(chat))
        .await
        .unwrap()
}

pub(super) async fn send(
    runtime: &AgentChatRuntime,
    factory: &NativeFactory,
    chat: &str,
    id: &str,
    native_turn: usize,
) -> Value {
    let input = serde_json::from_value::<SendInput>(json!({
        "client_message_id":id,"text":format!("Prompt {id}"),"attachments":[],"delivery":"auto",
    }))
    .unwrap();
    let response = runtime
        .send(chat, input, CallerCtx::runtime())
        .await
        .unwrap();
    let control = control(factory, chat).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(native_turn))
        .await
        .unwrap();
    runtime.snapshot(chat).await.unwrap();
    response
}

pub(super) async fn complete(
    runtime: &AgentChatRuntime,
    factory: &NativeFactory,
    chat: &str,
    native: usize,
) {
    control(factory, chat)
        .await
        .complete(native, "Settled response");
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if runtime.snapshot(chat).await.unwrap()["session"]["activeTurnId"].is_null() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
}

pub(super) async fn wait_for_starts(factory: &NativeFactory, count: usize) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while factory.records.starts.lock().unwrap().len() < count {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
}
