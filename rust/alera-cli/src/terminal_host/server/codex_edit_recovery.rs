use super::codex_queue_delivery::contains_client_message;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};

impl ServerActor {
    #[cfg(test)]
    pub(super) async fn reconcile_codex_history_edit(
        &mut self,
        tab_id: &str,
        operation_id: &str,
    ) -> HostResult<Value> {
        self.reconcile_codex_history_edit_scanned(tab_id, operation_id, None)
            .await
    }

    pub(super) async fn reconcile_codex_history_edit_scanned(
        &mut self,
        tab_id: &str,
        operation_id: &str,
        scan: Option<&super::codex_history_scans::CodexHistoryScan>,
    ) -> HostResult<Value> {
        let tab = self.codex_tab(tab_id).await?;
        let mut state = self.codex_delivery_state(&tab).await?;
        let index = state
            .operations
            .iter()
            .position(|op| op.id == operation_id)
            .ok_or_else(|| HostError::state("The edit operation no longer exists."))?;
        let server = self.ensure_codex_server(None).await?;
        let turns =
            super::codex_history_scans::scanned_history(&server, &state.thread_id, scan, false)
                .await?
                .turns;
        let mut replaced = false;
        if let Some(turn) = turns
            .iter()
            .find(|turn| contains_client_message(turn, operation_id))
        {
            state.operations[index].phase = "completed".into();
            state.operations[index]
                .payload
                .as_object_mut()
                .unwrap()
                .remove("lastError");
            let receipt = alera_core::runtime::CodexQueueEntry {
                id: operation_id.into(),
                revision: 0,
                payload: state.operations[index].payload.clone(),
                status: "accepted".into(),
                error: None,
                turn_id: turn["id"].as_str().map(str::to_string),
            };
            state.messages.retain(|entry| entry.id != operation_id);
            state.messages.push(receipt);
            replaced = true;
        } else if state.operations[index].payload["uncertainPhase"] == "interrupting" {
            state.operations[index].phase = "failed".into();
            state.operations[index].payload["lastError"] = json!(
                "The runtime restarted before editing history. Confirm the correction again."
            );
        } else if state.operations[index].payload["uncertainPhase"] == "rollingBack" {
            let operation = &state.operations[index];
            let target = operation.payload["editTargetTurnId"]
                .as_str()
                .unwrap_or_default();
            let original = operation.payload["editOriginalTurnIds"]
                .as_array()
                .ok_or_else(|| HostError::state("The original history boundary is unavailable."))?;
            let position = original
                .iter()
                .position(|id| id.as_str() == Some(target))
                .ok_or_else(|| HostError::state("The original turn boundary is unavailable."))?;
            let prefix = &original[..position];
            if prefix.len() == turns.len()
                && prefix
                    .iter()
                    .zip(turns.iter())
                    .all(|(id, turn)| *id == turn["id"])
            {
                state.discarded_turn_ids.extend(
                    original[position..]
                        .iter()
                        .filter_map(|id| id.as_str().map(str::to_string)),
                );
                state.history_revision += 1;
                state.operations[index].phase = "rolledBack".into();
                state.operations[index].result =
                    Some(json!({"thread": {"id": state.thread_id, "turns": turns.as_ref()}}));
                replaced = true;
            } else if turns.iter().any(|turn| turn["id"].as_str() == Some(target)) {
                state.operations[index].phase = "failed".into();
                state.operations[index].payload["lastError"] =
                    json!("History still contains the original turn. Confirm the edit again.");
            }
        }
        self.save_codex_delivery(&mut state).await?;
        if replaced {
            self.reconcile_codex_history_snapshot(
                &state,
                &json!({"thread":{"id":state.thread_id,"turns":turns.as_ref()}}),
            )
            .await?;
        }
        Ok(state.snapshot())
    }
}
