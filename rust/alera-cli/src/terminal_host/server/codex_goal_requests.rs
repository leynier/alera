//! Goal requests bridged to the Codex app-server.

use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_state::{persist_snapshot, snapshot, snapshot_delta, tab_thread_id};
use super::codex_tab_lifecycle::{active_cwd, configuration};
use super::codex_thread_identity::ensure_expected_thread;
use super::codex_user_messages::append_goal_user_input;
use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn get_codex_goal(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let Some(thread_id) = tab_thread_id(&tab) else {
            return Ok(json!({"goal": null}));
        };
        let result = self
            .codex_server_request("thread/goal/get", json!({"threadId": thread_id}))
            .await?;
        let clear = result.get("goal").is_none_or(Value::is_null);
        self.persist_codex_goal(&tab.id, result.get("goal"), clear, None)
            .await?;
        Ok(result)
    }

    pub(super) async fn set_codex_goal(&mut self, payload: &Value) -> HostResult<Value> {
        let (tab, thread_id, _) = self.materialize_codex_thread(payload).await?;
        let mut params = json!({"threadId": thread_id});
        let Some(params_object) = params.as_object_mut() else {
            unreachable!("goal params are always an object");
        };
        for key in ["objective", "status", "tokenBudget"] {
            if let Some(value) = payload.get(key) {
                params_object.insert(key.to_string(), value.clone());
            }
        }
        let result = self.codex_server_request("thread/goal/set", params).await?;
        let record_user_message = payload
            .get("recordUserMessage")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let client_user_message_id = record_user_message.then(|| {
            payload
                .get("clientUserMessageId")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| Uuid::new_v4().to_string())
        });
        self.persist_codex_goal(
            &tab.id,
            result.get("goal"),
            false,
            client_user_message_id.as_deref(),
        )
        .await?;
        Ok(result)
    }

    pub(super) async fn clear_codex_goal(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let Some(thread_id) = tab_thread_id(&tab) else {
            return Ok(json!({"cleared": false}));
        };
        let result = self
            .codex_server_request("thread/goal/clear", json!({"threadId": thread_id}))
            .await?;
        if result.get("cleared").and_then(Value::as_bool) == Some(true) {
            self.persist_codex_goal(&tab.id, None, true, None).await?;
        }
        Ok(result)
    }

    async fn persist_codex_goal(
        &mut self,
        tab_id: &str,
        goal: Option<&Value>,
        clear: bool,
        client_user_message_id: Option<&str>,
    ) -> HostResult<()> {
        let mut tab = self.codex_tab(tab_id).await?;
        let previous_snapshot = snapshot(&tab);
        let mut next_snapshot = previous_snapshot.clone();
        if let Some(object) = next_snapshot.as_object_mut() {
            if clear {
                object.remove("goal");
            } else if let Some(goal) = goal.filter(|value| value.is_object()) {
                object.insert("goal".to_string(), goal.clone());
            }
        }
        persist_snapshot(&mut tab, next_snapshot);
        if let Some(client_user_message_id) = client_user_message_id {
            let objective = goal
                .and_then(|value| value.get("objective"))
                .and_then(Value::as_str)
                .ok_or_else(|| HostError::state("Codex app-server returned no goal objective."))?;
            append_goal_user_input(&mut tab, objective, client_user_message_id);
        }
        let next_snapshot = snapshot(&tab);
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.refresh_codex_presence(&saved);
        self.schedule_codex_presence_changed();
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": tab_thread_id(&saved),
                "cwd": active_cwd(&saved),
                "configuration": configuration(&saved),
                "snapshot": snapshot(&saved),
                "snapshotDelta": snapshot_delta(&previous_snapshot, &next_snapshot, &[]),
            }),
        ));
        Ok(())
    }
}
