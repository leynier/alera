//! Why a provider turn failed, as a small closed set. Adapters set a class
//! only from typed native fields (error codes, HTTP statuses, terminal
//! reasons), never by reading message text, so a client can show one curated
//! message per class next to the raw error, which is always kept.

use crate::{ProviderError, ProviderEvent};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FailureClass {
    /// A usage, quota or rate limit stopped the turn, including retries
    /// that gave up on HTTP 429.
    UsageLimit,
    /// The conversation no longer fits the model's context window.
    ContextWindowFull,
    /// The provider rejected the account's credentials.
    Auth,
    /// The provider refused a new turn while its previous one still runs.
    PreviousTurnActive,
    /// An attachment of the turn could not be read.
    AttachmentUnreadable,
    /// Anything else, including classes a newer adapter knows.
    #[default]
    #[serde(other)]
    Unknown,
}

impl FailureClass {
    pub fn is_unknown(self) -> bool {
        self == Self::Unknown
    }
}

impl ProviderError {
    /// The class of a turn that could not start; `Unknown` unless the
    /// adapter refused it for a fixed reason.
    pub fn failure_class(&self) -> FailureClass {
        match self {
            Self::Rejected { class, .. } => *class,
            _ => FailureClass::Unknown,
        }
    }
}

impl ProviderEvent {
    /// `failureClass` of a failed `turn.completed` or a `runtime.error`.
    pub fn failure_class(&self) -> FailureClass {
        self.payload
            .get("failureClass")
            .cloned()
            .and_then(|value| serde_json::from_value(value).ok())
            .unwrap_or_default()
    }

    /// A failed `turn.completed` whose native child turns keep running and
    /// will report their own `task.completed`, as after a completed turn.
    /// Without it, the turn's open child work ends with the turn.
    pub fn child_turns_continue(&self) -> bool {
        self.payload.get("childTurnsContinue") == Some(&Value::Bool(true))
    }

    /// A `task.*` the agent resumes from when it ends, so it holds the chat
    /// as working after the turn that started it. Native sub-agents are
    /// awaited; a background command or monitor is only when the agent said
    /// it waits on it.
    pub fn task_awaited(&self) -> bool {
        self.payload.get("awaited") == Some(&Value::Bool(true))
    }
}
