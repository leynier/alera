//! Where committed chat changes go: the host (which broadcasts them to
//! clients) and any in-process subscribers of the runtime handle.

use async_trait::async_trait;
use serde_json::Value;
use tokio::sync::broadcast;

use crate::terminal_host::server::{ServerCommand, ServerInbox};

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum ChatRuntimeEvent {
    /// One committed cursor step of a chat.
    Changed {
        chat_id: String,
        workspace_id: String,
        cursor: i64,
        delta: Value,
    },
    /// The chat list of a workspace changed (create, close, reopen, rename,
    /// provider switch).
    ChatsChanged {
        workspace_id: Option<String>,
    },
    PreferencesChanged {
        revision: i64,
    },
    Deleted {
        chat_id: String,
        workspace_id: String,
        discarded: bool,
    },
    /// A tab record was created, removed or renamed by the chat runtime.
    TabsChanged {
        workspace_id: String,
    },
}

#[async_trait]
pub(crate) trait ChatEventSink: Send + Sync + 'static {
    /// Delivered in commit order; awaiting it applies backpressure.
    async fn emit(&self, event: ChatRuntimeEvent);
    /// Busy or live provider counts changed; the host re-evaluates its idle
    /// shutdown timer.
    fn activity_changed(&self);
}

/// Sends every event to the host sink and to in-process subscribers.
pub(crate) struct EventFanout {
    host: Box<dyn ChatEventSink>,
    subscribers: broadcast::Sender<ChatRuntimeEvent>,
}

impl EventFanout {
    pub(crate) fn new(host: Box<dyn ChatEventSink>) -> Self {
        let (subscribers, _) = broadcast::channel(1024);
        Self { host, subscribers }
    }

    pub(crate) fn subscribe(&self) -> broadcast::Receiver<ChatRuntimeEvent> {
        self.subscribers.subscribe()
    }
}

#[async_trait]
impl ChatEventSink for EventFanout {
    async fn emit(&self, event: ChatRuntimeEvent) {
        let _ = self.subscribers.send(event.clone());
        self.host.emit(event).await;
    }

    fn activity_changed(&self) {
        self.host.activity_changed();
    }
}

/// A sink that drops everything, for a runtime with no host attached.
#[cfg(test)]
pub(crate) struct NullSink;

#[cfg(test)]
#[async_trait]
impl ChatEventSink for NullSink {
    async fn emit(&self, _event: ChatRuntimeEvent) {}
    fn activity_changed(&self) {}
}

/// Bridges ordered runtime commits into the terminal-host actor. Provider
/// tasks never write to client connections directly.
pub(crate) struct HostEventSink {
    inbox: ServerInbox,
}

impl HostEventSink {
    pub(crate) fn new(inbox: ServerInbox) -> Self {
        Self { inbox }
    }
}

#[async_trait]
impl ChatEventSink for HostEventSink {
    async fn emit(&self, event: ChatRuntimeEvent) {
        let _ = self
            .inbox
            .send(ServerCommand::AgentChatRuntimeEvent { event });
    }

    fn activity_changed(&self) {
        let _ = self.inbox.send(ServerCommand::AgentChatActivityChanged);
    }
}
