use super::canonical_payload::*;
use super::*;
use claude_agent_sdk::{Message, ResultMessage};

impl ClaudeProvider {
    pub(crate) fn map_message(&mut self, message: Message) -> Vec<ProviderEvent> {
        match message {
            Message::Assistant(message) => self.map_assistant(message),
            Message::StreamEvent(message) => self.map_stream(message),
            Message::Result(message) => self.map_result(message),
            Message::RateLimit(info) => self.map_rate_limit(info),
            Message::System(message) => self.map_system(message),
            Message::User(message) => vec![self.map_user_message(message)],
            Message::ConversationReset(message) => {
                if !message.session_id.is_empty() {
                    self.set_native_thread(&message.session_id);
                }
                vec![self.event(
                    EventKind::ThreadMetadataUpdated,
                    json!({
                        "metadata": {
                            "newConversationId": message.new_conversation_id,
                        }
                    }),
                    self.raw("conversation_reset", message.raw),
                )]
            }
            Message::Unknown(payload) => {
                let message_type = payload
                    .get("type")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
                    .to_owned();
                let warning = json!({
                    "message": "unknown Claude SDK message",
                    "detail": payload.clone(),
                });
                vec![self.event(
                    EventKind::RuntimeWarning,
                    warning,
                    self.raw(message_type, payload),
                )]
            }
        }
    }

    fn map_system(&mut self, message: claude_agent_sdk::SystemMessage) -> Vec<ProviderEvent> {
        let payload = if message.raw.is_null() {
            serde_json::to_value(&message).unwrap_or(Value::Null)
        } else {
            message.raw.clone()
        };
        let subtype = message.subtype.to_ascii_lowercase();
        if matches!(subtype.as_str(), "init" | "initialize") {
            if let Some(native) = text_field(&payload, &["session_id", "sessionId"]) {
                self.set_native_thread(&native);
            }
        }
        let raw = || self.raw(subtype.clone(), payload.clone());
        match subtype.as_str() {
            "init" | "initialize" => {
                let commands = self.init_message_commands(&payload);
                let mut events = vec![self.event(
                    EventKind::SessionConfigured,
                    json!({ "config": payload }),
                    raw(),
                )];
                events.extend(commands);
                events
            }
            "session_state_changed" | "session-state-changed" => {
                let native_state = payload.get("state").and_then(Value::as_str);
                let Some(state) = native_state.and_then(session_state) else {
                    return vec![self.event(
                        EventKind::RuntimeWarning,
                        json!({
                            "message": "unknown Claude session state",
                            "detail": payload,
                        }),
                        raw(),
                    )];
                };
                vec![self.event(
                    EventKind::SessionStateChanged,
                    compact_nulls(json!({
                        "state": state,
                        "reason": text_field(&payload, &["reason", "message"]),
                        "detail": payload,
                    })),
                    raw(),
                )]
            }
            "compact_boundary" | "compactboundary" | "context_compaction" => vec![self.event(
                EventKind::ThreadStateChanged,
                json!({ "state": "compacted", "detail": payload }),
                raw(),
            )],
            _ if subtype.contains("task") => self.map_native_task(&subtype, &payload),
            _ => vec![self.event(
                EventKind::RuntimeWarning,
                json!({
                    "message": "unknown Claude system message",
                    "detail": payload,
                }),
                raw(),
            )],
        }
    }

    fn map_rate_limit(&mut self, info: claude_agent_sdk::RateLimitEvent) -> Vec<ProviderEvent> {
        self.turn_failure.rate_limit(
            &info.rate_limit_info.status,
            info.rate_limit_info.rate_limit_type.as_deref(),
        );
        let payload = serde_json::to_value(&info).unwrap_or(Value::Null);
        let Some(window) = rate_limit_window(&payload) else {
            let warning = json!({
                "message": "Claude rate limit event did not contain a usable window",
                "detail": payload.clone(),
            });
            return vec![self.event(
                EventKind::RuntimeWarning,
                warning,
                self.raw("rate_limit_event", info.raw.clone()),
            )];
        };
        vec![self.event(
            EventKind::AccountRateLimitsUpdated,
            json!({ "limits": { "windows": [window] } }),
            self.raw("rate_limit_event", info.raw),
        )]
    }

    fn map_result(&mut self, message: ResultMessage) -> Vec<ProviderEvent> {
        self.pending_user_prompt = None;
        if !message.session_id.is_empty() {
            self.set_native_thread(&message.session_id);
        }
        let turn_id = self
            .active_turn_id
            .try_lock()
            .ok()
            .and_then(|value| value.clone());
        let interrupted = message.terminal_reason.as_deref().is_some_and(|reason| {
            let reason = reason.to_ascii_lowercase();
            reason.contains("interrupt") || reason.contains("abort") || reason.contains("cancel")
        });
        let failed = message.is_error
            || message
                .errors
                .as_ref()
                .is_some_and(|errors| !errors.is_empty())
            || failure::result_failed_without_error(&message);
        let state = if interrupted {
            "interrupted"
        } else if failed {
            "failed"
        } else {
            "completed"
        };
        let kind = if interrupted {
            EventKind::TurnAborted
        } else {
            EventKind::TurnCompleted
        };
        let mut terminal_payload = if interrupted {
            json!({
                "reason": message
                    .terminal_reason
                    .clone()
                    .unwrap_or_else(|| "interrupt".into()),
            })
        } else {
            json!({ "state": state })
        };
        if !interrupted {
            if let Some(stop_reason) = message
                .terminal_reason
                .as_ref()
                .or(message.stop_reason.as_ref())
            {
                terminal_payload["stopReason"] = Value::String(stop_reason.clone());
            }
            if let Some(usage) = message.usage.clone() {
                terminal_payload["usage"] = usage;
            }
            if let Some(errors) = message.errors.as_ref().filter(|errors| !errors.is_empty()) {
                terminal_payload["errorMessage"] = Value::String(errors.join("; "));
            } else if failed {
                if let Some(result) = message.result.as_ref().filter(|result| !result.is_empty()) {
                    terminal_payload["errorMessage"] = Value::String(result.clone());
                }
            }
            if failed {
                terminal_payload["failureClass"] = json!(self.turn_failure.class(&message));
            }
            if let Some(model_usage) = message.model_usage.clone() {
                terminal_payload["modelUsage"] = model_usage;
            }
            if let Some(total_cost_usd) = message.total_cost_usd {
                terminal_payload["totalCostUsd"] = json!(total_cost_usd);
            }
        }
        if let Some(usage) = message.usage.clone().and_then(normalize_token_usage) {
            terminal_payload["tokenUsage"] = usage;
        }
        if interrupted {
            terminal_payload["reason"] = Value::String(
                message
                    .terminal_reason
                    .clone()
                    .unwrap_or_else(|| "interrupt".into()),
            );
        }
        let event = self.event_for_turn(
            kind,
            turn_id,
            terminal_payload,
            self.raw("result", message.raw),
        );
        if let Some(session) = &mut self.session {
            session.status = SessionStatus::Ready;
            session.active_turn_id = None;
        }
        if let Ok(mut active) = self.active_turn_id.try_lock() {
            *active = None;
        }
        self.turn_failure = Default::default();
        self.streamed_text_message_ids.clear();
        self.streamed_thinking_message_ids.clear();
        self.streamed_text_unscoped = false;
        self.streamed_thinking_unscoped = false;
        self.stream_message_id = None;
        self.open_items.clear();
        self.stream_items.clear();
        vec![event]
    }
}

fn session_state(value: &str) -> Option<&'static str> {
    match value.to_ascii_lowercase().as_str() {
        "starting" | "initializing" => Some("starting"),
        "idle" | "ready" => Some("ready"),
        "running" | "active" => Some("running"),
        "requires_action" | "requiresaction" | "waiting" => Some("waiting"),
        "stopped" | "closed" => Some("stopped"),
        "error" | "failed" => Some("error"),
        _ => None,
    }
}
