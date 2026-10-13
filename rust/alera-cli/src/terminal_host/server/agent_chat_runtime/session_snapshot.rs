//! Store-backed snapshot and history reads. The core store owns pagination
//! and keeps the full transcript out of the session header.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::session::ChatSession;

pub(crate) const HISTORY_MAX_ITEMS: usize = 200;

fn parse_history_token(token: &str) -> HostResult<i64> {
    token
        .strip_prefix("seq:")
        .and_then(|value| value.parse().ok())
        .ok_or_else(|| HostError::format("before must be a historyBefore token"))
}

impl ChatSession {
    pub(super) async fn snapshot(&mut self) -> HostResult<Value> {
        self.flush()
            .await
            .map_err(|error| HostError::state(format!("The chat could not be saved: {error}")))?;
        self.deps
            .store
            .agent_chat(&self.header.chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .map(|record| record.snapshot)
            .ok_or_else(|| {
                HostError::conflict("chatNotFound", "The chat no longer exists.", json!({}))
            })
    }

    pub(super) async fn history(&mut self, before: &str, limit: usize) -> HostResult<Value> {
        let before = parse_history_token(before)?;
        let page = self
            .deps
            .store
            .agent_chat_history(
                &self.header.chat_id,
                before,
                limit.clamp(1, HISTORY_MAX_ITEMS) as i64,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(json!({
            "items": page.items,
            "turns": page.turns,
            "historyBefore": page.history_before.map(|seq| format!("seq:{seq}")),
        }))
    }
}
