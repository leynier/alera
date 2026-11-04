//! A turn the agent starts on its own while no app turn runs, as Claude
//! Agent does over ACP v2 once the background sub-agents it waited on end,
//! becomes the chat's running turn: no user message, and an `origin` that
//! says why it runs.

use alera_provider_protocol::ProviderEvent;

use super::session::ChatSession;

impl ChatSession {
    /// Adopts the native turn of a `turn.started` the agent opened itself.
    /// A running app turn already owns the provider's work, so it stays.
    pub(super) async fn adopt_agent_started_turn(&mut self, event: &ProviderEvent) {
        let (Some(origin), Some(native_turn)) =
            (event.agent_started_turn_origin(), event.turn_id.as_deref())
        else {
            return;
        };
        if self.header.session.active_turn_id.is_some()
            || self.provider.is_none()
            || self.header.archived
        {
            return;
        }
        let model = self.header.session.model.clone();
        let reasoning_effort = self.header.session.reasoning_effort.clone();
        self.adopt_native_turn(native_turn, model, reasoning_effort, origin)
            .await;
    }
}
