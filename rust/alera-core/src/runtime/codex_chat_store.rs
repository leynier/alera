//! Durable delivery and history-operation state, independent of tab payloads.

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;

use super::RuntimeStore;

pub(super) const CODEX_CHAT_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS codexChatState (threadId TEXT PRIMARY KEY, tabId TEXT NOT NULL, revision INTEGER NOT NULL, stateJson TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS codexChatStateTab ON codexChatState(tabId)",
    "CREATE TRIGGER IF NOT EXISTS codexChatStateDeleteTab AFTER DELETE ON workspaceTabs BEGIN DELETE FROM codexChatState WHERE tabId = OLD.id; END",
];

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodexQueueEntry {
    pub id: String,
    pub revision: u64,
    pub payload: Value,
    pub status: String,
    pub error: Option<String>,
    pub turn_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodexChatOperation {
    pub id: String,
    pub kind: String,
    pub phase: String,
    pub payload: Value,
    pub result: Option<Value>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CodexChatDeliveryState {
    pub thread_id: String,
    pub tab_id: String,
    pub revision: u64,
    pub history_revision: u64,
    pub paused: bool,
    pub history_edit_unavailable: Option<String>,
    pub discarded_turn_ids: Vec<String>,
    pub messages: Vec<CodexQueueEntry>,
    pub operations: Vec<CodexChatOperation>,
}

impl CodexChatDeliveryState {
    pub fn new(tab_id: &str, thread_id: &str) -> Self {
        Self {
            tab_id: tab_id.into(),
            thread_id: thread_id.into(),
            ..Self::default()
        }
    }

    pub fn history_locked(&self) -> bool {
        self.operations.iter().any(|operation| {
            operation.kind == "edit" && !matches!(operation.phase.as_str(), "completed" | "failed")
        })
    }

    pub fn has_pending(&self) -> bool {
        self.messages
            .iter()
            .any(|entry| !matches!(entry.status.as_str(), "accepted" | "removed"))
    }

    pub fn snapshot(&self) -> Value {
        serde_json::json!({
            "threadId": self.thread_id,
            "tabId": self.tab_id,
            "revision": self.revision,
            "historyRevision": self.history_revision,
            "paused": self.paused,
            "historyEditUnavailableReason": self.history_edit_unavailable,
            "historyLocked": self.history_locked(),
            "messages": self.messages.iter().filter(|entry| !matches!(entry.status.as_str(), "accepted" | "removed")).collect::<Vec<_>>(),
            "editOperation": self.operations.iter().rev().find(|operation| operation.kind == "edit").map(|operation| serde_json::json!({
                "id": operation.id, "kind": operation.kind, "phase": operation.phase,
                "payload": {"lastError": operation.payload.get("lastError")},
                "result": {"error": operation.result.as_ref().and_then(|result| result.get("error"))},
            })),
        })
    }
}

impl RuntimeStore {
    pub async fn codex_chat_state(
        &self,
        thread_id: &str,
    ) -> Result<Option<CodexChatDeliveryState>> {
        let row = sqlx::query("SELECT stateJson FROM codexChatState WHERE threadId = ?")
            .bind(thread_id)
            .fetch_optional(self.pool())
            .await?;
        row.map(|row| {
            Ok(serde_json::from_str(
                &row.try_get::<String, _>("stateJson")?,
            )?)
        })
        .transpose()
    }

    /// Compare-and-swap also protects a deferred operation from a stale writer.
    pub async fn save_codex_chat_state(&self, state: &mut CodexChatDeliveryState) -> Result<()> {
        let previous = state.revision;
        let mut next = state.clone();
        next.revision += 1;
        let json = serde_json::to_string(&next)?;
        let changed = if previous == 0 {
            sqlx::query("INSERT OR IGNORE INTO codexChatState (threadId, tabId, revision, stateJson) VALUES (?, ?, ?, ?)")
                .bind(&next.thread_id).bind(&next.tab_id).bind(next.revision as i64).bind(json)
                .execute(self.pool()).await?.rows_affected()
        } else {
            sqlx::query("UPDATE codexChatState SET tabId = ?, revision = ?, stateJson = ? WHERE threadId = ? AND revision = ?")
                .bind(&next.tab_id).bind(next.revision as i64).bind(json).bind(&next.thread_id).bind(previous as i64)
                .execute(self.pool()).await?.rows_affected()
        };
        if changed != 1 {
            bail!("Codex queue changed. Refresh before trying again.");
        }
        *state = next;
        Ok(())
    }

    pub async fn list_codex_chat_states(&self) -> Result<Vec<CodexChatDeliveryState>> {
        let rows = sqlx::query("SELECT stateJson FROM codexChatState")
            .fetch_all(self.pool())
            .await?;
        rows.into_iter()
            .map(|row| {
                Ok(serde_json::from_str(
                    &row.try_get::<String, _>("stateJson")?,
                )?)
            })
            .collect()
    }
}
