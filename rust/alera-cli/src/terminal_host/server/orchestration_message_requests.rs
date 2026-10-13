//! Agent messaging verbs: `send`, `check`, `reply`, `messages` and `ask`.

use alera_core::runtime::{
    inbox_thread_parties, is_external_inbox, MessageDelivery, NewOrchestrationMessage,
    OrchestrationMessage, OrchestrationMessagePriority, OrchestrationMessageType,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::group_resolution::{
    is_group_address, resolve_group_address,
};
use crate::terminal_host::orchestration::message_formatter::format_messages_for_injection;
use crate::terminal_host::orchestration::message_waiters::WaitKind;

use super::orchestration_message_delivery::{requested_delivery, DeliveryMode};
use super::orchestration_validation::{
    optional_string, parse_message_type, parse_priority, parse_type_filter, prefixed_subject,
    require_string, state_error, wait_timeout_ms,
};
use super::ServerActor;

pub(super) fn generated_group_thread_id() -> String {
    format!("thread_{}", uuid::Uuid::new_v4().simple())
}

pub(super) fn check_response(messages: &[OrchestrationMessage], inject: bool) -> Value {
    let mut response = json!({ "messages": messages });
    if inject {
        response["formatted"] = Value::String(format_messages_for_injection(messages));
    }
    response
}

impl ServerActor {
    // --- send -------------------------------------------------------------

    pub(super) async fn orchestration_send(&mut self, payload: &Value) -> HostResult<Value> {
        let from_handle = require_string(payload, "from")?;
        let to = require_string(payload, "to")?;
        let subject = require_string(payload, "subject")?;
        let body = optional_string(payload, "body").unwrap_or_default();
        let message_type = parse_message_type(payload)?;
        let priority = parse_priority(payload)?;
        let delivery = requested_delivery(payload, MessageDelivery::TurnEnd)?;
        let message_payload = optional_string(payload, "payload");
        let mut explicit_thread_id = optional_string(payload, "threadId");
        if is_external_inbox(&to) {
            explicit_thread_id = self
                .inbox_thread_for_agent_message(&from_handle, &to, explicit_thread_id.as_deref())
                .await?;
        }

        let recipients = resolve_group_address(
            &to,
            &from_handle,
            &self.group_resolution_terminals(),
            &self.agent_presence,
        );
        if recipients.is_empty() {
            return Err(HostError::state(format!("No recipients resolved for {to}")));
        }

        // Group fan-out shares a thread id so replies converge.
        let thread_id = if recipients.len() > 1 {
            explicit_thread_id.or_else(|| Some(generated_group_thread_id()))
        } else {
            explicit_thread_id
        };

        let mut inserted = Vec::new();
        for recipient in &recipients {
            let message = self
                .runtime_store
                .insert_orchestration_message(NewOrchestrationMessage {
                    from_handle: from_handle.clone(),
                    to_handle: recipient.clone(),
                    subject: subject.clone(),
                    body: body.clone(),
                    message_type,
                    priority,
                    thread_id: thread_id.clone(),
                    payload: message_payload.clone(),
                    run_id: optional_string(payload, "runId"),
                    workspace_id: optional_string(payload, "workspaceId"),
                    task_id: optional_string(payload, "taskId"),
                    dispatch_id: optional_string(payload, "dispatchId"),
                    expires_at: optional_string(payload, "expiresAt"),
                    delivery,
                    ..NewOrchestrationMessage::default()
                })
                .await
                .map_err(state_error)?;
            self.queue_inbox_reply_push(&message).await;
            inserted.push(message);
        }

        let mut deliveries = Vec::with_capacity(recipients.len());
        for recipient in &recipients {
            self.notify_message_arrived(recipient, message_type).await;
            if is_external_inbox(recipient) {
                continue;
            }
            let mode = self.deliver_after_send(recipient).await;
            deliveries.push(json!({ "recipient": recipient, "deliveryMode": mode.as_str() }));
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "orchestrationMessagesChanged",
            json!({}),
        ));

        let mut response = json!({
            "messages": inserted,
            "recipients": recipients,
            "deliveries": deliveries,
        });
        if let [only] = deliveries.as_slice() {
            response["deliveryMode"] = only["deliveryMode"].clone();
        }
        Ok(response)
    }

    /// An agent may open a thread with any inbox, or continue one that
    /// already runs between that inbox and itself in either direction. The
    /// message is stored under the thread's root id.
    async fn inbox_thread_for_agent_message(
        &self,
        from: &str,
        to: &str,
        thread_id: Option<&str>,
    ) -> HostResult<Option<String>> {
        let Some(thread_id) = thread_id else {
            return Ok(None);
        };
        let named = self
            .runtime_store
            .orchestration_message_by_id(thread_id)
            .await
            .map_err(state_error)?;
        let root_id = named.map(|message| message.thread_id.unwrap_or(message.id));
        let root = match root_id {
            Some(root_id) => self
                .runtime_store
                .orchestration_message_by_id(&root_id)
                .await
                .map_err(state_error)?,
            None => None,
        };
        match root {
            Some(root) if inbox_thread_parties(&root) == Some((to, from)) => Ok(Some(root.id)),
            _ => Err(HostError::conflict(
                "inbox_thread_mismatch",
                format!(
                    "Thread {thread_id} is not a conversation between {to} and this terminal; omit the thread to start a new one."
                ),
                json!({}),
            )),
        }
    }

    // --- check ------------------------------------------------------------

    pub(super) async fn orchestration_check(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let handle = require_string(payload, "terminal")?;
        let all = payload.get("all").and_then(Value::as_bool).unwrap_or(false);
        let wait = payload
            .get("wait")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let inject = payload
            .get("inject")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let type_filter = parse_type_filter(payload)?;

        if all {
            // `--all` is a read-only view: never marks read, never waits.
            let limit = payload.get("limit").and_then(Value::as_i64).unwrap_or(100);
            let filter = if type_filter.is_empty() {
                None
            } else {
                Some(type_filter.as_slice())
            };
            let messages = self
                .runtime_store
                .all_orchestration_messages_for_handle(&handle, filter, limit)
                .await
                .map_err(state_error)?;
            return Ok(Some(check_response(&messages, inject)));
        }

        let messages = self.consume_unread_messages(&handle, &type_filter).await?;
        if !messages.is_empty() || !wait {
            return Ok(Some(check_response(&messages, inject)));
        }

        // Nothing unread and the caller asked to wait: park the request.
        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            handle,
            WaitKind::Check {
                type_filter,
                inject,
            },
        );
        self.spawn_wait_timeout(waiter_id, wait_timeout_ms(payload));
        Ok(None)
    }

    /// Reads unread messages (optionally filtered) and marks them read.
    pub(super) async fn consume_unread_messages(
        &mut self,
        handle: &str,
        type_filter: &[OrchestrationMessageType],
    ) -> HostResult<Vec<OrchestrationMessage>> {
        let filter = if type_filter.is_empty() {
            None
        } else {
            Some(type_filter)
        };
        let messages = self
            .runtime_store
            .unread_orchestration_messages(handle, filter)
            .await
            .map_err(state_error)?;
        if messages.is_empty() {
            return Ok(messages);
        }
        let ids: Vec<String> = messages.iter().map(|message| message.id.clone()).collect();
        self.runtime_store
            .mark_orchestration_messages_read(&ids)
            .await
            .map_err(state_error)?;
        Ok(messages)
    }

    // --- reply ------------------------------------------------------------

    pub(super) async fn orchestration_reply(&mut self, payload: &Value) -> HostResult<Value> {
        let message_id = require_string(payload, "id")?;
        let body = require_string(payload, "body")?;
        let original = self
            .runtime_store
            .orchestration_message_by_id(&message_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("message not found: {message_id}")))?;
        super::inbox_guards::reject_reply_as_inbox(&original)?;
        self.runtime_store
            .mark_orchestration_messages_read(std::slice::from_ref(&original.id))
            .await
            .map_err(state_error)?;
        let reply = self
            .runtime_store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: original.to_handle.clone(),
                to_handle: original.from_handle.clone(),
                subject: prefixed_subject("Re: ", &original.subject),
                body,
                message_type: OrchestrationMessageType::Status,
                priority: OrchestrationMessagePriority::Normal,
                thread_id: original
                    .thread_id
                    .clone()
                    .or_else(|| Some(original.id.clone())),
                run_id: original.run_id.clone(),
                workspace_id: original.workspace_id.clone(),
                task_id: original.task_id.clone(),
                dispatch_id: original.dispatch_id.clone(),
                reply_to_id: Some(original.id.clone()),
                delivery: MessageDelivery::TurnEnd,
                ..NewOrchestrationMessage::default()
            })
            .await
            .map_err(state_error)?;
        let recipient = reply.to_handle.clone();
        self.queue_inbox_reply_push(&reply).await;
        // Waiters that consume the reply run first, so an answer read through
        // `inbox.wait` or `check --wait` is not pasted into the terminal too.
        self.notify_message_arrived(&recipient, OrchestrationMessageType::Status)
            .await;
        let mut response = json!(reply);
        if !is_external_inbox(&recipient) {
            let mode = self.deliver_after_send(&recipient).await;
            response["deliveryMode"] = json!(mode.as_str());
        }
        Ok(response)
    }

    // --- messages ---------------------------------------------------------

    pub(super) async fn orchestration_messages(&mut self, payload: &Value) -> HostResult<Value> {
        let limit = payload.get("limit").and_then(Value::as_i64).unwrap_or(50);
        let direction =
            optional_string(payload, "direction").unwrap_or_else(|| "inbox".to_string());
        let terminal_filter = optional_string(payload, "terminal");
        let messages = match (terminal_filter.clone(), direction.as_str()) {
            (Some(handle), "outbox") => self
                .runtime_store
                .all_orchestration_messages_from_handle(&handle, limit)
                .await
                .map_err(state_error)?,
            (Some(handle), _) => self
                .runtime_store
                .all_orchestration_messages_for_handle(&handle, None, limit)
                .await
                .map_err(state_error)?,
            (None, "outbox") => {
                return Err(HostError::format("--terminal is required for outbox."));
            }
            (None, _) => self
                .runtime_store
                .recent_orchestration_messages(limit)
                .await
                .map_err(state_error)?,
        };
        Ok(json!({
            "kind": "messages",
            "items": messages,
            "messages": messages,
            "filters": { "terminal": terminal_filter, "direction": direction },
        }))
    }

    // --- ask --------------------------------------------------------------

    /// Asks a terminal a question. A worker's question always goes to its
    /// coordinator, and asking with the dispatch's context token counts as a
    /// worker command (it accepts the dispatch or revives a stalled one).
    pub(super) async fn orchestration_ask(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let from_handle = require_string(payload, "from")?;
        let requested_to = require_string(payload, "to")?;
        let question = require_string(payload, "question")?;
        let delivery = requested_delivery(payload, MessageDelivery::Now)?;
        let mut active_dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(&from_handle)
            .await
            .map_err(state_error)?;
        if active_dispatch.is_some() && optional_string(payload, "contextToken").is_some() {
            let mut touch = payload.clone();
            touch["terminal"] = json!(from_handle);
            active_dispatch = Some(self.touch_worker_dispatch(&touch).await?);
        }
        let to = active_dispatch
            .as_ref()
            .map(|dispatch| dispatch.coordinator_handle.clone())
            .unwrap_or(requested_to);
        if is_group_address(&to) {
            return Err(HostError::state(
                "ask requires a single terminal handle, not a group address",
            ));
        }
        let options = optional_string(payload, "options");
        let body = match &options {
            Some(options) => format!("{question}\nOptions: {options}"),
            None => question.clone(),
        };
        let message = self
            .runtime_store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: from_handle.clone(),
                to_handle: to.clone(),
                subject: prefixed_subject("Question: ", &question),
                body,
                message_type: OrchestrationMessageType::Question,
                priority: OrchestrationMessagePriority::High,
                run_id: active_dispatch
                    .as_ref()
                    .and_then(|dispatch| dispatch.run_id.clone())
                    .or_else(|| optional_string(payload, "runId")),
                workspace_id: active_dispatch
                    .as_ref()
                    .map(|dispatch| dispatch.workspace_id.clone())
                    .or_else(|| optional_string(payload, "workspaceId")),
                task_id: active_dispatch
                    .as_ref()
                    .map(|dispatch| dispatch.task_id.clone())
                    .or_else(|| optional_string(payload, "taskId")),
                dispatch_id: active_dispatch
                    .as_ref()
                    .map(|dispatch| dispatch.id.clone())
                    .or_else(|| optional_string(payload, "dispatchId")),
                expires_at: optional_string(payload, "expiresAt"),
                delivery,
                ..NewOrchestrationMessage::default()
            })
            .await
            .map_err(state_error)?;
        // The question is its own thread root: replies inherit thread_id =
        // message id via `reply`.
        self.notify_message_arrived(&to, OrchestrationMessageType::Question)
            .await;
        let delivery_mode = if is_external_inbox(&to) {
            DeliveryMode::Unavailable
        } else {
            self.deliver_after_send(&to).await
        };
        if payload.get("wait").and_then(Value::as_bool) == Some(false) {
            // The reply reaches the asker's terminal on its next turn, or
            // through `inbox.wait` on this question id.
            return Ok(Some(json!({
                "questionId": message.id,
                "threadId": message.id,
                "to": to,
                "deliveryMode": delivery_mode.as_str(),
            })));
        }

        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            from_handle,
            WaitKind::Ask {
                thread_id: message.id.clone(),
                after_sequence: message.sequence,
            },
        );
        self.spawn_wait_timeout(waiter_id, wait_timeout_ms(payload));
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn generated_group_thread_ids_are_unique() {
        let ids = (0..512)
            .map(|_| generated_group_thread_id())
            .collect::<HashSet<_>>();

        assert_eq!(ids.len(), 512);
    }
}
