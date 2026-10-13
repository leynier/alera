//! Sending, queueing, interrupting and finishing turns.

use alera_core::runtime::{AgentChatReceipt, AgentChatReceiptCheck};
use alera_provider_protocol::{InteractionMode, InterruptInput, TurnInput};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx, SendInput};
use super::ids::{new_id, now, receipt_scope};
use super::item_normalization::segment_complete_item;
use super::provider_traits::provider_traits;
use super::session::{ChatSession, DeferredTurn, FLUSH_TEXT_BYTES};
use super::session_turn_admission::{client_message_digest, provider_attachments};
use super::wire::{ChatItem, ChatTurn, QueueEntry, STREAM_TEXT};

const CLIENT_MESSAGE_VERB: &str = "clientMessage";

impl ChatSession {
    fn client_message_scope(&self) -> String {
        receipt_scope(
            &format!("chat:{}", self.header.chat_id),
            CLIENT_MESSAGE_VERB,
        )
    }

    fn validate_turn_model(&self, requested: Option<&str>) -> HostResult<bool> {
        let per_turn_model = self
            .live_caps
            .as_ref()
            .map(|caps| caps.model_switch)
            .unwrap_or_else(|| {
                provider_traits(&self.header.provider).is_some_and(|traits| traits.per_turn_model)
            });
        if let Some(requested) = requested {
            if !per_turn_model && self.header.session.model.as_deref() != Some(requested) {
                return Err(unsupported(format!(
                    "{} cannot switch models during an active chat.",
                    self.header.provider
                )));
            }
        }
        Ok(per_turn_model)
    }

    pub(super) async fn send(&mut self, input: SendInput, ctx: &CallerCtx) -> HostResult<Value> {
        if input.text.trim().is_empty() && input.attachments.is_empty() {
            return Err(HostError::format("a message needs text or attachments"));
        }
        if self
            .deps
            .store
            .is_agent_chat_message_cancelled(&self.header.chat_id, &input.client_message_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            return Err(conflict(
                "request_resolved",
                "This client message was already cancelled.",
            ));
        }
        let scope = self.client_message_scope();
        let digest = client_message_digest(&input);
        if let AgentChatReceiptCheck::Replay(response) = self
            .deps
            .store
            .check_agent_chat_receipt(&scope, &input.client_message_id, &digest)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            return Ok(response);
        }
        self.validate_turn_model(input.model.as_deref())?;
        if input.delivery == "steer" && !self.live_caps.as_ref().is_some_and(|caps| caps.steer) {
            return Err(unsupported(
                "This provider cannot take input during a running turn.",
            ));
        }
        let client_message_id = input.client_message_id.clone();
        let response = if self.must_queue() {
            self.enqueue(input, ctx)
        } else {
            self.start_turn(input, ctx).await?
        };
        // Recorded once the message itself is committed.
        self.message_receipts.push(AgentChatReceipt {
            caller_scope: scope,
            request_id: client_message_id,
            digest,
            receipt: response.clone(),
        });
        Ok(response)
    }

    /// A turn runs, waits on the user, or earlier messages wait ahead.
    fn must_queue(&self) -> bool {
        self.header.session.active_turn_id.is_some()
            || !self.header.pending_requests.is_empty()
            || !self.header.queue.is_empty()
            || self.deferred_turn.is_some()
    }

    fn enqueue(&mut self, input: SendInput, ctx: &CallerCtx) -> Value {
        let entry = QueueEntry {
            queue_id: new_id("queue"),
            client_message_id: input.client_message_id,
            text: input.text,
            attachments: input.attachments,
            created_at: now(),
            model: input.model,
            interaction_mode: input.interaction_mode,
            runtime_mode_ceiling: input.runtime_mode_ceiling,
            actor: Some(ctx.actor.clone()),
            origin: input.origin,
        };
        let queue_id = entry.queue_id.clone();
        self.header.queue.push(entry);
        json!({"delivery": "queued", "queueId": queue_id})
    }

    pub(super) fn cancel_queued(&mut self, queue_id: &str) -> Value {
        let before = self.header.queue.len();
        self.header.queue.retain(|entry| entry.queue_id != queue_id);
        json!({"cancelled": self.header.queue.len() != before})
    }

    pub(super) async fn cancel_message(&mut self, client_message_id: &str) -> HostResult<Value> {
        let marked = self
            .deps
            .store
            .cancel_agent_chat_message(&self.header.chat_id, client_message_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let before = self.header.queue.len();
        self.header
            .queue
            .retain(|entry| entry.client_message_id != client_message_id);
        if self.header.queue.len() != before {
            return Ok(json!({"cancelled": true, "marked": marked}));
        }
        let Some(active_turn_id) = self.header.session.active_turn_id.clone() else {
            return Ok(json!({"cancelled": false, "marked": marked}));
        };
        let turn = self
            .deps
            .store
            .agent_chat_turn_for_client_message(&self.header.chat_id, client_message_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let owns_active_turn = turn
            .as_ref()
            .and_then(|value| value.get("turnId"))
            .and_then(Value::as_str)
            == Some(active_turn_id.as_str());
        if !owns_active_turn {
            return Ok(json!({"cancelled": false, "marked": marked}));
        }
        let response = self.interrupt(Some(&active_turn_id)).await?;
        Ok(json!({
            "cancelled": true,
            "marked": marked,
            "turnId": active_turn_id,
            "interrupted": response.get("interrupted").cloned().unwrap_or(Value::Bool(false)),
        }))
    }

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
        let per_turn_model = self.validate_turn_model(input.model.as_deref())?;
        let resume =
            (self.provider.is_none() && self.startup.is_none()).then(|| self.plan_start(None));
        let stamp = now();
        let turn = ChatTurn {
            turn_id: new_id("turn"),
            status: "running".into(),
            started_at: stamp.clone(),
            completed_at: None,
            error_message: None,
            reason: None,
            model: input
                .model
                .clone()
                .or_else(|| self.header.session.model.clone()),
            provider: self.header.provider.clone(),
            provider_instance_id: self.header.provider_instance_id.clone(),
            generation: self.generation,
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
        let text = self.turn_text(&input.text, &item_id).await?;
        self.header.upsert_turn(turn.clone());
        self.header.session.active_turn_id = Some(turn.turn_id.clone());
        self.set_status("running");
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
        let turn_input = TurnInput {
            thread_id: self.header.chat_id.clone(),
            input: text,
            attachments: provider_attachments(&input.attachments),
            model: input.model.clone().filter(|_| per_turn_model),
            interaction_mode: if interaction == "plan" {
                InteractionMode::Plan
            } else {
                InteractionMode::Default
            },
            options: Default::default(),
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
    /// of a fresh provider session in a chat with history.
    async fn turn_text(&mut self, text: &str, current_item_id: &str) -> HostResult<String> {
        if !self.handoff_pending {
            return Ok(text.to_string());
        }
        let store = self.deps.store.clone();
        let chat_id = self.header.chat_id.clone();
        let prefix = super::handoff::transcript_handoff(&store, &chat_id, current_item_id)
            .await
            .map_err(HostError::state)?;
        Ok(match prefix {
            Some(prefix) => format!("{prefix}{text}"),
            None => text.to_string(),
        })
    }

    pub(super) async fn submit_turn(&mut self, input: TurnInput) {
        let Some(provider) = self.provider.as_mut() else {
            return;
        };
        match provider.send_turn(input).await {
            Ok(result) => {
                self.provider_turn_id = Some(result.turn_id.clone());
                if let Some(app_turn) = self.header.session.active_turn_id.clone() {
                    self.map_native_turn(&result.turn_id, &app_turn).await;
                    if let Some(native) = &result.native_turn_id {
                        self.map_native_turn(native, &app_turn).await;
                    }
                }
                self.handoff_pending = false;
                self.events_armed = true;
            }
            Err(error) => {
                let message = error.to_string();
                let dead = matches!(
                    error,
                    alera_provider_protocol::ProviderError::Closed
                        | alera_provider_protocol::ProviderError::Transport(_)
                );
                self.finish_turn("failed", Some(message.clone()), Some("sendFailed".into()))
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

    /// Ends the running turn and everything that belonged to it.
    pub(super) async fn finish_turn(
        &mut self,
        status: &str,
        error_message: Option<String>,
        reason: Option<String>,
    ) {
        let Some(turn_id) = self.header.session.active_turn_id.take() else {
            return;
        };
        if let Some(turn) = self.header.turn_mut(&turn_id) {
            turn.status = status.into();
            turn.completed_at = Some(now());
            turn.error_message = error_message.clone();
            turn.reason = reason;
        }
        self.provider_turn_id = None;
        self.deferred_turn = None;
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
        if self.provider.is_some() {
            self.set_status("ready");
        } else if matches!(self.header.session.status.as_str(), "running" | "waiting") {
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
