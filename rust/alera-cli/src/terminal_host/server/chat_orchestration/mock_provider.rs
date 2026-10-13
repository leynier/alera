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
    pub changed: Notify,
}

impl MockProviderFactory {
    pub async fn control(&self, chat_id: &str) -> Arc<MockProviderControl> {
        loop {
            let changed = self.changed.notified();
            if let Some(control) = self.controls.lock().unwrap().get(chat_id).cloned() {
                return control;
            }
            changed.await;
        }
    }
}

impl MockProviderControl {
    pub async fn wait_turns(&self, count: usize) {
        loop {
            let changed = self.changed.notified();
            if self.turns.lock().unwrap().len() >= count {
                return;
            }
            changed.await;
        }
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
