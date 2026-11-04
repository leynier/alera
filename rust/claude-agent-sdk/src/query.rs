use crate::client::ClaudeClient;
use crate::error::Result;
use crate::message::Message;
use crate::types::ClaudeAgentOptions;
use serde_json::Value;
use std::collections::HashSet;
use tokio::time::{timeout_at, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SessionState {
    Idle,
    Running,
    RequiresAction,
}

struct RunState {
    result_received: bool,
    turn_in_progress: bool,
    session_state: Option<SessionState>,
    inflight_tasks: HashSet<String>,
    end_deadline: Option<Instant>,
}

impl RunState {
    fn new() -> Self {
        Self {
            result_received: false,
            turn_in_progress: false,
            session_state: None,
            inflight_tasks: HashSet::new(),
            end_deadline: None,
        }
    }

    fn observe(&mut self, message: &Message, run_end_timeout: std::time::Duration) {
        match message {
            Message::System(system) => self.observe_system(system, run_end_timeout),
            Message::Assistant(assistant)
                if self.result_received && assistant.parent_tool_use_id.is_none() =>
            {
                self.turn_in_progress = true;
                self.end_deadline = None;
            }
            Message::StreamEvent(event)
                if self.result_received && event.parent_tool_use_id.is_none() =>
            {
                self.turn_in_progress = true;
                self.end_deadline = None;
            }
            Message::Result(_) => {
                self.result_received = true;
                self.turn_in_progress = false;
                if self.inflight_tasks.is_empty()
                    && !matches!(
                        self.session_state,
                        Some(SessionState::Running | SessionState::RequiresAction)
                    )
                {
                    self.end_deadline = None;
                } else if !matches!(self.session_state, Some(SessionState::RequiresAction)) {
                    self.arm(run_end_timeout);
                }
            }
            _ => {}
        }
    }

    fn observe_system(
        &mut self,
        system: &crate::message::SystemMessage,
        run_end_timeout: std::time::Duration,
    ) {
        if system.subtype == "session_state_changed" {
            self.session_state = match system.data.get("state").and_then(Value::as_str) {
                Some("idle") => Some(SessionState::Idle),
                Some("requires_action") => Some(SessionState::RequiresAction),
                Some(_) => Some(SessionState::Running),
                None => self.session_state,
            };
            match self.session_state {
                Some(SessionState::Idle)
                    if self.result_received && self.inflight_tasks.is_empty() =>
                {
                    self.end_deadline = None;
                }
                Some(SessionState::RequiresAction) => self.end_deadline = None,
                Some(SessionState::Running) if self.result_received => self.arm(run_end_timeout),
                _ => {}
            }
        }
        let task_id = system.data.get("task_id").and_then(Value::as_str);
        match (system.subtype.as_str(), task_id) {
            ("task_started", Some(task_id))
                if matches!(
                    system.data.get("task_type").and_then(Value::as_str),
                    Some("local_agent" | "local_workflow")
                ) =>
            {
                self.inflight_tasks.insert(task_id.to_owned());
                if self.result_received {
                    self.arm(run_end_timeout);
                }
            }
            ("task_notification", Some(task_id)) => {
                self.inflight_tasks.remove(task_id);
                if self.result_received
                    && !matches!(self.session_state, Some(SessionState::RequiresAction))
                    && self.end_deadline.is_none()
                {
                    self.arm(run_end_timeout);
                }
            }
            ("task_updated", Some(task_id))
                if system
                    .data
                    .get("patch")
                    .and_then(Value::as_object)
                    .and_then(|patch| patch.get("status"))
                    .and_then(Value::as_str)
                    .is_some_and(|status| {
                        matches!(status, "completed" | "failed" | "stopped" | "killed")
                    }) =>
            {
                self.inflight_tasks.remove(task_id);
                if self.result_received
                    && !matches!(self.session_state, Some(SessionState::RequiresAction))
                    && self.end_deadline.is_none()
                {
                    self.arm(run_end_timeout);
                }
            }
            _ => {}
        }
    }

    fn arm(&mut self, run_end_timeout: std::time::Duration) {
        self.end_deadline = Some(Instant::now() + run_end_timeout);
    }

    fn is_done(&self) -> bool {
        self.result_received
            && !self.turn_in_progress
            && self.inflight_tasks.is_empty()
            && !matches!(
                self.session_state,
                Some(SessionState::Running | SessionState::RequiresAction)
            )
            && self.end_deadline.is_none()
    }
}

pub struct Query {
    client: ClaudeClient,
}

impl Query {
    pub async fn next(&self) -> Result<Option<Message>> {
        self.client.next_message().await
    }

    pub async fn collect(self) -> Result<Vec<Message>> {
        let mut messages = Vec::new();
        let mut state = RunState::new();
        loop {
            let next = match state.end_deadline {
                Some(deadline) => match timeout_at(deadline, self.next()).await {
                    Err(_) if state.inflight_tasks.is_empty() => break,
                    Err(_) => {
                        state.end_deadline = None;
                        continue;
                    }
                    Ok(message) => message?,
                },
                None => self.next().await?,
            };
            let Some(message) = next else {
                break;
            };
            state.observe(&message, self.client.run_end_timeout());
            messages.push(message);
            if state.is_done() {
                break;
            }
        }
        self.client.close().await?;
        Ok(messages)
    }

    pub fn client(&self) -> &ClaudeClient {
        &self.client
    }

    pub async fn close(&self) -> Result<()> {
        self.client.close().await
    }
}

pub async fn query(prompt: impl Into<String>, options: ClaudeAgentOptions) -> Result<Query> {
    let client = ClaudeClient::connect(options).await?;
    if let Err(error) = client.send_prompt(prompt).await {
        let _ = client.close().await;
        return Err(error);
    }
    Ok(Query { client })
}

pub async fn query_messages(
    prompt: impl Into<String>,
    options: ClaudeAgentOptions,
) -> Result<Vec<Message>> {
    query(prompt, options).await?.collect().await
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_agent_transport::{JsonTransport, TransportError};
    use async_trait::async_trait;
    use serde_json::json;
    use tokio::sync::mpsc;
    use tokio::time::Duration;

    struct QueryTransport {
        incoming: mpsc::UnboundedReceiver<Value>,
        incoming_tx: mpsc::UnboundedSender<Value>,
        closed: bool,
    }

    impl QueryTransport {
        fn new() -> Self {
            let (incoming_tx, incoming) = mpsc::unbounded_channel();
            Self {
                incoming,
                incoming_tx,
                closed: false,
            }
        }

        fn enqueue(&self, value: Value) {
            let _ = self.incoming_tx.send(value);
        }

        fn enqueue_run(&self) {
            for value in [
                json!({
                    "type": "system",
                    "subtype": "session_state_changed",
                    "state": "running"
                }),
                json!({
                    "type": "system",
                    "subtype": "task_started",
                    "task_id": "agent-1",
                    "task_type": "local_agent"
                }),
                json!({
                    "type": "result",
                    "subtype": "success",
                    "session_id": "session",
                    "is_error": false
                }),
                json!({
                    "type": "assistant",
                    "session_id": "session",
                    "message": {
                        "role": "assistant",
                        "model": "claude-sonnet",
                        "content": [{ "type": "text", "text": "follow-up" }]
                    }
                }),
                json!({
                    "type": "result",
                    "subtype": "success",
                    "session_id": "session",
                    "is_error": false
                }),
                json!({
                    "type": "system",
                    "subtype": "task_notification",
                    "task_id": "agent-1",
                    "status": "completed"
                }),
                json!({
                    "type": "system",
                    "subtype": "session_state_changed",
                    "state": "idle"
                }),
            ] {
                self.enqueue(value);
            }
        }
    }

    #[async_trait]
    impl JsonTransport for QueryTransport {
        async fn send(&mut self, message: Value) -> std::result::Result<(), TransportError> {
            if self.closed {
                return Err(TransportError::Closed);
            }
            match message.get("type").and_then(Value::as_str) {
                Some("control_request") if message["request"]["subtype"] == json!("initialize") => {
                    self.enqueue(json!({
                        "type": "control_response",
                        "response": {
                            "subtype": "success",
                            "request_id": message["request_id"],
                            "response": { "commands": [] }
                        }
                    }));
                }
                Some("user") => self.enqueue_run(),
                _ => {}
            }
            Ok(())
        }

        async fn recv(&mut self) -> std::result::Result<Option<Value>, TransportError> {
            Ok(self.incoming.recv().await)
        }

        async fn close(&mut self) -> std::result::Result<(), TransportError> {
            self.closed = true;
            Ok(())
        }
    }

    #[tokio::test]
    async fn collect_waits_for_task_completion_and_idle_after_a_result() {
        let transport = QueryTransport::new();
        let options = ClaudeAgentOptions {
            run_end_timeout: Duration::from_millis(25),
            ..ClaudeAgentOptions::default()
        };
        let client = ClaudeClient::connect_with_transport(transport, options)
            .await
            .unwrap();
        client.send_prompt("start").await.unwrap();
        let messages = (Query { client }).collect().await.unwrap();
        assert_eq!(messages.len(), 7);
        assert_eq!(messages[0].kind(), "system");
        assert_eq!(messages[1].kind(), "system");
        assert_eq!(messages[2].kind(), "result");
        assert_eq!(messages[3].kind(), "assistant");
        assert_eq!(messages[4].kind(), "result");
        assert_eq!(messages[6].kind(), "system");
    }
}
