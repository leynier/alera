use alera_core::runtime::{InboxMessageKind, InboxQuestionStatus};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::message_waiters::{MessageWaiter, WaitKind};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::inbox_requests::inbox_error;
use super::orchestration_validation::{optional_string, wait_timeout_ms};
use super::ServerActor;

const INBOX_WAIT_PAGE: i64 = 50;

/// What `inbox.wait` reports, and whether waiting can stop.
struct InboxWaitState {
    body: Value,
    settled: bool,
}

impl ServerActor {
    /// `inbox.wait` for one question (`questionId`) or for anything new sent
    /// to an inbox (`inbox`). Returns at once when there is news after
    /// `after`, otherwise parks until a reply, a cancellation, or the timeout.
    pub(super) async fn inbox_wait(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let after = payload.get("after").and_then(Value::as_i64).unwrap_or(0);
        let (inbox, question_id) = match optional_string(payload, "questionId") {
            Some(question_id) => {
                let question = self
                    .runtime_store
                    .orchestration_message_by_id(&question_id)
                    .await
                    .map_err(inbox_error)?
                    .filter(|question| {
                        alera_core::runtime::is_external_inbox(&question.from_handle)
                    })
                    .ok_or_else(|| {
                        HostError::conflict(
                            "inbox_question_not_found",
                            format!("No inbox question {question_id}"),
                            json!({}),
                        )
                    })?;
                (question.from_handle, Some(question_id))
            }
            None => (
                optional_string(payload, "inbox")
                    .ok_or_else(|| HostError::format("questionId or inbox is required."))?,
                None,
            ),
        };
        alera_core::runtime::validate_inbox_address(&inbox).map_err(inbox_error)?;
        let state = self
            .inbox_wait_state(&inbox, question_id.as_deref(), after)
            .await?;
        let timeout_ms = wait_timeout_ms(payload);
        if state.settled || payload.get("timeoutMs").and_then(Value::as_u64) == Some(0) {
            return Ok(Some(state.body));
        }
        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            inbox,
            WaitKind::Inbox {
                question_id,
                after_sequence: after,
            },
        );
        self.spawn_wait_timeout(waiter_id, timeout_ms);
        Ok(None)
    }

    pub(super) async fn resolve_inbox_waiter(&mut self, waiter: MessageWaiter) {
        let WaitKind::Inbox {
            question_id,
            after_sequence,
        } = waiter.kind.clone()
        else {
            return;
        };
        match self
            .inbox_wait_state(&waiter.handle, question_id.as_deref(), after_sequence)
            .await
        {
            Ok(state) if !state.settled => self.orchestration_waiters.repark(waiter),
            Ok(state) => {
                self.client_write(waiter.client_id, ok_response(waiter.request_id, state.body))
            }
            Err(error) => {
                self.client_write(waiter.client_id, error_response(waiter.request_id, &error))
            }
        }
    }

    /// The deadline handler reads the store once more, so a reply that landed
    /// at the boundary is returned instead of a bare timeout.
    pub(super) async fn finish_inbox_wait_timeout(
        &mut self,
        waiter: MessageWaiter,
        effective_timeout_ms: u64,
    ) {
        let WaitKind::Inbox {
            question_id,
            after_sequence,
        } = waiter.kind.clone()
        else {
            return;
        };
        let response = match self
            .inbox_wait_state(&waiter.handle, question_id.as_deref(), after_sequence)
            .await
        {
            Ok(mut state) => {
                if !state.settled {
                    state.body["outcome"] = json!("timeout");
                    state.body["timedOut"] = json!(true);
                }
                state.body["waitedMs"] = json!(effective_timeout_ms);
                ok_response(waiter.request_id, state.body)
            }
            Err(error) => error_response(waiter.request_id, &error),
        };
        self.client_write(waiter.client_id, response);
        // The final read can expire rows; clients learn of it like any change.
        self.broadcast_inbox_change().await;
    }

    async fn inbox_wait_state(
        &self,
        inbox: &str,
        question_id: Option<&str>,
        after: i64,
    ) -> HostResult<InboxWaitState> {
        let Some(question_id) = question_id else {
            let messages = self
                .runtime_store
                .inbox_messages_after(inbox, after, INBOX_WAIT_PAGE)
                .await
                .map_err(inbox_error)?;
            let cursor = messages.last().map_or(after, |message| message.sequence);
            self.mark_returned_read(messages.iter().map(|message| message.id.clone()))
                .await?;
            let settled = !messages.is_empty();
            return Ok(InboxWaitState {
                body: json!({
                    "outcome": if settled { "message" } else { "pending" },
                    "inbox": inbox,
                    "messages": messages,
                    "cursor": cursor,
                }),
                settled,
            });
        };
        let question = self
            .runtime_store
            .orchestration_message_by_id(question_id)
            .await
            .map_err(inbox_error)?;
        let Some(question) = question else {
            // Purged while someone was waiting on it.
            return Ok(InboxWaitState {
                body: json!({ "outcome": "purged", "questionId": question_id, "cursor": after }),
                settled: true,
            });
        };
        let thread_id = question.thread_id.clone().unwrap_or(question.id.clone());
        let detail = self
            .runtime_store
            .inbox_thread(&thread_id)
            .await
            .map_err(inbox_error)?
            .ok_or_else(|| HostError::state(format!("inbox thread {thread_id} is missing")))?;
        let status = detail
            .messages
            .iter()
            .find(|entry| entry.message.id == question_id)
            .and_then(|entry| entry.status)
            .unwrap_or(InboxQuestionStatus::Pending);
        let incoming: Vec<_> = detail
            .messages
            .iter()
            .filter(|entry| entry.message.to_handle == inbox && entry.message.sequence > after)
            .cloned()
            .collect();
        let cursor = incoming
            .last()
            .map_or(after, |entry| entry.message.sequence);
        let answers_question = incoming.iter().any(|entry| {
            entry.kind == InboxMessageKind::Reply
                && entry.message.reply_to_id.as_deref() == Some(question_id)
        });
        let outcome = if answers_question {
            "answered"
        } else if !incoming.is_empty() {
            "message"
        } else {
            match status {
                InboxQuestionStatus::Cancelled => "cancelled",
                // A paste in flight still stamps it delivered; its Enter decides.
                InboxQuestionStatus::Expired
                    if !self
                        .orchestration_delivery_in_flight
                        .contains(&detail.thread.recipient) =>
                {
                    "expired"
                }
                _ => "pending",
            }
        };
        self.mark_returned_read(incoming.iter().map(|entry| entry.message.id.clone()))
            .await?;
        Ok(InboxWaitState {
            settled: outcome != "pending",
            body: json!({
                "outcome": outcome,
                "questionId": question_id,
                "status": status,
                "thread": detail.thread,
                "messages": incoming,
                "cursor": cursor,
                "recipient": self.inbox_recipient(&detail.thread.recipient),
            }),
        })
    }

    async fn mark_returned_read(&self, ids: impl Iterator<Item = String>) -> HostResult<()> {
        let ids: Vec<String> = ids.collect();
        self.runtime_store
            .mark_inbox_messages_read(&ids)
            .await
            .map(|_| ())
            .map_err(inbox_error)
    }
}
