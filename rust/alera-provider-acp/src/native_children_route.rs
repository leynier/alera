//! Where native child sessions meet the provider: which notifications they
//! own, the events their changes become, the root turn the agent starts on
//! its own once its background work ends, and stopping one child.

use crate::mapping::{map_incoming, MappingContext};
use crate::native_children::{scoped_id, ChildEvent};
use crate::runtime_response::acp_error;
use crate::transport::raw;
use crate::AcpProvider;
use agent_client_protocol::{AcpIncoming, AcpProtocolGeneration};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderSession, SessionStatus,
    SubagentCapabilities, TurnStatus, BACKGROUND_CONTINUATION_ORIGIN,
};
use serde_json::{json, Value};
use uuid::Uuid;

pub(crate) fn is_update_method(method: &str) -> bool {
    matches!(
        method,
        "session/update"
            | "x.ai/session_notification"
            | "_x.ai/session_notification"
            | "_x.ai/session/update"
    )
}

impl<T: JsonTransport> AcpProvider<T> {
    /// The agent negotiated ACP v2 and its flavor runs native children.
    pub(crate) fn follows_work_state(&self) -> bool {
        self.config.native_child_sessions && self.protocol_generation() == AcpProtocolGeneration::V2
    }

    pub(crate) fn native_subagent_capabilities(&self) -> SubagentCapabilities {
        let follows = self.follows_work_state();
        SubagentCapabilities {
            native_child_sessions: follows,
            stop: follows,
        }
    }

    /// Handles a notification native child sessions own and returns its
    /// first event, queueing the rest. `None` leaves it to the mapping.
    pub(crate) fn route_native_child(
        &mut self,
        incoming: &AcpIncoming,
        session: &ProviderSession,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let AcpIncoming::Notification {
            method,
            params,
            raw: frame,
        } = incoming
        else {
            return Ok(None);
        };
        let Some(source) = params.get("sessionId").and_then(Value::as_str) else {
            return Ok(None);
        };
        if !is_update_method(method) {
            return Ok(None);
        }
        let update = params.get("update").unwrap_or(params);
        let name = update
            .get("sessionUpdate")
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        let root = session.native_thread_id.as_str();
        let changes = if source == root {
            match name {
                "subagent_update" => self.children.child_state(root, root, update),
                "tool_call" | "tool_call_update" => {
                    self.children.observe_call(root, root, update);
                    return Ok(None);
                }
                "state_update" => return Ok(self.root_state(update, session, frame)),
                _ => return Ok(None),
            }
        } else {
            match name {
                "subagent_update" => self.children.child_state(root, source, update),
                "session_message" => self.children.delegation(root, source, update),
                "state_update" => self.children.own_state(root, source, update),
                _ => self.children.frame(source, params.clone()),
            }
        };
        let mut events = Vec::new();
        for change in changes {
            events.extend(self.child_event(change, session, method)?);
        }
        let mut events = events.into_iter();
        let Some(first) = events.next() else {
            return Ok(Some(self.child_event_base(
                session,
                method,
                EventKind::Unknown(format!("acp.native-child.{name}")),
                update.clone(),
                frame.clone(),
            )));
        };
        for event in events {
            self.queue_event(event)?;
        }
        Ok(Some(first))
    }

    /// The root session's work state. Work the agent starts while no turn
    /// runs is a turn of its own: Claude resumes itself once background
    /// work it waited on ends.
    fn root_state(
        &mut self,
        update: &Value,
        session: &ProviderSession,
        frame: &Value,
    ) -> Option<ProviderEvent> {
        if update.get("state").and_then(Value::as_str) == Some("idle") {
            return None;
        }
        self.children.running_seen = true;
        if session.active_turn_id.is_some() || self.prompt_id.is_some() {
            return None;
        }
        let turn_id = format!("turn:{}", Uuid::new_v4());
        if let Some(active) = self.session.as_mut() {
            active.status = SessionStatus::Running;
            active.active_turn_id = Some(turn_id.clone());
        }
        self.children.accepted = true;
        let mut event = self.child_event_base(
            session,
            "session/update",
            EventKind::TurnStarted,
            json!({
                "model": session.model,
                "agentStarted": {"origin": BACKGROUND_CONTINUATION_ORIGIN},
            }),
            frame.clone(),
        );
        event.turn_id = Some(turn_id);
        Some(event)
    }

    /// Marks the prompt accepted, and lets a failed root turn leave the
    /// children that still work running.
    pub(crate) fn settle_root_event(&mut self, event: &mut ProviderEvent) {
        if event.kind == EventKind::Unknown("acp.prompt.accepted".into()) {
            self.children.accepted = true;
            return;
        }
        if event.kind != EventKind::TurnCompleted {
            return;
        }
        if event.payload.get("state") == Some(&json!(TurnStatus::Failed))
            && self.children.any_running()
        {
            event.payload["childTurnsContinue"] = Value::Bool(true);
        }
        if event.payload.get("errorMessage").is_none_or(Value::is_null) {
            if let Some(message) = event
                .raw
                .as_ref()
                .and_then(|raw| raw.payload.pointer("/params/update/error/message"))
                .cloned()
            {
                event.payload["errorMessage"] = message;
            }
        }
        self.children.reset_turn();
    }

    fn child_event_base(
        &self,
        session: &ProviderSession,
        method: &str,
        kind: EventKind,
        payload: Value,
        frame: Value,
    ) -> ProviderEvent {
        let mut event = ProviderEvent::new(
            self.kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            kind,
            payload,
            Some(raw(method, frame)),
        );
        event.turn_id = self
            .session
            .as_ref()
            .and_then(|session| session.active_turn_id.clone());
        event
    }

    fn child_event(
        &mut self,
        change: ChildEvent,
        session: &ProviderSession,
        method: &str,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        match change {
            ChildEvent::Task(kind, payload) => Ok(Some(self.child_event_base(
                session,
                method,
                kind,
                payload,
                Value::Null,
            ))),
            ChildEvent::Prompt {
                item_id,
                call,
                text,
            } => {
                let mut event = self.child_event_base(
                    session,
                    method,
                    EventKind::ItemCompleted,
                    json!({
                        "itemType": "user_message",
                        "status": "completed",
                        "data": {"text": text},
                        "parentToolUseId": call,
                    }),
                    Value::Null,
                );
                event.item_id = Some(item_id);
                Ok(Some(event))
            }
            ChildEvent::Frame {
                session: child,
                call,
                params,
            } => self.child_frame(session, method, &child, &call, params),
        }
    }

    /// A child's item or stream delta, as an item of the session under the
    /// call that delegated to the child. Its other frames (usage, plans,
    /// commands, titles) describe the child alone and are dropped.
    fn child_frame(
        &mut self,
        session: &ProviderSession,
        method: &str,
        child: &str,
        call: &str,
        params: Value,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let root = session.native_thread_id.as_str();
        if let Some(update) = params.get("update") {
            if matches!(
                update.get("sessionUpdate").and_then(Value::as_str),
                Some("tool_call" | "tool_call_update")
            ) {
                self.children.observe_call(root, child, update);
            }
        }
        let provider = self.kind();
        let turn_id = self
            .session
            .as_ref()
            .and_then(|session| session.active_turn_id.clone());
        let context = MappingContext {
            provider: &provider,
            instance_id: &self.config.provider_instance_id,
            thread_id: &session.thread_id,
            native_thread_id: child,
            turn_id: turn_id.as_deref(),
            prompt_id: None,
            prompt_meta_id: None,
            idle_ends_turn: false,
            prompt_acceptance: false,
        };
        let incoming = AcpIncoming::Notification {
            method: method.to_owned(),
            raw: json!({"jsonrpc": "2.0", "method": method, "params": params}),
            params,
        };
        let mut event = map_incoming(incoming, &context)?.event;
        if !matches!(
            event.kind,
            EventKind::ContentDelta
                | EventKind::ItemStarted
                | EventKind::ItemUpdated
                | EventKind::ItemCompleted
        ) {
            return Ok(None);
        }
        let stream = event
            .payload
            .get("streamKind")
            .and_then(Value::as_str)
            .map(str::to_owned);
        if stream.as_deref() == Some("assistant_text") {
            if let Some(delta) = event.payload.get("delta").and_then(Value::as_str) {
                let message = event.item_id.as_deref();
                self.children.record_answer(child, message, delta);
            }
        }
        let native = event
            .item_id
            .clone()
            .or(stream)
            .unwrap_or_else(|| "item".into());
        event.item_id = Some(scoped_id(root, child, &native));
        event.payload["parentToolUseId"] = Value::String(call.to_owned());
        event.payload["subagentThreadId"] = Value::String(child.to_owned());
        Ok(Some(event))
    }

    /// Stops one child session by the task id its events carry: ACP
    /// cancels a session's work by its id, and the child reports its own
    /// cancelled idle.
    pub(crate) async fn stop_native_child(&mut self, task_id: &str) -> Result<(), ProviderError> {
        if !self.follows_work_state() {
            return Err(ProviderError::Unsupported("stopping a sub-agent".into()));
        }
        match self.children.running_child_of(task_id) {
            Err(()) => Err(ProviderError::Validation(
                "the task is not a sub-agent of this session".into(),
            )),
            Ok(None) => Err(ProviderError::InvalidState(
                "the sub-agent is not running".into(),
            )),
            Ok(Some(child)) => self.client.cancel(&child).await.map_err(acp_error),
        }
    }
}
