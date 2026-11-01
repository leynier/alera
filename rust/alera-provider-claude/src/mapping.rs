use super::canonical_payload::*;
use super::*;
use claude_agent_sdk::{Message, ResultMessage};

impl ClaudeProvider {
    pub(crate) fn map_message(&mut self, message: Message) -> Vec<ProviderEvent> {
        if let Message::Assistant(message) = message {
            if self.is_compact_echo(&message) {
                return Vec::new();
            }
            let mut events = Vec::new();
            if message.error.is_none() {
                events.extend(self.recover_api_retry());
            }
            events.extend(self.map_assistant(message));
            return events;
        }
        // A held thinking block shows before any other frame.
        let mut events = self.release_held_thinking();
        events.extend(self.map_other_message(message));
        events
    }

    fn map_other_message(&mut self, message: Message) -> Vec<ProviderEvent> {
        match message {
            Message::Assistant(message) => self.map_assistant(message),
            Message::StreamEvent(message) => self.map_stream(message),
            Message::Result(message) => self.map_result(message),
            Message::RateLimit(info) => self.map_rate_limit(info),
            Message::System(message) => self.map_system(message),
            Message::User(message) => {
                let handles = self.workflow_handles_event(&message);
                let mut events = vec![self.map_user_message(message)];
                events.extend(handles);
                events
            }
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
        let permission_notice = matches!(subtype.as_str(), "init" | "initialize")
            .then(|| self.adopt_reported_permission_mode(&payload))
            .flatten();
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
                events.extend(permission_notice);
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
            "compact_boundary" | "compactboundary" | "context_compaction" => {
                self.map_compact_boundary(payload)
            }
            "status" => self.map_status(&payload),
            "informational" => self.map_informational(&payload),
            "api_retry" => self.map_api_retry(&payload),
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

    /// A blocked assistant frame repeats its limit in
    /// `api_error_params.rate_limit_info` while the CLI throttles unchanged
    /// `rate_limit_event`s, so its reset time still reaches the usage view.
    pub(super) fn assistant_rate_limit(&mut self, raw: &Value) -> Option<ProviderEvent> {
        let info = [raw, raw.get("message").unwrap_or(&Value::Null)]
            .into_iter()
            .find_map(|frame| frame.get("api_error_params")?.get("rate_limit_info"))
            .filter(|info| blocked_without_overage(info))?;
        self.turn_failure.rate_limit(
            "rejected",
            info.get("rateLimitType").and_then(Value::as_str),
        );
        let window = rate_limit_window(info)?;
        Some(self.event(
            EventKind::AccountRateLimitsUpdated,
            json!({ "limits": { "windows": [window] } }),
            self.raw("assistant", raw.clone()),
        ))
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
        // A /compact the usage limit stopped ends with a success result.
        let limited_compaction = (!interrupted)
            .then(|| self.turn_failure.limited_compaction(&message))
            .flatten()
            .map(|error| error.map(str::to_owned));
        let failed = failure::result_failed(&message) || limited_compaction.is_some();
        let class = failed.then(|| self.turn_failure.class(&message));
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
            if let Some(class) = class {
                let error = limited_compaction
                    .clone()
                    .flatten()
                    .or_else(|| failure::result_error_message(&message, class));
                if let Some(error) = error {
                    terminal_payload["errorMessage"] = Value::String(error);
                }
                terminal_payload["failureClass"] = json!(class);
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
        self.attach_context_usage(&mut terminal_payload, message.model_usage.as_ref());
        // Items the turn ended during settle before its terminal event.
        let mut events = Vec::new();
        events.extend(self.settle_compaction(interrupted, message.result.as_deref()));
        events.extend(self.settle_api_retry(interrupted, class));
        events.push(self.event_for_turn(
            kind,
            turn_id,
            terminal_payload,
            self.raw("result", message.raw),
        ));
        if let Some(session) = &mut self.session {
            session.status = SessionStatus::Ready;
            session.active_turn_id = None;
        }
        if let Ok(mut active) = self.active_turn_id.try_lock() {
            *active = None;
        }
        self.turn_failure = Default::default();
        self.turn_signals = Default::default();
        self.streamed_text_message_ids.clear();
        self.streamed_thinking_message_ids.clear();
        self.streamed_text_unscoped = false;
        self.streamed_thinking_unscoped = false;
        self.stream_message_id = None;
        self.open_items.clear();
        self.stream_items.clear();
        events
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
