//! `agentChat.feedback`, T3 Code's `provider.uploadFeedback`: the live
//! provider sends its native thread and logs to its vendor. The person
//! confirmed the upload on the client, and the transcript does not change.

use alera_provider_protocol::{FeedbackUploadInput, ProviderError};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, turn_active, unsupported};
use super::session::ChatSession;

/// The adapters that implement `Provider::upload_feedback`, known before a
/// provider runs so an idle chat answers for the right reason.
fn uploads_feedback(provider: &str) -> bool {
    provider == "codex"
}

impl ChatSession {
    /// Uploads feedback for this chat's native thread. The provider call holds
    /// the actor as `/compact` does, so a running turn is refused: its events
    /// would pile up behind an upload that can take a while.
    pub(super) async fn upload_feedback(&mut self, reason: Option<String>) -> HostResult<Value> {
        if !uploads_feedback(&self.header.provider) {
            return Err(unsupported(
                "This chat's agent does not support feedback uploads.",
            ));
        }
        if self.never_sent() {
            return Err(conflict(
                "feedbackNeedsConversation",
                "Send a message before you submit feedback.",
            ));
        }
        if self.is_busy() {
            return Err(turn_active(
                "Wait for the current turn to finish before you send feedback.",
            ));
        }
        let provider = self.provider.as_mut().ok_or_else(provider_not_running)?;
        let result = provider
            .upload_feedback(FeedbackUploadInput::new(reason.as_deref()))
            .await;
        // Codex queues what it read while it waited; poll it again.
        self.events_armed = true;
        match result {
            Ok(result) => Ok(json!({"feedbackId": result.feedback_id})),
            Err(ProviderError::Unsupported(_)) => Err(unsupported(
                "This chat's agent does not support feedback uploads.",
            )),
            Err(ProviderError::Closed | ProviderError::InvalidState(_)) => {
                Err(provider_not_running())
            }
            Err(ProviderError::Rpc { message, .. }) => Err(feedback_failed(&message)),
            Err(ProviderError::Timeout { .. }) => Err(feedback_failed(
                "The agent did not answer the upload in time.",
            )),
            Err(error) => {
                tracing::warn!(chat_id = %self.header.chat_id, error = %error, "feedback upload failed");
                Err(feedback_failed("The agent could not upload the feedback."))
            }
        }
    }
}

fn provider_not_running() -> HostError {
    conflict(
        "providerUnavailable",
        "The agent session is no longer running. Send a message first.",
    )
}

fn feedback_failed(detail: &str) -> HostError {
    conflict("feedbackFailed", detail)
}

#[cfg(test)]
mod tests {
    use super::uploads_feedback;

    #[test]
    fn only_codex_uploads_feedback() {
        assert!(uploads_feedback("codex"));
        for provider in super::super::provider_traits::PROVIDERS {
            assert_eq!(uploads_feedback(provider), provider == "codex");
        }
    }
}
