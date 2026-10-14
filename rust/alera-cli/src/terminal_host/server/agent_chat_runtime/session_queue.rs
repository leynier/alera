//! Serialized queue edits and delivery into the active native turn.

use alera_provider_protocol::{InteractionMode, TurnInput};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx, SendInput};
use super::ids::{new_id, now};
use super::item_normalization::segment_complete_item;
use super::session::ChatSession;
use super::session_turn_admission::provider_attachments;
use super::wire::{ChatItem, QueueEntry, STREAM_TEXT};

impl ChatSession {
    pub(super) fn edit_queued(&mut self, queue_id: &str, text: String) -> HostResult<Value> {
        let entry = self
            .header
            .queue
            .iter_mut()
            .find(|entry| entry.queue_id == queue_id)
            .ok_or_else(|| conflict("queueNotFound", "That message is no longer queued."))?;
        if text.trim().is_empty() && entry.attachments.is_empty() {
            return Err(HostError::format("a message needs text or attachments"));
        }
        entry.text = text;
        Ok(json!({"updated":true,"queueId":queue_id}))
    }
    pub(super) fn enqueue(&mut self, input: SendInput, ctx: &CallerCtx) -> Value {
        let entry = QueueEntry {
            queue_id: new_id("queue"),
            client_message_id: input.client_message_id,
            text: input.text,
            attachments: input.attachments,
            created_at: now(),
            model: input.model,
            reasoning_effort: input.reasoning_effort,
            interaction_mode: input.interaction_mode,
            runtime_mode_ceiling: input.runtime_mode_ceiling,
            actor: Some(ctx.actor.clone()),
            origin: input.origin,
        };
        let queue_id = entry.queue_id.clone();
        self.header.queue.push(entry);
        json!({"delivery":"queued","queueId":queue_id})
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
            return Ok(json!({"cancelled":true,"marked":marked}));
        }
        let Some(active_turn_id) = self.header.session.active_turn_id.clone() else {
            return Ok(json!({"cancelled":false,"marked":marked}));
        };
        let turn = self
            .deps
            .store
            .agent_chat_turn_for_client_message(&self.header.chat_id, client_message_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if turn
            .as_ref()
            .and_then(|turn| turn.get("turnId"))
            .and_then(Value::as_str)
            != Some(&active_turn_id)
        {
            return Ok(json!({"cancelled":false,"marked":marked}));
        }
        let response = self.interrupt(Some(&active_turn_id)).await?;
        Ok(
            json!({"cancelled":true,"marked":marked,"turnId":active_turn_id,"interrupted":response["interrupted"]}),
        )
    }

    pub(super) async fn promote_queue_to_steer(
        &mut self,
        queue_id: &str,
        turn_id: &str,
        _ctx: &CallerCtx,
    ) -> HostResult<Value> {
        if self.header.session.active_turn_id.as_deref() != Some(turn_id) {
            return Err(conflict("turnNotActive", "That turn is no longer running."));
        }
        let index = self
            .header
            .queue
            .iter()
            .position(|entry| entry.queue_id == queue_id)
            .ok_or_else(|| conflict("queueNotFound", "That message is no longer queued."))?;
        let entry = self.header.queue[index].clone();
        let ctx = CallerCtx {
            scope: "runtime".into(),
            actor: entry.actor.unwrap_or_else(|| "runtime".into()),
            mobile: false,
        };
        let input = SendInput {
            client_message_id: entry.client_message_id,
            text: entry.text,
            attachments: entry.attachments,
            delivery: "steer".into(),
            model: entry.model,
            reasoning_effort: entry.reasoning_effort,
            interaction_mode: entry.interaction_mode,
            runtime_mode_ceiling: entry.runtime_mode_ceiling,
            origin: entry.origin,
        };
        let mut response = self.steer_message(input, &ctx).await?;
        // The actor cannot process turn completion or another queue mutation
        // between native acceptance and removing exactly this entry.
        self.header.queue.remove(index);
        response["queueId"] = json!(queue_id);
        Ok(response)
    }

    pub(super) async fn steer_message(
        &mut self,
        input: SendInput,
        ctx: &CallerCtx,
    ) -> HostResult<Value> {
        if !self.live_caps.as_ref().is_some_and(|caps| caps.steer) {
            return Err(unsupported(
                "This provider cannot take input during a running turn.",
            ));
        }
        let turn_id = self
            .header
            .session
            .active_turn_id
            .clone()
            .ok_or_else(|| conflict("turnNotActive", "There is no running turn to steer."))?;
        let native_turn = self
            .provider_turn_id
            .clone()
            .ok_or_else(|| conflict("turnNotActive", "The native turn has not started."))?;
        if !self.header.pending_requests.is_empty() {
            return Err(conflict(
                "request_pending",
                "Answer the pending request before steering.",
            ));
        }
        let active = self
            .header
            .turns
            .iter()
            .find(|turn| turn.turn_id == turn_id);
        if input
            .model
            .as_deref()
            .is_some_and(|model| active.and_then(|turn| turn.model.as_deref()) != Some(model))
            || input.reasoning_effort.as_deref().is_some_and(|effort| {
                active.and_then(|turn| turn.reasoning_effort.as_deref()) != Some(effort)
            })
        {
            return Err(unsupported(
                "Steering cannot change the running turn's model or effort.",
            ));
        }
        if let Some(ceiling) = input.runtime_mode_ceiling.as_deref() {
            self.ensure_mode_ceiling(ceiling, None)?;
        }
        let stamp = now();
        let mut item = ChatItem::new(new_id("item"), "user_message", &stamp, self.generation);
        item.turn_id = Some(turn_id.clone());
        item.status = "completed".into();
        item.client_message_id = Some(input.client_message_id);
        item.actor = Some(ctx.actor.clone());
        item.normalized.insert(
            "origin".into(),
            input.origin.unwrap_or_else(|| json!({"kind":"user"})),
        );
        item.normalized.insert("delivery".into(), json!("steer"));
        if !input.attachments.is_empty() {
            item.attachments = Some(input.attachments.clone());
        }
        let item_id = item.item_id.clone();
        let segments =
            segment_complete_item(item, STREAM_TEXT, &input.text).map_err(HostError::state)?;
        let provider = self
            .provider
            .as_mut()
            .ok_or_else(|| conflict("turnNotActive", "The provider stopped."))?;
        provider
            .steer_turn(
                TurnInput {
                    thread_id: self.header.chat_id.clone(),
                    input: input.text,
                    attachments: provider_attachments(&input.attachments),
                    model: None,
                    interaction_mode: InteractionMode::Default,
                    options: Default::default(),
                },
                &native_turn,
            )
            .await
            .map_err(|error| match error {
                alera_provider_protocol::ProviderError::Unsupported(message) => {
                    unsupported(message)
                }
                other => HostError::state(other.to_string()),
            })?;
        for segment in segments {
            self.insert_item(segment);
        }
        self.events_armed = true;
        Ok(json!({"delivery":"steered","itemId":item_id,"turnId":turn_id}))
    }
}
