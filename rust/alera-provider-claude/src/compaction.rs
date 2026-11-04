//! Claude's compaction lifecycle as one `context_compaction` item, as T3
//! Code's fc21184afb and 0345e852ed:
//!
//! - `system/status` `compacting` starts the item;
//! - `system/status` with `compact_result` settles it as compacted or failed;
//! - a `status: null` frame with neither result nor `permissionMode` means
//!   the compaction stopped;
//! - `compact_boundary` completes it with token counts, or reports a
//!   standalone item for a CLI that sends no status frames;
//! - the turn's result settles an item still running.
//!
//! `ItemStatus` has no stopped value, so a stopped compaction is `failed`
//! with `data.outcome: "stopped"`.

use super::canonical_payload::*;
use super::*;

#[derive(Debug, Clone)]
pub(crate) struct RunningCompaction {
    item_id: String,
    started_at: String,
    trigger: &'static str,
    /// Set once `compact_result: "success"` settled the item, which then
    /// only waits for its boundary's token counts.
    completed_at: Option<String>,
}

struct Settle<'a> {
    kind: EventKind,
    status: &'a str,
    title: &'a str,
    outcome: &'a str,
    detail: Option<String>,
    data: Value,
}

fn now() -> String {
    chrono::Utc::now().to_rfc3339()
}

fn frame_uuid(payload: &Value) -> Option<String> {
    text_field(payload, &["uuid"])
}

impl ClaudeProvider {
    pub(super) fn map_status(&mut self, payload: &Value) -> Vec<ProviderEvent> {
        if let Some(outcome) = payload.get("compact_result").and_then(Value::as_str) {
            let error = text_field(payload, &["compact_error"]);
            self.turn_failure
                .compaction_result(outcome, error.as_deref());
            self.turn_signals.compaction_reported = true;
            return match outcome {
                "success" => {
                    let Some(state) = self
                        .turn_signals
                        .compaction
                        .as_mut()
                        .filter(|state| state.completed_at.is_none())
                    else {
                        return Vec::new();
                    };
                    state.completed_at = Some(now());
                    let state = state.clone();
                    vec![self.compaction_event(
                        &state,
                        Settle {
                            kind: EventKind::ItemCompleted,
                            status: "completed",
                            title: "Context compacted",
                            outcome: "completed",
                            detail: None,
                            data: json!({}),
                        },
                        payload,
                    )]
                }
                "failed" => {
                    let state = self
                        .take_running_compaction()
                        .unwrap_or_else(|| self.new_compaction(frame_uuid(payload)));
                    self.turn_signals.compaction = None;
                    vec![self.compaction_event(
                        &state,
                        Settle {
                            kind: EventKind::ItemCompleted,
                            status: "failed",
                            title: "Context compaction failed",
                            outcome: "failed",
                            detail: error.clone(),
                            data: compact_nulls(json!({ "error": error })),
                        },
                        payload,
                    )]
                }
                _ => Vec::new(),
            };
        }
        if payload.get("status").and_then(Value::as_str) == Some("compacting") {
            if self
                .turn_signals
                .compaction
                .as_ref()
                .is_some_and(|state| state.completed_at.is_none())
            {
                return Vec::new();
            }
            let state = self.new_compaction(frame_uuid(payload));
            self.turn_signals.compaction = Some(state.clone());
            return vec![self.compaction_event(
                &state,
                Settle {
                    kind: EventKind::ItemStarted,
                    status: "inProgress",
                    title: "Compacting context",
                    outcome: "running",
                    detail: None,
                    data: json!({}),
                },
                payload,
            )];
        }
        let stopped = matches!(payload.get("status"), Some(Value::Null))
            && payload.get("permissionMode").is_none();
        if !stopped {
            return Vec::new();
        }
        let Some(state) = self.take_running_compaction() else {
            return Vec::new();
        };
        vec![self.compaction_event(&state, stopped_settle(), payload)]
    }

    pub(super) fn map_compact_boundary(&mut self, payload: Value) -> Vec<ProviderEvent> {
        self.turn_signals.compaction_reported = true;
        let mut state = self
            .turn_signals
            .compaction
            .take()
            .unwrap_or_else(|| self.new_compaction(frame_uuid(&payload)));
        let metadata = payload
            .get("compact_metadata")
            .cloned()
            .unwrap_or(json!({}));
        match metadata.get("trigger").and_then(Value::as_str) {
            Some("manual") => state.trigger = "manual",
            Some("auto") => state.trigger = "auto",
            _ => {}
        }
        let number = |key: &str| metadata.get(key).filter(|value| value.is_u64()).cloned();
        let data = compact_nulls(json!({
            "preTokens": number("pre_tokens"),
            "postTokens": number("post_tokens"),
            "durationMs": number("duration_ms"),
        }));
        let item = self.compaction_event(
            &state,
            Settle {
                kind: EventKind::ItemCompleted,
                status: "completed",
                title: "Context compacted",
                outcome: "completed",
                detail: None,
                data,
            },
            &payload,
        );
        let mut events = vec![item];
        events.extend(self.compaction_context_usage(&payload));
        events.push(self.event(
            EventKind::ThreadStateChanged,
            json!({ "state": "compacted", "detail": payload.clone() }),
            self.raw("compact_boundary", payload),
        ));
        events
    }

    /// Settles a compaction the turn ended during: an interrupted turn
    /// stopped it, any other end means it failed.
    pub(super) fn settle_compaction(
        &mut self,
        interrupted: bool,
        result_text: Option<&str>,
    ) -> Option<ProviderEvent> {
        let state = self.take_running_compaction();
        self.turn_signals.compaction = None;
        let state = state?;
        let settle = if interrupted {
            stopped_settle()
        } else {
            Settle {
                kind: EventKind::ItemCompleted,
                status: "failed",
                title: "Context compaction failed",
                outcome: "failed",
                detail: result_text.map(str::to_owned),
                data: json!({}),
            }
        };
        Some(self.compaction_event(&state, settle, &Value::Null))
    }

    /// Whether this assistant frame is `/compact`'s own echo, which the
    /// compaction item already shows.
    pub(super) fn is_compact_echo(&self, message: &claude_agent_sdk::AssistantMessage) -> bool {
        let echo = |raw: &Value| raw.get("local_command_source").is_some();
        self.turn_signals.compact_command
            && self.turn_signals.compaction_reported
            && message.parent_tool_use_id.is_none()
            && (echo(&message.raw) || message.raw.get("message").is_some_and(echo))
    }

    fn take_running_compaction(&mut self) -> Option<RunningCompaction> {
        if self
            .turn_signals
            .compaction
            .as_ref()
            .is_some_and(|state| state.completed_at.is_none())
        {
            self.turn_signals.compaction.take()
        } else {
            None
        }
    }

    fn new_compaction(&self, uuid: Option<String>) -> RunningCompaction {
        let uuid = uuid.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        RunningCompaction {
            item_id: format!("compaction:{uuid}"),
            started_at: now(),
            trigger: if self.turn_signals.compact_command {
                "manual"
            } else {
                "auto"
            },
            completed_at: None,
        }
    }

    fn compaction_event(
        &self,
        state: &RunningCompaction,
        settle: Settle<'_>,
        frame: &Value,
    ) -> ProviderEvent {
        let mut data = json!({
            "trigger": state.trigger,
            "outcome": settle.outcome,
            "startedAt": state.started_at,
        });
        if settle.kind == EventKind::ItemCompleted {
            data["completedAt"] = json!(state.completed_at.clone().unwrap_or_else(now));
        }
        if let (Some(data), Some(extra)) = (data.as_object_mut(), settle.data.as_object()) {
            data.extend(extra.clone());
        }
        let mut payload = json!({
            "itemType": "context_compaction",
            "status": settle.status,
            "title": settle.title,
            "data": data,
        });
        if let Some(detail) = settle
            .detail
            .as_deref()
            .map(str::trim)
            .filter(|detail| !detail.is_empty())
        {
            payload["detail"] = json!(detail);
        }
        let message_type = frame
            .get("subtype")
            .and_then(Value::as_str)
            .unwrap_or("result")
            .to_owned();
        let mut event = self.event(settle.kind, payload, self.raw(message_type, frame.clone()));
        event.item_id = Some(state.item_id.clone());
        event.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: None,
        });
        event
    }
}

fn stopped_settle() -> Settle<'static> {
    Settle {
        kind: EventKind::ItemCompleted,
        status: "failed",
        title: "Context compaction stopped",
        outcome: "stopped",
        detail: None,
        data: json!({}),
    }
}
