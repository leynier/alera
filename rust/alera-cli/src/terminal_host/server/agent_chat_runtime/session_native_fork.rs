//! Native fork intent stays host-only and starts on the target's first send.

use alera_provider_protocol::NativeForkBoundary;
use serde::Deserialize;

use super::session::ChatSession;

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct NativeForkPlan {
    pub source_native_thread_id: String,
    pub boundary: NativeForkBoundary,
    pub provider: String,
    pub provider_instance_id: String,
}

impl ChatSession {
    pub(super) fn native_fork_pending(&self) -> bool {
        self.native_fork.as_ref().is_some_and(|plan| {
            plan.provider == self.header.provider
                && plan.provider_instance_id == self.header.provider_instance_id
                && self
                    .header
                    .session
                    .extra
                    .get("historyOperation")
                    .and_then(|operation| operation.get("kind"))
                    .and_then(serde_json::Value::as_str)
                    == Some("nativeForkDeferred")
        })
    }

    pub(super) fn native_fork_has_local_history(&self) -> bool {
        let Some(source_turn) = self.fork_source_turn_id.as_deref() else {
            return true;
        };
        let Some(index) = self
            .header
            .turns
            .iter()
            .position(|turn| turn.turn_id == source_turn)
        else {
            return true;
        };
        self.header.turns[index + 1..]
            .iter()
            .any(|turn| Some(&turn.turn_id) != self.header.session.active_turn_id.as_ref())
    }

    pub(super) async fn complete_native_fork(&mut self) -> Result<(), String> {
        self.clear_native_fork("nativeFork").await
    }

    pub(super) async fn clear_native_fork(&mut self, kind: &str) -> Result<(), String> {
        self.native_fork = None;
        self.header
            .session
            .extra
            .insert("historyOperation".into(), serde_json::json!({"kind":kind}));
        let mut record = self
            .deps
            .store
            .agent_chat(&self.header.chat_id)
            .await
            .map_err(|error| error.to_string())?
            .ok_or_else(|| "The forked chat no longer exists.".to_string())?;
        if let Some(metadata) = record
            .metadata
            .as_mut()
            .and_then(serde_json::Value::as_object_mut)
        {
            metadata.remove("nativeFork");
        }
        self.deps
            .store
            .set_agent_chat_metadata(&self.header.chat_id, record.metadata.as_ref())
            .await
            .map(|_| ())
            .map_err(|error| error.to_string())
    }
}
