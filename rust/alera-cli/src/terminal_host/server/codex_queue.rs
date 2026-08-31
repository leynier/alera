//! Shared queue mutations. Only the host advances delivery.

use alera_core::runtime::{CodexChatDeliveryState, CodexQueueEntry, WorkspaceTabRecord};
use serde_json::{json, Value};

use super::codex_state::{snapshot, tab_thread_id};
use super::codex_thread_identity::ensure_expected_thread;
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

impl ServerActor {
    pub(super) async fn codex_delivery_state(
        &self,
        tab: &WorkspaceTabRecord,
    ) -> HostResult<CodexChatDeliveryState> {
        let thread_id = tab_thread_id(tab).unwrap_or_default();
        if thread_id.is_empty() {
            return Ok(CodexChatDeliveryState::new(&tab.id, ""));
        }
        let mut state = self
            .runtime_store
            .codex_chat_state(&thread_id)
            .await
            .map_err(store_error)?
            .unwrap_or_else(|| CodexChatDeliveryState::new(&tab.id, &thread_id));
        if state.tab_id != tab.id {
            if self
                .codex_tab(&state.tab_id)
                .await
                .ok()
                .is_some_and(|owner| tab_thread_id(&owner).as_deref() == Some(&thread_id))
            {
                return Err(HostError::state(
                    "This conversation is already open in another tab.",
                ));
            }
            state.tab_id = tab.id.clone();
            for entry in &mut state.messages {
                entry.payload["tabId"] = json!(tab.id);
            }
            for operation in &mut state.operations {
                operation.payload["tabId"] = json!(tab.id);
            }
            self.runtime_store
                .save_codex_chat_state(&mut state)
                .await
                .map_err(store_error)?;
        }
        Ok(state)
    }

    pub(super) async fn save_codex_delivery(
        &mut self,
        state: &mut CodexChatDeliveryState,
    ) -> HostResult<()> {
        self.runtime_store
            .save_codex_chat_state(state)
            .await
            .map_err(store_error)?;
        let turn_active = self
            .codex_tab(&state.tab_id)
            .await
            .ok()
            .is_some_and(|tab| super::codex_state::active_turn_id(&snapshot(&tab)).is_some());
        self.refresh_codex_delivery_activity(state, turn_active);
        self.broadcast_authenticated(event("codexQueueChanged", state.snapshot()));
        self.schedule_shutdown_if_idle();
        Ok(())
    }

    pub(super) fn refresh_codex_delivery_activity(
        &mut self,
        state: &CodexChatDeliveryState,
        turn_active: bool,
    ) {
        let active = turn_active
            || self.codex_history_scans.contains(&state.tab_id)
            || state.operations.iter().any(|op| {
                op.kind == "edit"
                    && matches!(
                        op.phase.as_str(),
                        "interrupting" | "rollingBack" | "resending"
                    )
            })
            || state.messages.iter().any(|entry| entry.status == "sending")
            || (!state.paused && state.has_pending());
        if active {
            self.codex_delivery_active.insert(state.tab_id.clone());
        } else {
            self.codex_delivery_active.remove(&state.tab_id);
        }
    }

    pub(super) fn schedule_codex_queue(&self, tab_id: &str) {
        let _ = self.inbox.send(ServerCommand::CodexQueueAdvance {
            tab_id: tab_id.into(),
        });
    }

    pub(super) async fn handle_codex_queue_request(
        &mut self,
        kind: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.handle_codex_queue_request_scanned(kind, payload, None)
            .await
    }

    pub(super) async fn handle_codex_queue_request_scanned(
        &mut self,
        kind: &str,
        payload: &Value,
        scan: Option<&super::codex_history_scans::CodexHistoryScan>,
    ) -> HostResult<Value> {
        let mut retained = None;
        let result = self
            .mutate_codex_queue(kind, payload, &mut retained, scan)
            .await;
        if result.is_err() {
            if let Some(retained) = retained {
                // Persistence may have succeeded before a later step failed.
                // Release only copies that no persisted entry or history owns.
                if let Err(error) = self.release_codex_attachments(&retained).await {
                    tracing::warn!("Could not release uncommitted Codex attachments: {error}");
                }
            }
        }
        result
    }

    async fn mutate_codex_queue(
        &mut self,
        kind: &str,
        payload: &Value,
        retained: &mut Option<Value>,
        scan: Option<&super::codex_history_scans::CodexHistoryScan>,
    ) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self.codex_tab(&tab_id).await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        if kind == "codex.queue.get" {
            return self
                .codex_queue_close_snapshot(&self.codex_delivery_state(&tab).await?)
                .await;
        }
        if self.codex_history_scans.contains(&tab_id) && kind != "codex.queue.pause" {
            return Err(HostError::state(
                "History is being read. Wait before changing this queue.",
            ));
        }
        let mut state = self.codex_delivery_state(&tab).await?;
        let mut canceled_attachments = Vec::new();
        if state.thread_id.is_empty() && kind != "codex.queue.add" && kind != "codex.queue.cancel" {
            return Ok(state.snapshot());
        }
        if state.history_locked() {
            return Err(HostError::state(
                "The conversation is being edited. Wait before changing its queue.",
            ));
        }
        if kind == "codex.queue.add" {
            let id = require_string_key(payload, "clientUserMessageId")?;
            if payload
                .get("expectedHistoryRevision")
                .and_then(Value::as_u64)
                .is_some_and(|revision| revision != state.history_revision)
            {
                return Err(HostError::state(
                    "History changed. Review it before sending this message.",
                ));
            }
            if state.messages.iter().any(|entry| entry.id == id) {
                return Ok(state.snapshot());
            }
            if state
                .messages
                .iter()
                .filter(|entry| !matches!(entry.status.as_str(), "accepted" | "removed"))
                .count()
                >= 100
            {
                return Err(HostError::state("The queue already contains 100 messages."));
            }
            let mut prepared = super::codex_queue_attachments::retain_attachments(
                &self.runtime_dir,
                payload.clone(),
            )
            .await?;
            *retained = Some(prepared.clone());
            let (tab, thread_id, cwd) = self.materialize_codex_thread(&prepared).await?;
            state = self.codex_delivery_state(&tab).await?;
            prepared["expectedThreadId"] = json!(thread_id);
            prepared["cwd"] = json!(cwd);
            state.messages.push(CodexQueueEntry {
                id,
                revision: 0,
                payload: prepared,
                status: "queued".into(),
                error: None,
                turn_id: None,
            });
        } else {
            if let Some(id) = payload.get("operationId").and_then(Value::as_str) {
                if state
                    .operations
                    .iter()
                    .any(|op| op.id == id && op.kind == "queue")
                {
                    return Ok(state.snapshot());
                }
            }
            ensure_queue_revision(&state, payload)?;
            if let Some(id) = payload.get("operationId").and_then(Value::as_str) {
                let mut count = state
                    .operations
                    .iter()
                    .filter(|op| op.kind == "queue")
                    .count();
                state.operations.retain(|op| {
                    if op.kind == "queue" && count >= 128 {
                        count -= 1;
                        false
                    } else {
                        true
                    }
                });
                state
                    .operations
                    .push(alera_core::runtime::CodexChatOperation {
                        id: id.into(),
                        kind: "queue".into(),
                        phase: "completed".into(),
                        payload: json!({"action":kind,"messageId":payload.get("messageId")}),
                        result: None,
                    });
            }
            match kind {
                "codex.queue.cancel" => return self.cancel_codex_tab_queues(state, payload).await,
                "codex.queue.pause" => state.paused = true,
                "codex.queue.resume" => {
                    if state
                        .messages
                        .iter()
                        .any(|entry| matches!(entry.status.as_str(), "sending" | "uncertain"))
                    {
                        return Err(HostError::state(
                            "An earlier delivery must be reconciled before resuming.",
                        ));
                    }
                    if state.messages.iter().any(|entry| {
                        entry.status == "failed" && entry.payload.get("turnId").is_some()
                    }) {
                        return Err(HostError::state("An unsuccessful Steer remains queued. Edit or remove it before resuming."));
                    }
                    for entry in &mut state.messages {
                        if entry.status == "failed" {
                            entry.status = "queued".into();
                            entry.error = None;
                        }
                    }
                    state.paused = false;
                }
                "codex.queue.edit" | "codex.queue.remove" | "codex.queue.steer" => {
                    let id = require_string_key(payload, "messageId")?;
                    let index = state
                        .messages
                        .iter()
                        .position(|entry| entry.id == id)
                        .ok_or_else(|| HostError::state("This queued message no longer exists."))?;
                    let entry = &mut state.messages[index];
                    if !matches!(entry.status.as_str(), "queued" | "failed") {
                        return Err(HostError::state("This message was sent or is being delivered. Your edit has not been applied."));
                    }
                    if kind == "codex.queue.remove" {
                        canceled_attachments.push(entry.payload.clone());
                        entry.status = "removed".into();
                        entry.payload = json!({});
                    } else if kind == "codex.queue.edit" {
                        let text = payload
                            .pointer("/message/draft/text")
                            .or_else(|| payload.pointer("/message/userMessage/text"))
                            .and_then(Value::as_str)
                            .ok_or_else(|| {
                                HostError::format("The edited message text is required.")
                            })?;
                        let mut replacement = entry.payload.clone();
                        super::codex_edit_input::replace_prompt(&mut replacement, text, true)?;
                        replacement.as_object_mut().unwrap().remove("turnId");
                        entry.payload = super::codex_queue_attachments::retain_attachments(
                            &self.runtime_dir,
                            replacement,
                        )
                        .await?;
                        *retained = Some(entry.payload.clone());
                        entry.status = "queued".into();
                        entry.error = None;
                        entry.revision += 1;
                    } else {
                        let turn_id = require_string_key(payload, "turnId")?;
                        if super::codex_state::active_turn_id(&snapshot(&tab)).as_deref()
                            != Some(&turn_id)
                        {
                            state.paused = true;
                            state.messages[index].status = "failed".into();
                            state.messages[index].payload["turnId"] = json!(turn_id);
                            state.messages[index].error = Some("The active turn ended before Steer. Edit or remove this message before resuming.".into());
                            self.save_codex_delivery(&mut state).await?;
                            return Err(HostError::state("The active turn ended. The message remains queued and the queue is paused."));
                        }
                        return self
                            .deliver_codex_queue_entry(state, index, Some(turn_id))
                            .await;
                    }
                }
                "codex.queue.reconcile" => {
                    return self.reconcile_codex_queue_scanned(state, scan).await
                }
                _ => return Err(HostError::format("Unknown Codex queue action.")),
            }
        }
        self.save_codex_delivery(&mut state).await?;
        for payload in canceled_attachments {
            if let Err(error) = self.release_codex_attachments(&payload).await {
                tracing::warn!("Could not release canceled Codex attachments: {error}");
            }
        }
        if kind == "codex.queue.add" {
            if let Some(turn_id) = payload.get("turnId").and_then(Value::as_str) {
                let index = state.messages.len() - 1;
                if super::codex_state::active_turn_id(&snapshot(&tab)).as_deref() == Some(turn_id) {
                    return self
                        .deliver_codex_queue_entry(state, index, Some(turn_id.into()))
                        .await;
                }
                state.messages[index].status = "failed".into();
                state.messages[index].error = Some("The original turn ended. This message was not sent. Use Steer on another active turn or edit it before resuming.".into());
                state.paused = true;
                self.save_codex_delivery(&mut state).await?;
                return Ok(state.snapshot());
            }
        }
        self.schedule_codex_queue(&tab_id);
        Ok(state.snapshot())
    }

    pub(super) async fn guard_codex_history_mutation(
        &mut self,
        payload: &Value,
        stopping: bool,
    ) -> HostResult<()> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let mut state = self.codex_delivery_state(&tab).await?;
        if (!stopping && self.codex_history_scans.contains(&tab.id))
            || state.history_locked()
            || (!stopping && state.messages.iter().any(|entry| entry.status == "sending"))
        {
            return Err(HostError::state(
                "A Codex history or delivery operation is still in progress.",
            ));
        }
        if state.has_pending() || (stopping && !state.thread_id.is_empty()) {
            state.paused = true;
            self.save_codex_delivery(&mut state).await?;
        }
        Ok(())
    }
}

pub(super) fn ensure_queue_revision(
    state: &CodexChatDeliveryState,
    payload: &Value,
) -> HostResult<()> {
    if payload.get("expectedRevision").and_then(Value::as_u64) != Some(state.revision) {
        return Err(HostError::conflict(
            "codexQueueConflict",
            "The queue changed on another client. Review it before trying again.",
            state.snapshot(),
        ));
    }
    Ok(())
}

pub(super) fn store_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
