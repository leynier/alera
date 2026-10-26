//! Starting, interrupting and finishing turns, and draining the queue.

use alera_provider_protocol::{FailureClass, InteractionMode, InterruptInput, TurnInput};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx, SendInput};
use super::ids::{new_id, now};
use super::item_normalization::segment_complete_item;
use super::provider_traits::provider_traits;
use super::session::{ChatSession, DeferredTurn, FLUSH_TEXT_BYTES};
use super::session_turn_admission::provider_attachments;
use super::wire::{ChatItem, ChatTurn, STREAM_TEXT};

#[cfg(test)]
#[path = "session_turn_end_tests.rs"]
mod tests;

/// How a turn ended.
pub(super) struct TurnEnd {
    pub status: String,
    pub error_message: Option<String>,
    pub reason: Option<String>,
    pub failure_class: FailureClass,
    /// The provider's native child turns outlive this failed turn and report
    /// their own ends; otherwise the turn's awaited work ends with it.
    pub child_turns_continue: bool,
}

impl TurnEnd {
    pub(super) fn new(status: &str, error_message: Option<String>, reason: Option<String>) -> Self {
        Self {
            status: status.into(),
            error_message,
            reason,
            failure_class: FailureClass::Unknown,
            child_turns_continue: false,
        }
    }
}

impl ChatSession {
    pub(super) async fn start_turn(
        &mut self,
        input: SendInput,
        ctx: &CallerCtx,
    ) -> HostResult<Value> {
        if let Some(ceiling) = input.runtime_mode_ceiling.as_deref() {
            let requested_rank =
                crate::terminal_host::server::chat_orchestration::authorization::mode_rank(
                    &self.header.session.runtime_mode,
                )
                .ok_or_else(|| HostError::format("unknown current runtime mode"))?;
            let ceiling_rank =
                crate::terminal_host::server::chat_orchestration::authorization::mode_rank(ceiling)
                    .ok_or_else(|| HostError::format("unknown runtime mode ceiling"))?;
            if requested_rank > ceiling_rank {
                return Err(conflict(
                    "mode_ceiling",
                    "The chat runtime mode exceeds the caller's mode ceiling.",
                ));
            }
        }
        let traits = provider_traits(&self.header.provider);
        let interaction = input
            .interaction_mode
            .clone()
            .unwrap_or_else(|| self.header.session.interaction_mode.clone());
        if !traits
            .as_ref()
            .is_some_and(|traits| traits.interaction_modes.contains(&interaction.as_str()))
        {
            return Err(unsupported(format!(
                "{} does not support the {interaction} interaction mode.",
                self.header.provider
            )));
        }
        if !input.attachments.is_empty()
            && !traits
                .as_ref()
                .is_some_and(|traits| traits.images || traits.files)
        {
            return Err(unsupported(format!(
                "{} does not accept attachments.",
                self.header.provider
            )));
        }
        let per_turn_model = self.apply_turn_configuration(&input).await?;
        self.derive_first_send_title(&input.text).await;
        let resume =
            (self.provider.is_none() && self.startup.is_none()).then(|| self.plan_start(None));
        let stamp = now();
        let turn = ChatTurn {
            turn_id: new_id("turn"),
            status: "running".into(),
            started_at: stamp.clone(),
            completed_at: None,
            error_message: None,
            failure_class: None,
            reason: None,
            model: input
                .model
                .clone()
                .or_else(|| self.header.session.model.clone()),
            reasoning_effort: self.header.session.reasoning_effort.clone(),
            provider: self.header.provider.clone(),
            provider_instance_id: self.header.provider_instance_id.clone(),
            generation: self.generation,
            origin: None,
        };
        let mut item = ChatItem::new(new_id("item"), "user_message", &stamp, self.generation);
        item.turn_id = Some(turn.turn_id.clone());
        item.status = "completed".into();
        item.client_message_id = Some(input.client_message_id.clone());
        item.actor = Some(ctx.actor.clone());
        item.normalized.insert(
            "origin".into(),
            input
                .origin
                .clone()
                .unwrap_or_else(|| json!({"kind": "user"})),
        );
        if !input.attachments.is_empty() {
            item.attachments = Some(input.attachments.clone());
        }
        let item_id = item.item_id.clone();
        let mut text_items =
            segment_complete_item(item, STREAM_TEXT, &input.text).map_err(|error| {
                HostError::state(format!("The message could not be saved: {error}"))
            })?;
        let segment_count = text_items.len();
        if segment_count > 1 {
            text_items[0]
                .normalized
                .insert("segmentCount".into(), Value::from(segment_count as u64));
        }
        let segmented = segment_count > 1;
        let (text, handed_off) = self.turn_text(&input.text, &item_id).await?;
        let handoff = handed_off.then(|| self.handoff_marker(&turn, &stamp));
        self.header.upsert_turn(turn.clone());
        self.header.session.active_turn_id = Some(turn.turn_id.clone());
        self.set_status("running");
        if let Some(handoff) = handoff {
            self.insert_item(handoff);
        }
        for item in text_items.drain(..) {
            self.insert_item(item);
            if self.pending.estimated_bytes(&self.items) >= FLUSH_TEXT_BYTES {
                self.flush().await.map_err(|error| {
                    HostError::state(format!("The message could not be saved: {error}"))
                })?;
            }
        }
        if segmented {
            self.flush().await.map_err(|error| {
                HostError::state(format!("The message could not be saved: {error}"))
            })?;
        }
        let mut options = super::session_effort::turn_effort_options(
            &self.header.provider,
            self.header.session.reasoning_effort.as_deref(),
        );
        if self.header.provider == "claudeAgent" {
            options.insert("appUserItemId".into(), json!(item_id));
        }
        let turn_input = TurnInput {
            thread_id: self.header.chat_id.clone(),
            input: text,
            attachments: provider_attachments(&input.attachments),
            model: self.header.session.model.clone().filter(|_| per_turn_model),
            interaction_mode: if interaction == "plan" {
                InteractionMode::Plan
            } else {
                InteractionMode::Default
            },
            options,
        };
        if self.provider.is_some() {
            self.submit_turn(turn_input).await;
        } else {
            self.deferred_turn = Some(DeferredTurn { input: turn_input });
            if let Some(resume) = resume {
                self.spawn_startup(resume).await;
            }
        }
        Ok(json!({"delivery": "started", "itemId": item_id, "turnId": turn.turn_id}))
    }

    /// The user's text, preceded by the transcript handoff on the first turn
    /// of a fresh provider session in a chat with history, and whether the
    /// transcript was prepended.
    async fn turn_text(&mut self, text: &str, current_item_id: &str) -> HostResult<(String, bool)> {
        // Work merged back from a fork rides ahead of the next prompt.
        let text = match self.take_merge_back_context().await {
            Some(merged) => format!("{merged}{text}"),
            None => text.to_string(),
        };
        if !self.handoff_pending {
            return Ok((text, false));
        }
        let store = self.deps.store.clone();
        let chat_id = self.header.chat_id.clone();
        let prefix = super::handoff::transcript_handoff(&store, &chat_id, current_item_id)
            .await
            .map_err(HostError::state)?;
        Ok(match prefix {
            Some(prefix) => (format!("{prefix}{text}"), true),
            None => (text, false),
        })
    }

    pub(super) async fn submit_turn(&mut self, input: TurnInput) {
        let Some(provider) = self.provider.as_mut() else {
            return;
        };
        match provider.send_turn(input).await {
            Ok(result) => {
                self.provider_turn_id = Some(
                    result
                        .native_turn_id
                        .clone()
                        .unwrap_or_else(|| result.turn_id.clone()),
                );
                if let Some(app_turn) = self.header.session.active_turn_id.clone() {
                    self.map_native_turn(&result.turn_id, &app_turn).await;
                    if let Some(native) = &result.native_turn_id {
                        self.map_native_turn(native, &app_turn).await;
                    }
                    self.settle_handoff(&app_turn, "completed");
                }
                self.handoff_pending = false;
                self.events_armed = true;
                self.remember_first_send().await;
            }
            Err(error) => {
                let message = error.to_string();
                let dead = matches!(
                    error,
                    alera_provider_protocol::ProviderError::Closed
                        | alera_provider_protocol::ProviderError::Transport(_)
                );
                self.end_turn(TurnEnd {
                    failure_class: error.failure_class(),
                    ..TurnEnd::new("failed", Some(message.clone()), Some("sendFailed".into()))
                })
                .await;
                if dead {
                    self.provider_failed(message).await;
                }
            }
        }
    }

    pub(super) async fn interrupt(&mut self, turn_id: Option<&str>) -> HostResult<Value> {
        let Some(active) = self.header.session.active_turn_id.clone() else {
            return Ok(json!({"acknowledged": true, "interrupted": false}));
        };
        if turn_id.is_some_and(|id| id != active) {
            return Err(conflict("turnNotActive", "That turn is no longer running."));
        }
        if self.deferred_turn.take().is_some() || self.provider.is_none() {
            self.cancel_startup().await;
            self.revoke_launch_credentials("interrupted").await;
            self.finish_turn("interrupted", None, Some("interrupted".into()))
                .await;
            return Ok(json!({"acknowledged": true, "interrupted": true}));
        }
        let provider = self.provider.as_mut().expect("provider is running");
        provider
            .interrupt(InterruptInput {
                thread_id: self.header.chat_id.clone(),
                turn_id: self.provider_turn_id.clone(),
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.events_armed = true;
        Ok(json!({"acknowledged": true, "interrupted": true}))
    }

    pub(super) async fn finish_turn(
        &mut self,
        status: &str,
        error_message: Option<String>,
        reason: Option<String>,
    ) {
        self.end_turn(TurnEnd::new(status, error_message, reason))
            .await;
    }

    /// Ends the running turn and everything that belonged to it.
    pub(super) async fn end_turn(&mut self, end: TurnEnd) {
        let TurnEnd {
            status,
            error_message,
            reason,
            failure_class,
            child_turns_continue,
        } = end;
        let status = status.as_str();
        let Some(turn_id) = self.header.session.active_turn_id.take() else {
            return;
        };
        if let Some(turn) = self.header.turn_mut(&turn_id) {
            turn.status = status.into();
            turn.completed_at = Some(now());
            turn.error_message = error_message.clone();
            turn.failure_class =
                (status == "failed" && !failure_class.is_unknown()).then_some(failure_class);
            turn.reason = reason;
        }
        self.provider_turn_id = None;
        self.deferred_turn = None;
        // A marker still pending here never reached a provider.
        self.settle_handoff(&turn_id, "failed");
        let open: Vec<String> = self
            .items
            .values()
            .filter(|item| item.turn_id.as_deref() == Some(turn_id.as_str()))
            .filter(|item| item.status == "inProgress" || item.streaming)
            .map(|item| item.item_id.clone())
            .collect();
        for item_id in open {
            if let Some(item) = self.items.get_mut(&item_id) {
                item.streaming = false;
                if item.status == "inProgress" {
                    item.status = if status == "completed" {
                        "completed"
                    } else {
                        "failed"
                    }
                    .into();
                }
                item.updated_at = now();
            }
            self.pending.item(&item_id);
        }
        self.expire_requests_of_turn(Some(&turn_id));
        self.end_awaited_work_of(&turn_id, status, child_turns_continue);
        if self.provider.is_some() {
            self.set_status(self.idle_status());
        } else if matches!(
            self.header.session.status.as_str(),
            "running" | "waiting" | "starting"
        ) {
            self.set_status("stopped");
        }
        if status == "failed" {
            self.header.session.error_message = error_message;
        }
        let _ = self.flush().await;
        self.items
            .retain(|_, item| item.turn_id.as_deref() != Some(turn_id.as_str()));
    }

    /// Starts the oldest queued message once nothing runs.
    pub(super) async fn drain_queue(&mut self) {
        if self.header.session.active_turn_id.is_some()
            || !self.header.pending_requests.is_empty()
            || self.startup.is_some()
            || self.header.queue.is_empty()
        {
            return;
        }
        if self.provider.is_none() && self.header.session.status == "error" {
            return;
        }
        let entry = self.header.queue.remove(0);
        let ctx = CallerCtx {
            scope: "runtime".into(),
            actor: entry.actor.clone().unwrap_or_else(|| "runtime".into()),
            mobile: false,
        };
        let input = SendInput {
            client_message_id: entry.client_message_id,
            text: entry.text,
            attachments: entry.attachments,
            delivery: "auto".into(),
            model: entry.model,
            reasoning_effort: entry.reasoning_effort,
            interaction_mode: entry.interaction_mode,
            runtime_mode_ceiling: entry.runtime_mode_ceiling,
            origin: entry.origin,
        };
        let failed_input = input.clone();
        if let Err(error) = self.start_turn(input, &ctx).await {
            tracing::warn!(chat_id = %self.header.chat_id, error = %error, "queued agent chat message failed to start");
            self.record_rejected_queued_turn(failed_input, &ctx, error.to_string())
                .await;
        }
        let _ = self.flush().await;
    }

    pub(super) fn insert_item(&mut self, item: ChatItem) {
        let item_id = item.item_id.clone();
        self.items.insert(item_id.clone(), item);
        self.pending.item(&item_id);
        self.has_items = true;
    }
}
