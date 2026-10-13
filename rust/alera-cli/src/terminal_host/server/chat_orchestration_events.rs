use async_trait::async_trait;
use serde_json::Value;

use super::chat_orchestration::OrchestrationEventSink;
use super::{ServerCommand, ServerInbox};

/// Queues committed orchestration changes back through the single host actor.
/// The service never writes to a client connection directly, so task changes
/// preserve the same ordering and backpressure rules as chat runtime events.
pub(crate) struct HostOrchestrationEventSink {
    inbox: ServerInbox,
}

impl HostOrchestrationEventSink {
    pub(crate) fn new(inbox: ServerInbox) -> Self {
        Self { inbox }
    }
}

#[async_trait]
impl OrchestrationEventSink for HostOrchestrationEventSink {
    async fn changed(&self, change: Value) {
        let _ = self
            .inbox
            .send(ServerCommand::ChatOrchestrationChanged { change });
    }
}
