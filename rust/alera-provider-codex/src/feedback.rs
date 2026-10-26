//! T3 Code's Codex `/feedback`: the thread and Codex's logs go to OpenAI
//! through `feedback/upload`, only when the person asks for it. Clients run
//! the command through `upload_feedback` after asking for consent, so a turn
//! whose whole text is the command is refused rather than sent to the model.

use crate::provider::CodexProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    FeedbackUploadInput, FeedbackUploadResult, ProviderError, ProviderSlashCommand, TurnInput,
};
use serde_json::{json, Value};

const FEEDBACK_COMMAND: &str = "feedback";
const FEEDBACK_DESCRIPTION: &str = "Send this thread and Codex logs to OpenAI";
const FEEDBACK_HINT: &str = "Describe the issue (optional)";

pub(crate) fn feedback_command() -> Option<ProviderSlashCommand> {
    ProviderSlashCommand::from_native(
        FEEDBACK_COMMAND,
        Some(FEEDBACK_DESCRIPTION),
        Some(FEEDBACK_HINT),
    )
}

/// T3 Code's `parseCodexFeedbackCommand`: no attachments and the trimmed
/// text is `/feedback`, in any case, alone or followed by white space.
pub(crate) fn is_feedback_turn(input: &TurnInput) -> bool {
    if !input.attachments.is_empty() {
        return false;
    }
    let text = input.input.trim();
    let Some(head) = text.get(..FEEDBACK_COMMAND.len() + 1) else {
        return false;
    };
    let rest = &text[head.len()..];
    head.eq_ignore_ascii_case("/feedback") && rest.chars().next().is_none_or(char::is_whitespace)
}

pub(crate) fn refuse_feedback_turn(input: &TurnInput) -> Result<(), ProviderError> {
    if is_feedback_turn(input) {
        return Err(ProviderError::Unsupported(
            "Codex feedback is sent with the chat's /feedback command, which asks before uploading anything to OpenAI."
                .into(),
        ));
    }
    Ok(())
}

impl<T: JsonTransport> CodexProvider<T> {
    /// `feedback/upload` as T3 Code's `CodexAdapterV2.uploadFeedback` sends
    /// it; Codex answers with the thread id OpenAI files the report under.
    pub(crate) async fn upload_feedback_native(
        &mut self,
        input: FeedbackUploadInput,
    ) -> Result<FeedbackUploadResult, ProviderError> {
        self.ensure_open()?;
        let native_thread_id = self
            .session
            .as_ref()
            .map(|session| session.native_thread_id.clone())
            .ok_or_else(|| ProviderError::InvalidState("start a Codex session first".into()))?;
        let mut params = json!({
            "classification": "bug",
            "includeLogs": true,
            "threadId": native_thread_id,
        });
        if let Some(reason) = FeedbackUploadInput::new(input.reason.as_deref()).reason {
            params["reason"] = Value::String(reason);
        }
        let response = self.call("feedback/upload", params).await?;
        let feedback_id = response
            .get("threadId")
            .and_then(Value::as_str)
            .filter(|id| !id.trim().is_empty())
            .ok_or_else(|| {
                ProviderError::Protocol("Codex feedback/upload returned no threadId".into())
            })?;
        Ok(FeedbackUploadResult {
            feedback_id: feedback_id.to_owned(),
        })
    }
}
