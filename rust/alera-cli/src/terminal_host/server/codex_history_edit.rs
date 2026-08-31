//! Rollback is isolated here because upstream deprecates it. Never emulate it
//! by editing rollout files or changing the identity of the conversation.

use super::codex_history_actions::{read_turns, unsupported};
use super::codex_queue::store_error;
use super::codex_state::{set_thread_and_snapshot, snapshot, tab_thread_id};
use super::codex_tab_lifecycle::active_cwd;
use super::codex_thread_identity::ensure_expected_thread;
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;
use alera_core::runtime::CodexChatOperation;
use serde_json::{json, Value};
use std::time::Duration;

const ROLLBACK_RECEIPT_PERSIST_FAILED: &str = "codex.rollback_receipt_persist_failed";

impl ServerActor {
    pub(super) async fn edit_codex_history(&mut self, payload: &Value) -> HostResult<Value> {
        self.edit_codex_history_scanned(payload, None).await
    }

    pub(super) async fn edit_codex_history_scanned(
        &mut self,
        payload: &Value,
        scan: Option<&super::codex_history_scans::CodexHistoryScan>,
    ) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let mut state = self.codex_delivery_state(&tab).await?;
        let operation_id = require_string_key(payload, "operationId")?;
        if let Some(operation) = state
            .operations
            .iter()
            .find(|op| op.id == operation_id)
            .cloned()
        {
            if operation.kind != "edit" {
                return Err(HostError::state(
                    "Operation identity belongs to another action.",
                ));
            }
            super::codex_edit_input::validate_retry(&operation.payload, payload)?;
            if operation.phase == "uncertain" {
                return self
                    .reconcile_codex_history_edit_scanned(&tab.id, &operation_id, scan)
                    .await;
            }
            if matches!(operation.phase.as_str(), "rolledBack" | "resendFailed") {
                self.finish_codex_history_edit(
                    &tab.id,
                    &operation_id,
                    Ok(operation.result.unwrap_or(json!({}))),
                )
                .await;
                return Ok(self.codex_delivery_state(&tab).await?.snapshot());
            }
            return Ok(state.snapshot());
        }
        if state
            .messages
            .iter()
            .any(|entry| entry.status == "uncertain")
        {
            return Err(HostError::state(
                "Reconcile uncertain deliveries before editing conversation history.",
            ));
        }
        if state.history_locked() || state.messages.iter().any(|entry| entry.status == "sending") {
            return Err(HostError::state(
                "Another conversation operation is still in progress.",
            ));
        }
        if payload
            .get("expectedHistoryRevision")
            .and_then(Value::as_u64)
            != Some(state.history_revision)
        {
            return Err(HostError::state(
                "The conversation was edited on another client. Review it before trying again.",
            ));
        }
        let turn_id = require_string_key(payload, "turnId")?;
        let text = payload
            .get("text")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::format("The edited text is required."))?
            .to_string();
        let server = self
            .ensure_codex_server(active_cwd(&tab).as_deref())
            .await?;
        let scanned =
            super::codex_history_scans::scanned_history(&server, &state.thread_id, scan, true)
                .await?;
        let metadata = scanned.metadata;
        if metadata
            .pointer("/thread/historyMode")
            .and_then(Value::as_str)
            == Some("paginated")
        {
            let reason = "This Codex version does not support editing paginated conversations. The original history has not been changed.";
            state.history_edit_unavailable = Some(reason.into());
            self.save_codex_delivery(&mut state).await?;
            return Err(HostError::state(reason));
        }
        let turns = scanned.turns;
        let index = turns
            .iter()
            .position(|turn| turn["id"].as_str() == Some(&turn_id))
            .ok_or_else(|| {
                HostError::state("The original turn is no longer in this conversation.")
            })?;
        let user = turns[index]
            .get("items")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .find(|item| item["type"] == "userMessage")
            .ok_or_else(|| {
                HostError::state("The original user input cannot be reconstructed safely.")
            })?;
        if let Some(item_id) = payload.get("itemId").and_then(Value::as_str) {
            if user["id"].as_str() != Some(item_id) {
                return Err(HostError::state(
                    "Only the initial user message of a turn can be edited.",
                ));
            }
        }
        let original = state.messages.iter().find(|entry| {
            entry.turn_id.as_deref() == Some(&turn_id) && entry.payload.get("turnId").is_none()
        });
        let mut replacement = original
            .map(|entry| entry.payload.clone())
            .unwrap_or_else(|| {
                json!({
                    "tabId": tab.id, "expectedThreadId": state.thread_id,
                    "input": user.get("content").cloned().unwrap_or(json!([])),
                    "userMessage": {"text": text},
                })
            });
        super::codex_edit_input::replace_prompt(&mut replacement, &text, original.is_some())?;
        replacement["clientUserMessageId"] = json!(operation_id);
        replacement["editTargetTurnId"] = json!(turn_id);
        replacement["editTargetItemId"] = user["id"].clone();
        replacement["editOriginalTurnIds"] =
            json!(turns.iter().map(|turn| &turn["id"]).collect::<Vec<_>>());
        replacement =
            super::codex_queue_attachments::retain_attachments(&self.runtime_dir, replacement)
                .await?;
        state.paused = true;
        state.operations.push(CodexChatOperation {
            id: operation_id.clone(),
            kind: "edit".into(),
            phase: "interrupting".into(),
            payload: replacement,
            result: None,
        });
        self.save_codex_delivery(&mut state).await?;
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let tab_id = tab.id;
        let thread_id = state.thread_id.clone();
        let response_id = operation_id.clone();
        tokio::spawn(async move {
            let result = async {
                let before = server.request("thread/read", json!({"threadId": thread_id, "includeTurns": true})).await?;
                if let Some(active) = before.pointer("/thread/turns").and_then(Value::as_array).into_iter().flatten().find(|turn| turn["status"] == "inProgress") {
                    server.request("turn/interrupt", json!({"threadId": thread_id, "turnId": active["id"]})).await?;
                    tokio::time::timeout(Duration::from_secs(30), async {
                        loop {
                            let read = server.request("thread/read", json!({"threadId": thread_id, "includeTurns": true})).await?;
                            if !read.pointer("/thread/turns").and_then(Value::as_array).into_iter().flatten().any(|turn| turn["status"] == "inProgress") { return Ok::<_, HostError>(()); }
                            tokio::time::sleep(Duration::from_millis(100)).await;
                        }
                    }).await.map_err(|_| HostError::state("Codex did not confirm that the active turn stopped. History was not edited."))??;
                }
                let current = read_turns(&server, &thread_id).await?;
                let position = current.iter().position(|turn| turn["id"].as_str() == Some(&turn_id))
                    .ok_or_else(|| HostError::state("The original turn disappeared before rollback."))?;
                if current.iter().map(|turn| &turn["id"]).ne(turns.iter().map(|turn| &turn["id"])) {
                    return Err(HostError::state("New turns arrived. Confirm the edit again against the current history."));
                }
                state.operations.last_mut().unwrap().phase = "rollingBack".into();
                store.save_codex_chat_state(&mut state).await.map_err(store_error)?;
                let result = server.request("thread/rollback", json!({"threadId": thread_id, "numTurns": current.len() - position})).await.map_err(|error| {
                    if unsupported(&error) { HostError::state("This Codex version no longer supports editing history with rollback.") } else { error }
                })?;
                state.discarded_turn_ids.extend(current[position..].iter().filter_map(|turn| turn["id"].as_str().map(str::to_string)));
                state.history_revision += 1;
                let op = state.operations.last_mut().unwrap(); op.phase = "rolledBack".into(); op.result = Some(result.clone());
                store.save_codex_chat_state(&mut state).await.map_err(|error| HostError::conflict(
                    ROLLBACK_RECEIPT_PERSIST_FAILED,
                    format!("Codex rolled back history, but its recovery state could not be saved. Reconcile before continuing: {error}"),
                    Value::Null,
                ))?;
                Ok(result)
            }.await;
            let _ = inbox.send(ServerCommand::CodexEditFinished {
                tab_id,
                operation_id,
                result,
            });
        });
        Ok(
            json!({"accepted": true, "operationId": response_id, "queue": self.codex_delivery_state(&self.codex_tab(&require_string_key(payload, "tabId")?).await?).await?.snapshot()}),
        )
    }

    pub(super) async fn finish_codex_history_edit(
        &mut self,
        tab_id: &str,
        operation_id: &str,
        result: HostResult<Value>,
    ) {
        if let Err(error) = self
            .finish_codex_history_edit_inner(tab_id, operation_id, result)
            .await
        {
            tracing::warn!(tab_id, "Codex edit completion failed: {error}");
        }
    }

    async fn finish_codex_history_edit_inner(
        &mut self,
        tab_id: &str,
        operation_id: &str,
        result: HostResult<Value>,
    ) -> HostResult<()> {
        let tab = self.codex_tab(tab_id).await?;
        let mut state = self.codex_delivery_state(&tab).await?;
        let index = state
            .operations
            .iter()
            .position(|op| op.id == operation_id)
            .ok_or_else(|| {
                HostError::state("The edit operation no longer belongs to this conversation.")
            })?;
        let response = match result {
            Ok(response) => response,
            Err(error) => {
                if state.operations[index].phase == "uncertain" {
                    state.operations[index].payload["lastError"] = json!(error.wire_message());
                    return self.save_codex_delivery(&mut state).await;
                }
                if unsupported(&error)
                    || error
                        .wire_message()
                        .contains("paginated threads do not support thread/rollback")
                    || error
                        .wire_message()
                        .contains("no longer supports editing history with rollback")
                {
                    state.history_edit_unavailable = Some("This Codex version does not support editing this conversation. The original history has not been changed.".into());
                }
                let op = &mut state.operations[index];
                op.payload["uncertainPhase"] = json!(op.phase);
                // A confirmed rollback with an unsaved receipt also needs reconciliation.
                op.phase = if op.phase == "rollingBack"
                    && (super::codex_queue_delivery::delivery_is_uncertain(&error)
                        || matches!(&error, HostError::Conflict { code, .. } if code == ROLLBACK_RECEIPT_PERSIST_FAILED))
                {
                    "uncertain"
                } else {
                    "failed"
                }
                .into();
                op.result = Some(
                    json!({"error": state.history_edit_unavailable.clone().unwrap_or_else(|| error.wire_message())}),
                );
                return self.save_codex_delivery(&mut state).await;
            }
        };
        self.replace_codex_history_snapshot(&state, &response)
            .await?;
        let payload = state.operations[index].payload.clone();
        state.operations[index].phase = "resending".into();
        state.messages.retain(|entry| entry.id != operation_id);
        state.messages.push(alera_core::runtime::CodexQueueEntry {
            id: operation_id.into(),
            revision: 0,
            payload,
            status: "queued".into(),
            error: None,
            turn_id: None,
        });
        let message_index = state.messages.len() - 1;
        self.deliver_codex_queue_entry(state, message_index, None)
            .await?;
        Ok(())
    }

    pub(super) async fn replace_codex_history_snapshot(
        &mut self,
        state: &alera_core::runtime::CodexChatDeliveryState,
        response: &Value,
    ) -> HostResult<()> {
        self.install_codex_history_snapshot(state, response, false)
            .await
    }

    pub(super) async fn reconcile_codex_history_snapshot(
        &mut self,
        state: &alera_core::runtime::CodexChatDeliveryState,
        response: &Value,
    ) -> HostResult<()> {
        self.install_codex_history_snapshot(state, response, true)
            .await
    }

    async fn install_codex_history_snapshot(
        &mut self,
        state: &alera_core::runtime::CodexChatDeliveryState,
        response: &Value,
        preserve_pending_requests: bool,
    ) -> HostResult<()> {
        let tab = self.codex_tab(&state.tab_id).await?;
        let server = self
            .ensure_codex_server(active_cwd(&tab).as_deref())
            .await?;
        server.thread_history.lock().await.remove(&state.thread_id);
        let page = server
            .project_resumed_thread_history(&state.thread_id, response, 20)
            .await?
            .ok_or_else(|| HostError::state("The conversation history could not be loaded."))?;
        self.install_codex_history_page(state, response, page, preserve_pending_requests)
            .await
    }

    pub(super) async fn install_codex_history_page(
        &mut self,
        state: &alera_core::runtime::CodexChatDeliveryState,
        response: &Value,
        page: super::codex_state::CodexTurnHistoryPage,
        preserve_pending_requests: bool,
    ) -> HostResult<()> {
        let mut tab = self.codex_tab(&state.tab_id).await?;
        self.codex_pending_messages.remove(&state.tab_id);
        let surviving_turns: std::collections::HashSet<&str> = response
            .pointer("/thread/turns")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|turn| turn["id"].as_str())
            .filter(|id| {
                !state
                    .discarded_turn_ids
                    .iter()
                    .any(|discarded| discarded == id)
            })
            .collect();
        let mut retained = snapshot(&tab);
        if let Some(cells) = retained["timelineCells"].as_array_mut() {
            cells.retain(|cell| {
                cell["turnId"]
                    .as_str()
                    .is_some_and(|id| surviving_turns.contains(id))
            });
        }
        let receipts = delivery_presentation_snapshot(&tab, state, &surviving_turns);
        let hydrated = super::codex_state::merge_resume_snapshot(&receipts, page.snapshot);
        let mut next = super::codex_state::merge_resume_snapshot(&retained, hydrated);
        if preserve_pending_requests {
            preserve_surviving_requests(&retained, &mut next);
            if tab_thread_id(&tab).as_deref() == Some(state.thread_id.as_str())
                && next.get("goal").is_none()
            {
                if let Some(goal) = retained.get("goal") {
                    next["goal"] = goal.clone();
                }
            }
        }
        set_thread_and_snapshot(&mut tab, &state.thread_id, next);
        tab.payload["codexDiscardedTurnIds"] = json!(state.discarded_turn_ids);
        tab.payload["codexHistoryRevision"] = json!(state.history_revision);
        if let Some(turns) = response.pointer("/thread/turns").and_then(Value::as_array) {
            tab.payload["codexCompletedTurnIds"] = json!(turns
                .iter()
                .filter(|turn| super::codex_history_actions::turn_complete(turn))
                .filter_map(|turn| turn["id"].as_str())
                .collect::<Vec<_>>());
        }
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(store_error)?;
        self.refresh_codex_delivery_activity(
            state,
            super::codex_state::active_turn_id(&snapshot(&tab)).is_some(),
        );
        self.schedule_shutdown_if_idle();
        self.broadcast_authenticated(event("codexThreadChanged", json!({"tabId": tab.id, "threadId": state.thread_id, "historyRevision": state.history_revision, "replaceHistory": true, "snapshot": snapshot(&tab), "historyNextCursor": page.next_cursor})));
        Ok(())
    }
}

pub(super) fn delivery_presentation_snapshot(
    tab: &alera_core::runtime::WorkspaceTabRecord,
    state: &alera_core::runtime::CodexChatDeliveryState,
    surviving_turns: &std::collections::HashSet<&str>,
) -> Value {
    let mut presentation = tab.clone();
    presentation.payload["codexSnapshot"] = json!({"timelineCells":[]});
    for entry in &state.messages {
        let Some(turn_id) = entry
            .turn_id
            .as_deref()
            .filter(|id| surviving_turns.contains(id))
        else {
            continue;
        };
        if entry.status != "accepted" {
            continue;
        }
        super::codex_user_messages::append_user_input(
            &mut presentation,
            &entry.payload["input"],
            entry.payload.get("userMessage"),
            turn_id,
            Some(&entry.id),
            entry.payload.get("turnId").is_some(),
        );
    }
    let mut snapshot = snapshot(&presentation);
    for cell in snapshot["timelineCells"].as_array_mut().unwrap() {
        if let Some(cell) = cell.as_object_mut() {
            // The native history owns timestamps; reconstructing a receipt is not a new message.
            cell.remove("createdAt");
            cell.remove("updatedAt");
        }
    }
    snapshot
}

fn preserve_surviving_requests(previous: &Value, next: &mut Value) {
    let Some(active) = super::codex_state::active_turn_id(next)
        .filter(|active| Some(active) == super::codex_state::active_turn_id(previous).as_ref())
    else {
        return;
    };
    next["pendingRequests"] = json!(previous["pendingRequests"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|request| {
            request["turnId"]
                .as_str()
                .map(str::to_string)
                .or_else(|| super::codex_state::turn_id_from_message(request))
                // Older snapshots omitted the turn on requests from the active turn.
                .is_none_or(|turn| turn == active)
        })
        .collect::<Vec<_>>());
}
