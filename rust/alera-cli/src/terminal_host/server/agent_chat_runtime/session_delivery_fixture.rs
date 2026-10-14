use std::path::PathBuf;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::Duration;

use alera_provider_protocol::*;
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::Notify;

use super::super::commands::{CallerCtx, SendInput};
use super::super::events::NullSink;
use super::super::provider_factory::{
    BoxedProvider, ProviderFactory, ProviderInstanceConfig, ProviderLaunch,
};
use super::super::{AgentChatRuntime, CreateChatInput, InstanceDirectory};
use crate::terminal_host::server::chat_orchestration::mock_provider::{
    MockProviderControl, MockProviderFactory,
};
use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;

#[derive(Default)]
pub(super) struct SendGate {
    pub(super) entered: Notify,
    pub(super) release: Notify,
}

#[derive(Default)]
pub(super) struct Recorded {
    pub(super) starts: Mutex<Vec<SessionStartInput>>,
    pub(super) turns: Mutex<Vec<TurnInput>>,
    pub(super) steers: Mutex<Vec<(TurnInput, String)>>,
    pub(super) forks: Mutex<Vec<NativeForkInput>>,
    pub(super) reject_steer: AtomicBool,
    pub(super) send_gate: Mutex<Option<Arc<SendGate>>>,
}

#[derive(Default)]
pub(super) struct RecordingFactory {
    pub(super) inner: MockProviderFactory,
    pub(super) recorded: Arc<Recorded>,
}

#[async_trait]
impl ProviderFactory for RecordingFactory {
    async fn spawn(&self, launch: &ProviderLaunch) -> Result<BoxedProvider, ProviderError> {
        Ok(Box::new(RecordingProvider {
            inner: self.inner.spawn(launch).await?,
            recorded: self.recorded.clone(),
            fork_session: None,
        }))
    }
    async fn availability(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> Result<(), String> {
        self.inner.availability(provider, instance).await
    }
    async fn validate_reasoning_effort(
        &self,
        provider: &str,
        _: Option<&ProviderInstanceConfig>,
        _: Option<PathBuf>,
        model: Option<&str>,
        effort: &str,
    ) -> Result<(), String> {
        if provider == "codex"
            && model == Some("verified-model")
            && matches!(effort, "high" | "low")
        {
            Ok(())
        } else {
            Err("The exact model and effort were not verified.".into())
        }
    }
}

struct RecordingProvider {
    pub(super) inner: BoxedProvider,
    pub(super) recorded: Arc<Recorded>,
    fork_session: Option<ProviderSession>,
}

#[async_trait]
impl Provider for RecordingProvider {
    fn kind(&self) -> ProviderKind {
        self.inner.kind()
    }
    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            steer: true,
            fork: true,
            ..self.inner.capabilities()
        }
    }
    fn reasoning_effort_capabilities(&self) -> ReasoningEffortCapabilities {
        ReasoningEffortCapabilities {
            session: true,
            turn: true,
            model_specific: true,
            values: vec!["high".into(), "low".into()],
            session_wire_field: Some("reasoningEffort".into()),
            turn_wire_field: Some("reasoningEffort".into()),
        }
    }
    fn native_history_capabilities(&self) -> NativeHistoryCapabilities {
        NativeHistoryCapabilities {
            fork_at_turn: true,
            ..Default::default()
        }
    }
    fn session(&self) -> Option<&ProviderSession> {
        self.fork_session.as_ref().or_else(|| self.inner.session())
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.inner.initialize().await
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        self.recorded.starts.lock().unwrap().push(input.clone());
        self.inner.start_session(input).await
    }
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        self.recorded.turns.lock().unwrap().push(input.clone());
        let gate = self.recorded.send_gate.lock().unwrap().take();
        if let Some(gate) = gate {
            gate.entered.notify_one();
            gate.release.notified().await;
        }
        self.inner.send_turn(input).await
    }
    async fn steer_turn(&mut self, input: TurnInput, expected: &str) -> Result<(), ProviderError> {
        self.recorded
            .steers
            .lock()
            .unwrap()
            .push((input, expected.into()));
        if self.recorded.reject_steer.load(Ordering::SeqCst) {
            Err(ProviderError::Unsupported(
                "The native provider refused steering.".into(),
            ))
        } else {
            Ok(())
        }
    }
    async fn fork_session(
        &mut self,
        input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        self.recorded.forks.lock().unwrap().push(input.clone());
        let mut session = self.inner.start_session(input.session).await?;
        session.native_thread_id = format!("fork-native-{}", session.thread_id);
        self.fork_session = Some(session.clone());
        Ok(NativeForkResult {
            native_thread_id: Some(session.native_thread_id.clone()),
            session,
            source_native_thread_id: input.source_native_thread_id,
            boundary: input.boundary,
        })
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.inner.interrupt(input).await
    }
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.inner.respond(response).await
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.inner.next_event().await
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        self.inner.close().await
    }
}

pub(super) async fn fixture() -> (TestHarness, AgentChatRuntime, Arc<RecordingFactory>) {
    let harness = TestHarness::new().await;
    let factory = Arc::new(RecordingFactory::default());
    let runtime = AgentChatRuntime::new(
        harness.store.clone(),
        factory.clone(),
        Arc::new(harness.store.clone()),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    )
    .with_flush_delay(Duration::ZERO);
    (harness, runtime, factory)
}

pub(super) async fn create(runtime: &AgentChatRuntime, effort: Option<&str>) -> String {
    let created = runtime
        .create(
            CreateChatInput {
                workspace_id: "ws-a".into(),
                provider_instance_id: Some("codex".into()),
                model: Some("verified-model".into()),
                reasoning_effort: effort.map(str::to_owned),
                ..Default::default()
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    created["chatId"].as_str().unwrap().into()
}

pub(super) fn input(id: &str, text: &str) -> SendInput {
    serde_json::from_value(json!({
        "client_message_id": id, "text": text, "attachments": [], "delivery": "auto",
    }))
    .unwrap()
}

pub(super) async fn send(runtime: &AgentChatRuntime, chat: &str, id: &str, text: &str) -> Value {
    runtime
        .send(chat, input(id, text), CallerCtx::runtime())
        .await
        .unwrap()
}

pub(super) async fn wait_until(test: impl Fn() -> bool) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while !test() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
}

pub(super) async fn provider_control(
    factory: &RecordingFactory,
    chat: &str,
) -> Arc<MockProviderControl> {
    tokio::time::timeout(Duration::from_secs(5), factory.inner.control(chat))
        .await
        .unwrap()
}

pub(super) async fn finish_turn(
    runtime: &AgentChatRuntime,
    factory: &RecordingFactory,
    chat: &str,
    native: usize,
) {
    let control = provider_control(factory, chat).await;
    control.complete(native, "Completed source response");
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
