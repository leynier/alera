use super::codex_state::{active_turn_id, snapshot, tab_thread_id};
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::CodexChatDeliveryState;
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn advance_codex_queue(&mut self, tab_id: &str) {
        if let Err(error) = self.advance_codex_queue_inner(tab_id).await {
            tracing::warn!(tab_id, "Codex queue could not advance: {error}");
        }
    }

    async fn advance_codex_queue_inner(&mut self, tab_id: &str) -> HostResult<()> {
        if self.emulator_requests.has_runtime_mutations()
            || self.codex_history_scans.contains(tab_id)
        {
            return Ok(());
        }
        let tab = self.codex_tab(tab_id).await?;
        let mut state = self.codex_delivery_state(&tab).await?;
        if state.paused
            || state.history_locked()
            || state
                .messages
                .iter()
                .any(|entry| matches!(entry.status.as_str(), "sending" | "uncertain" | "failed"))
        {
            return Ok(());
        }
        if let Some(index) = state
            .messages
            .iter()
            .position(|entry| entry.status == "queued" && entry.payload["turnId"].is_string())
            .or_else(|| {
                state
                    .messages
                    .iter()
                    .position(|entry| entry.status == "queued")
            })
        {
            let turn_id = state.messages[index].payload["turnId"]
                .as_str()
                .map(str::to_string);
            let active = active_turn_id(&snapshot(&tab));
            if turn_id.is_some() && turn_id != active {
                state.paused = true;
                state.messages[index].status = "failed".into();
                state.messages[index].error = Some("The original turn ended. This message was not sent. Use Steer on another active turn or edit it before resuming.".into());
                self.save_codex_delivery(&mut state).await?;
            } else if turn_id.is_some() || active.is_none() {
                self.deliver_codex_queue_entry(state, index, turn_id)
                    .await?;
            }
        }
        Ok(())
    }

    pub(super) async fn deliver_codex_queue_entry(
        &mut self,
        mut state: CodexChatDeliveryState,
        index: usize,
        turn_id: Option<String>,
    ) -> HostResult<Value> {
        if let Some(turn_id) = &turn_id {
            state.messages[index].payload["turnId"] = json!(turn_id);
        }
        match self
            .prepare_codex_queue_delivery(state.clone(), index, turn_id)
            .await
        {
            Ok(response) => Ok(response),
            Err(error) => {
                state.paused = true;
                state.messages[index].status = "failed".into();
                state.messages[index].error = Some(error.wire_message());
                update_edit_delivery(&mut state, index);
                self.save_codex_delivery(&mut state).await?;
                Ok(state.snapshot())
            }
        }
    }

    async fn prepare_codex_queue_delivery(
        &mut self,
        mut state: CodexChatDeliveryState,
        index: usize,
        turn_id: Option<String>,
    ) -> HostResult<Value> {
        let tab = self.codex_tab(&state.tab_id).await?;
        let cwd = state.messages[index]
            .payload
            .get("cwd")
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| super::codex_tab_lifecycle::active_cwd(&tab))
            .ok_or_else(|| HostError::state("The conversation directory is unavailable."))?;
        let server = self.ensure_codex_server(Some(&cwd)).await?;
        if !server
            .has_loaded_thread(&state.tab_id, &state.thread_id, &cwd)
            .await
            && !self
                .hydrate_codex_queue_thread(&state, turn_id.as_deref())
                .await?
        {
            return Ok(state.snapshot());
        }
        let input = super::codex_workspace_inputs::normalize_legacy_codex_inputs(
            state.messages[index].payload["input"].clone(),
            &cwd,
        )
        .await?;
        let entry = &mut state.messages[index];
        entry.status = "sending".into();
        entry.error = None;
        entry.revision += 1;
        entry.turn_id = turn_id.clone();
        let mut payload = entry.payload.clone();
        payload["cwd"] = json!(cwd);
        if let Some(turn_id) = &turn_id {
            payload["turnId"] = json!(turn_id);
            entry.payload["turnId"] = json!(turn_id);
        }
        self.save_codex_delivery(&mut state).await?;
        let params = if let Some(turn_id) = &turn_id {
            json!({"threadId": state.thread_id, "expectedTurnId": turn_id, "clientUserMessageId": state.messages[index].id, "input": input})
        } else {
            super::codex_requests::turn_params(&payload, &state.thread_id, input)
        };
        let method = if turn_id.is_some() {
            "turn/steer"
        } else {
            "turn/start"
        };
        let tab_id = state.tab_id.clone();
        let thread_id = state.thread_id.clone();
        let message_id = state.messages[index].id.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = server.request(method, params).await;
            let _ = inbox.send(ServerCommand::CodexQueueDelivered {
                tab_id,
                thread_id,
                message_id,
                result,
            });
        });
        Ok(state.snapshot())
    }

    async fn hydrate_codex_queue_thread(
        &mut self,
        state: &CodexChatDeliveryState,
        target_turn: Option<&str>,
    ) -> HostResult<bool> {
        let opened = self
            .open_codex_thread(&json!({
                "tabId": state.tab_id, "supportsMissingRolloutRecovery": true,
            }))
            .await?;
        let tab = self.codex_tab(&state.tab_id).await?;
        if opened["recovery"].is_object()
            || tab_thread_id(&tab).as_deref() != Some(&state.thread_id)
            || opened["threadId"].as_str() != Some(&state.thread_id)
        {
            return Err(HostError::state(
                "The queued conversation could not be resumed. Recover it before sending.",
            ));
        }
        let current = self.codex_delivery_state(&tab).await?;
        if current.revision != state.revision {
            return Err(HostError::state(
                "The queue changed while its conversation was being resumed.",
            ));
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event("codexThreadChanged", json!({
            "tabId": state.tab_id, "threadId": state.thread_id, "historyRevision": state.history_revision,
            "snapshot": opened["snapshot"], "historyNextCursor": opened["historyNextCursor"],
        })));
        let active = active_turn_id(&snapshot(&tab));
        if let Some(target) = target_turn {
            if active.as_deref() != Some(target) {
                return Err(HostError::state(
                    "The original turn ended. This message was not sent.",
                ));
            }
        } else if active.is_some() {
            if state.history_locked() {
                return Err(HostError::state(
                    "A turn is still active. Wait before retrying the correction.",
                ));
            }
            return Ok(false);
        }
        Ok(true)
    }

    pub(super) async fn finish_codex_queue_delivery(
        &mut self,
        tab_id: &str,
        thread_id: &str,
        message_id: &str,
        result: HostResult<Value>,
    ) -> HostResult<()> {
        let tab = self.codex_tab(tab_id).await?;
        if tab_thread_id(&tab).as_deref() != Some(thread_id) {
            return Ok(());
        }
        let mut state = self.codex_delivery_state(&tab).await?;
        let Some(index) = state
            .messages
            .iter()
            .position(|entry| entry.id == message_id && entry.status == "sending")
        else {
            return Ok(());
        };
        let turn_id = state.messages[index].turn_id.clone();
        match &result {
            Ok(response) => {
                state.messages[index].status = "accepted".into();
                state.messages[index].turn_id = response
                    .pointer("/turn/id")
                    .or_else(|| response.get("turnId"))
                    .and_then(Value::as_str)
                    .map(str::to_string)
                    .or(turn_id);
            }
            Err(error) => {
                state.paused = true;
                state.messages[index].status = if delivery_is_uncertain(error) {
                    "uncertain"
                } else {
                    "failed"
                }
                .into();
                state.messages[index].error = Some(error.wire_message());
            }
        }
        update_edit_delivery(&mut state, index);
        if state.messages[index].status == "accepted" {
            let entry = &state.messages[index];
            if let Err(error) = self
                .protect_accepted_codex_attachments(&entry.payload)
                .await
            {
                tracing::warn!("Could not mark accepted Codex attachments: {error}");
            }
            if let Some(turn_id) = &entry.turn_id {
                self.persist_codex_user_input(
                    tab_id,
                    &entry.payload["input"],
                    entry.payload.get("userMessage"),
                    turn_id,
                    Some(&entry.id),
                    entry.payload.get("turnId").is_some(),
                )
                .await;
            }
            if entry.payload.get("turnId").is_none() {
                let prompt = super::codex_user_messages::visible_text(
                    &entry.payload["input"],
                    entry.payload.get("userMessage"),
                );
                self.observe_agent_title(tab_id, "codex", Some(thread_id), &prompt, true)
                    .await;
            }
            self.schedule_codex_queue(tab_id);
        }
        self.save_codex_delivery(&mut state).await?;
        Ok(())
    }

    #[cfg(test)]
    pub(super) async fn reconcile_codex_queue(
        &mut self,
        state: CodexChatDeliveryState,
    ) -> HostResult<Value> {
        self.reconcile_codex_queue_scanned(state, None).await
    }

    pub(super) async fn reconcile_codex_queue_scanned(
        &mut self,
        mut state: CodexChatDeliveryState,
        scan: Option<&super::codex_history_scans::CodexHistoryScan>,
    ) -> HostResult<Value> {
        let server = self.ensure_codex_server(None).await?;
        let turns =
            super::codex_history_scans::scanned_history(&server, &state.thread_id, scan, false)
                .await?
                .turns;
        for entry in &mut state.messages {
            if !matches!(entry.status.as_str(), "sending" | "uncertain") {
                continue;
            }
            if let Some(turn) = turns
                .iter()
                .find(|turn| contains_client_message(turn, &entry.id))
            {
                entry.turn_id = turn["id"].as_str().map(str::to_string);
                entry.status = "accepted".into();
                entry.error = None;
                self.protect_accepted_codex_attachments(&entry.payload)
                    .await?;
            } else {
                entry.status = "uncertain".into();
                entry.error = Some(
                    "Delivery could not be confirmed. It will not be resent automatically.".into(),
                );
            }
        }
        self.save_codex_delivery(&mut state).await?;
        self.reconcile_codex_history_snapshot(
            &state,
            &json!({"thread":{"id":state.thread_id,"turns":turns.as_ref()}}),
        )
        .await?;
        Ok(state.snapshot())
    }
}

fn update_edit_delivery(state: &mut CodexChatDeliveryState, index: usize) {
    let entry = &state.messages[index];
    if let Some(operation) = state
        .operations
        .iter_mut()
        .find(|op| op.kind == "edit" && op.id == entry.id)
    {
        operation.phase = match entry.status.as_str() {
            "accepted" => "completed",
            "uncertain" => "uncertain",
            _ => "resendFailed",
        }
        .into();
        operation.payload["uncertainPhase"] = json!("resending");
        operation.payload["lastError"] = json!(entry.error);
    }
}

pub(super) fn delivery_is_uncertain(error: &HostError) -> bool {
    let message = error.wire_message().to_ascii_lowercase();
    [
        "timed out",
        "disconnected",
        "input failed",
        "codex app-server output failed:",
        "closed",
        "exited",
    ]
    .iter()
    .any(|part| message.contains(part))
}

pub(super) fn contains_client_message(value: &Value, id: &str) -> bool {
    match value {
        Value::Object(object) => {
            (object.get("type").and_then(Value::as_str) == Some("userMessage")
                && object.get("clientId").and_then(Value::as_str) == Some(id))
                || object.get("clientUserMessageId").and_then(Value::as_str) == Some(id)
                || object
                    .values()
                    .any(|value| contains_client_message(value, id))
        }
        Value::Array(items) => items.iter().any(|value| contains_client_message(value, id)),
        _ => false,
    }
}
