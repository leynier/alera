use crate::{ProviderKind, RuntimeRequest};
use serde::{Deserialize, Serialize};
use serde_json::Value;

macro_rules! event_kinds {
    ($($variant:ident => $wire:literal),+ $(,)?) => {
        #[derive(Debug, Clone, PartialEq, Eq)]
        pub enum EventKind { $($variant,)+ Unknown(String) }
        impl EventKind {
            pub fn as_str(&self) -> &str {
                match self { $(Self::$variant => $wire,)+ Self::Unknown(name) => name }
            }
        }
        impl Serialize for EventKind {
            fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
                serializer.serialize_str(self.as_str())
            }
        }
        impl<'de> Deserialize<'de> for EventKind {
            fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
                let name = String::deserialize(deserializer)?;
                Ok(match name.as_str() { $($wire => Self::$variant,)+ _ => Self::Unknown(name) })
            }
        }
    };
}
event_kinds! {
    SessionStarted => "session.started",
    SessionConfigured => "session.configured",
    SessionStateChanged => "session.state.changed",
    SessionExited => "session.exited",
    SessionCommandsUpdated => "session.commands.updated",
    ThreadStarted => "thread.started",
    ThreadStateChanged => "thread.state.changed",
    ThreadMetadataUpdated => "thread.metadata.updated",
    ThreadTokenUsageUpdated => "thread.token-usage.updated",
    ThreadRealtimeStarted => "thread.realtime.started",
    ThreadRealtimeItemAdded => "thread.realtime.item-added",
    ThreadRealtimeAudioDelta => "thread.realtime.audio.delta",
    ThreadRealtimeError => "thread.realtime.error",
    ThreadRealtimeClosed => "thread.realtime.closed",
    TurnStarted => "turn.started",
    TurnCompleted => "turn.completed",
    TurnAborted => "turn.aborted",
    TurnPlanUpdated => "turn.plan.updated",
    TurnProposedDelta => "turn.proposed.delta",
    TurnProposedCompleted => "turn.proposed.completed",
    TurnDiffUpdated => "turn.diff.updated",
    ItemStarted => "item.started",
    ItemUpdated => "item.updated",
    ItemCompleted => "item.completed",
    ContentDelta => "content.delta",
    RequestOpened => "request.opened",
    RequestResolved => "request.resolved",
    UserInputRequested => "user-input.requested",
    UserInputResolved => "user-input.resolved",
    TaskStarted => "task.started",
    TaskProgress => "task.progress",
    TaskUpdated => "task.updated",
    TaskCompleted => "task.completed",
    HookStarted => "hook.started",
    HookProgress => "hook.progress",
    HookCompleted => "hook.completed",
    ToolProgress => "tool.progress",
    ToolSummary => "tool.summary",
    AuthStatus => "auth.status",
    AccountUpdated => "account.updated",
    AccountRateLimitsUpdated => "account.rate-limits.updated",
    McpStatusUpdated => "mcp.status.updated",
    McpOauthCompleted => "mcp.oauth.completed",
    ModelRerouted => "model.rerouted",
    ConfigWarning => "config.warning",
    DeprecationNotice => "deprecation.notice",
    FilesPersisted => "files.persisted",
    ToolDenied => "tool.denied",
    RuntimeWarning => "runtime.warning",
    RuntimeError => "runtime.error",
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StreamKind {
    AssistantText,
    ReasoningText,
    ReasoningSummaryText,
    PlanText,
    CommandOutput,
    FileChangeOutput,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TurnStatus {
    Completed,
    Failed,
    Interrupted,
    Cancelled,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderRefs {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_turn_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_item_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_request_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawEvent {
    pub source: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message_type: Option<String>,
    pub payload: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderEvent {
    pub event_id: String,
    pub provider: ProviderKind,
    pub provider_instance_id: String,
    pub thread_id: String,
    pub created_at: String,
    #[serde(rename = "type")]
    pub kind: EventKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_refs: Option<ProviderRefs>,
    pub payload: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub raw: Option<RawEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime_request: Option<RuntimeRequest>,
}

impl ProviderEvent {
    pub fn new(
        provider: ProviderKind,
        instance_id: impl Into<String>,
        thread_id: impl Into<String>,
        kind: EventKind,
        payload: Value,
        raw: Option<RawEvent>,
    ) -> Self {
        Self {
            event_id: uuid::Uuid::new_v4().to_string(),
            provider,
            provider_instance_id: instance_id.into(),
            thread_id: thread_id.into(),
            created_at: chrono::Utc::now().to_rfc3339(),
            kind,
            turn_id: None,
            item_id: None,
            request_id: None,
            provider_refs: None,
            payload,
            raw,
            runtime_request: None,
        }
    }
    pub fn with_request(mut self, request: RuntimeRequest) -> Self {
        self.request_id = Some(request.request_id.to_string());
        self.turn_id = request.turn_id.clone();
        self.item_id = request.item_id.clone();
        self.runtime_request = Some(request);
        self
    }
}
