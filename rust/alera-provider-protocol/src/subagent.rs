use crate::ProviderEvent;
use serde_json::Value;

/// `ChatTurn.origin` of a turn the agent started on its own once its
/// background work finished (ACP native child sessions).
pub const BACKGROUND_CONTINUATION_ORIGIN: &str = "backgroundContinuation";

/// What a live session can do with the agent's own sub-agents beyond the
/// static provider traits.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SubagentCapabilities {
    /// The agent runs its sub-agents as native child sessions the adapter
    /// projects under the call that started each one.
    pub native_child_sessions: bool,
    /// `Provider::stop_subagent` can stop one of them.
    pub stop: bool,
}

impl ProviderEvent {
    /// Why the agent started the turn a `turn.started` opens when no app
    /// turn asked for it. The host adopts such a turn as the running one.
    pub fn agent_started_turn_origin(&self) -> Option<&str> {
        self.payload
            .get("agentStarted")
            .and_then(|started| started.get("origin"))
            .and_then(Value::as_str)
            .filter(|origin| !origin.is_empty())
    }
}
