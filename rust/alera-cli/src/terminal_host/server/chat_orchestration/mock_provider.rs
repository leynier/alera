use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use alera_provider_protocol::*;
use async_trait::async_trait;
use serde_json::json;
use tokio::sync::{mpsc, Notify};

use crate::terminal_host::server::agent_chat_runtime::provider_factory::{
    BoxedProvider, ProviderFactory, ProviderInstanceConfig, ProviderLaunch,
};

#[derive(Default)]
pub(crate) struct MockProviderFactory {
    pub launches: Mutex<Vec<ProviderLaunch>>,
    controls: Mutex<HashMap<String, Arc<MockProviderControl>>>,
    changed: Notify,
}

pub(crate) struct MockProviderControl {
    chat_id: String,
    events: mpsc::UnboundedSender<ProviderEvent>,
    pub turns: Mutex<Vec<TurnInput>>,
    pub interrupts: Mutex<Vec<InterruptInput>>,
    pub responses: Mutex<Vec<RuntimeResponse>>,
    /// Running background commands the agent may wait on; `None` answers
    /// like a provider without background waits.
    pub background_tasks: Mutex<Option<Vec<String>>>,
    /// Sub-agent task ids the runtime asked to stop.
    pub stopped_subagents: Mutex<Vec<String>>,
    pub changed: Notify,
}

impl MockProviderFactory {
    pub async fn control(&self, chat_id: &str) -> Arc<MockProviderControl> {
        tokio::time::timeout(super::test_support::TEST_DEADLINE, async {
            loop {
                let changed = self.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if let Some(control) = self.controls.lock().unwrap().get(chat_id).cloned() {
                    break control;
                }
                changed.await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("provider {chat_id} did not start before the fixture deadline"))
    }

    pub async fn control_after(
        &self,
        chat_id: &str,
        previous: &Arc<MockProviderControl>,
    ) -> Arc<MockProviderControl> {
        tokio::time::timeout(super::test_support::TEST_DEADLINE, async {
            loop {
                let changed = self.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if let Some(control) = self.controls.lock().unwrap().get(chat_id).cloned() {
                    if !Arc::ptr_eq(&control, previous) {
                        break control;
                    }
                }
                changed.await;
            }
        })
        .await
        .unwrap_or_else(|_| {
            panic!("provider {chat_id} did not restart before the fixture deadline")
        })
    }
}

impl MockProviderControl {
    pub async fn wait_turns(&self, count: usize) {
        tokio::time::timeout(super::test_support::TEST_DEADLINE, async {
            loop {
                let changed = self.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if self.turns.lock().unwrap().len() >= count {
                    break;
                }
                changed.await;
            }
        })
        .await
        .unwrap_or_else(|_| {
            panic!(
                "provider {} did not receive {count} turns before the fixture deadline",
                self.chat_id
            )
        });
    }

    pub fn event(&self, kind: EventKind, native_turn: usize, payload: serde_json::Value) {
        let mut event = ProviderEvent::new(
            ProviderKind::Codex,
            "codex",
            &self.chat_id,
            kind,
            payload,
            None,
        );
        event.turn_id = Some(format!("native-turn-{native_turn}"));
        self.events.send(event).unwrap();
    }

    pub fn item_event(
        &self,
        kind: EventKind,
        native_turn: usize,
        native_item: &str,
        payload: serde_json::Value,
    ) {
        let mut event = ProviderEvent::new(
            ProviderKind::Codex,
            "codex",
            &self.chat_id,
            kind,
            payload,
            None,
        );
        event.turn_id = Some(format!("native-turn-{native_turn}"));
        event.item_id = Some(native_item.into());
        self.events.send(event).unwrap();
    }

    pub fn complete(&self, native_turn: usize, text: &str) {
        self.event(
            EventKind::ItemCompleted,
            native_turn,
            json!({
                "itemId": format!("native-item-{native_turn}"),
                "itemType": "assistant_message", "data": {"text": text},
            }),
        );
        self.event(
            EventKind::TurnCompleted,
            native_turn,
            json!({"state": "completed"}),
        );
    }

    pub fn request_approval(&self, native_turn: usize, native_id: &str) {
        let request = RuntimeRequest {
            request_id: native_id.into(),
            thread_id: self.chat_id.clone(),
            turn_id: Some(format!("native-turn-{native_turn}")),
            item_id: None,
            kind: RequestKind::CommandExecutionApproval,
            questions: Vec::new(),
            payload: json!({"command": "cargo clean"}),
            supports_feedback: false,
        };
        self.events
            .send(
                ProviderEvent::new(
                    ProviderKind::Codex,
                    "codex",
                    &self.chat_id,
                    EventKind::RequestOpened,
                    json!({}),
                    None,
                )
                .with_request(request),
            )
            .unwrap();
    }

    pub fn request_input(&self, native_turn: usize, native_id: &str) {
        let request = RuntimeRequest {
            request_id: native_id.into(),
            thread_id: self.chat_id.clone(),
            turn_id: Some(format!("native-turn-{native_turn}")),
            item_id: None,
            kind: RequestKind::ToolUserInput,
            questions: vec![UserInputQuestion {
                id: "choice".into(),
                header: "Choice".into(),
                question: "Which target?".into(),
                options: Vec::new(),
                allow_custom_answer: Some(true),
                initial_answer: None,
                multi_select: false,
            }],
            payload: json!({}),
            supports_feedback: false,
        };
        self.events
            .send(
                ProviderEvent::new(
                    ProviderKind::Codex,
                    "codex",
                    &self.chat_id,
                    EventKind::UserInputRequested,
                    json!({}),
                    None,
                )
                .with_request(request),
            )
            .unwrap();
    }
}

#[async_trait]
impl ProviderFactory for MockProviderFactory {
    async fn spawn(&self, launch: &ProviderLaunch) -> Result<BoxedProvider, ProviderError> {
        let (events, receiver) = mpsc::unbounded_channel();
        let control = Arc::new(MockProviderControl {
            chat_id: launch.chat_id.clone(),
            events,
            turns: Mutex::new(Vec::new()),
            interrupts: Mutex::new(Vec::new()),
            background_tasks: Mutex::new(None),
            stopped_subagents: Mutex::new(Vec::new()),
            responses: Mutex::new(Vec::new()),
            changed: Notify::new(),
        });
        self.launches.lock().unwrap().push(launch.clone());
        self.controls
            .lock()
            .unwrap()
            .insert(launch.chat_id.clone(), control.clone());
        self.changed.notify_waiters();
        Ok(Box::new(MockProvider {
            control,
            receiver,
            session: None,
        }))
    }

    async fn availability(
        &self,
        _: &str,
        _: Option<&ProviderInstanceConfig>,
    ) -> Result<(), String> {
        Ok(())
    }

    async fn discover_model_metadata(
        &self,
        provider: &str,
        _: Option<&ProviderInstanceConfig>,
        _: Option<std::path::PathBuf>,
    ) -> Option<Result<Vec<serde_json::Value>, String>> {
        (provider == "codex").then(|| {
            Ok(vec![json!({
                "id": "test-model", "label": "Test Model", "reasoningEfforts": ["low", "high"],
                "defaultReasoningEffort": "low",
            })])
        })
    }

    async fn validate_reasoning_effort(
        &self,
        provider: &str,
        _: Option<&ProviderInstanceConfig>,
        _: Option<std::path::PathBuf>,
        model: Option<&str>,
        effort: &str,
    ) -> Result<(), String> {
        if provider == "codex" && model == Some("test-model") && matches!(effort, "low" | "high") {
            Ok(())
        } else {
            Err("This model does not report support for this reasoning effort.".into())
        }
    }
}

struct MockProvider {
    control: Arc<MockProviderControl>,
    receiver: mpsc::UnboundedReceiver<ProviderEvent>,
    session: Option<ProviderSession>,
}

#[async_trait]
impl Provider for MockProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Codex
    }
    fn reasoning_effort_capabilities(&self) -> ReasoningEffortCapabilities {
        ReasoningEffortCapabilities {
            session: true,
            turn: true,
            model_specific: true,
            values: vec!["low".into(), "high".into()],
            session_wire_field: Some("reasoningEffort".into()),
            turn_wire_field: Some("reasoningEffort".into()),
        }
    }
    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            mcp_injection: McpInjectionCapabilities {
                stdio: true,
                http: true,
            },
            resume: true,
            interrupt: true,
            user_input: true,
            model_switch: true,
            ..Default::default()
        }
    }
    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        let session = ProviderSession {
            provider: ProviderKind::Codex,
            provider_instance_id: "codex".into(),
            native_thread_id: format!("native-{}", input.thread_id),
            thread_id: input.thread_id,
            status: SessionStatus::Ready,
            model: input.model,
            cwd: input.cwd,
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        Ok(session)
    }
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        let thread_id = input.thread_id.clone();
        let mut turns = self.control.turns.lock().unwrap();
        turns.push(input);
        let turn_id = format!("native-turn-{}", turns.len());
        drop(turns);
        self.control.changed.notify_waiters();
        Ok(TurnStartResult {
            thread_id,
            native_turn_id: Some(turn_id.clone()),
            turn_id,
        })
    }
    async fn await_background_tasks(
        &mut self,
        task_ids: &[String],
        _awaited: bool,
    ) -> Result<Vec<String>, ProviderError> {
        let running = self.control.background_tasks.lock().unwrap().clone();
        let running =
            running.ok_or_else(|| ProviderError::Unsupported("background waits".into()))?;
        Ok(task_ids
            .iter()
            .filter(|id| running.contains(id))
            .cloned()
            .collect())
    }
    async fn stop_subagent(&mut self, task_id: &str) -> Result<(), ProviderError> {
        let native_turn = self.control.turns.lock().unwrap().len();
        self.control
            .stopped_subagents
            .lock()
            .unwrap()
            .push(task_id.to_owned());
        self.control.event(
            EventKind::TaskCompleted,
            native_turn,
            json!({"taskId": task_id, "status": "stopped"}),
        );
        Ok(())
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        let native_turn = self.control.turns.lock().unwrap().len();
        self.control.interrupts.lock().unwrap().push(input);
        self.control.event(
            EventKind::TurnAborted,
            native_turn,
            json!({"reason": "interrupted"}),
        );
        Ok(())
    }
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.control.responses.lock().unwrap().push(response);
        self.control.changed.notify_waiters();
        Ok(())
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        Ok(self.receiver.recv().await)
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }
}
