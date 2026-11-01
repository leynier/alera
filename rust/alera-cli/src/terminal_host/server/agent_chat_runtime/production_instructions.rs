//! Delivers a chat's orchestration instructions (`ProviderLaunch::instructions`)
//! to providers that have no system prompt flag. Claude takes them on its
//! argv (`production_launch_config`). Codex takes them as the thread's
//! `developerInstructions` on start, resume and fork. Every other provider
//! receives them wrapped around the first prompt it can carry after each
//! session start, and again after a context compaction.

use alera_provider_protocol::{
    EventKind, FeedbackUploadInput, FeedbackUploadResult, InterruptInput, NativeForkInput,
    NativeForkResult, NativeHistoryCapabilities, NativeRewindFilesInput, NativeRewindFilesResult,
    NativeRollbackInput, NativeRollbackResult, Provider, ProviderCapabilities, ProviderError,
    ProviderEvent, ProviderKind, ProviderSession, ReasoningEffortCapabilities, RuntimeResponse,
    SessionStartInput, SubagentCapabilities, TurnInput, TurnStartResult, MAX_TURN_INPUT_CHARS,
};
use async_trait::async_trait;
use serde_json::Value;

use super::BoxedProvider;

const DEVELOPER_INSTRUCTIONS: &str = "developerInstructions";

enum Delivery {
    /// Codex thread options.
    Session,
    /// The first eligible prompt after a session start.
    Prompt { pending: bool },
}

pub(crate) struct InstructedProvider {
    inner: BoxedProvider,
    provider: String,
    text: String,
    delivery: Delivery,
}

/// Wraps `inner` when the launch carries instructions its provider needs
/// delivered here; Claude and launches without them pass through.
pub(crate) fn instructed(
    inner: BoxedProvider,
    provider: &str,
    sections: &[String],
) -> BoxedProvider {
    if sections.is_empty() || provider == "claudeAgent" {
        return inner;
    }
    Box::new(InstructedProvider {
        inner,
        provider: provider.to_owned(),
        text: sections.join("\n\n"),
        delivery: if provider == "codex" {
            Delivery::Session
        } else {
            Delivery::Prompt { pending: false }
        },
    })
}

/// A slash command, or a Cursor `$skill` lead, goes to the provider as is.
fn passes_through(provider: &str, input: &str) -> bool {
    let Some(first) = input.split_whitespace().next() else {
        return true;
    };
    (first.starts_with('/') && !first[1..].contains('/'))
        || (provider == "cursor" && first.starts_with('$'))
}

impl InstructedProvider {
    fn wrapped(&self, input: &str) -> Option<String> {
        if passes_through(&self.provider, input) {
            return None;
        }
        let wrapped = format!(
            "<alera_orchestration_instructions>\n{}\n</alera_orchestration_instructions>\n\n<user_request>\n{input}\n</user_request>",
            self.text
        );
        (wrapped.encode_utf16().count() <= MAX_TURN_INPUT_CHARS).then_some(wrapped)
    }

    fn arm(&mut self) {
        if let Delivery::Prompt { pending } = &mut self.delivery {
            *pending = true;
        }
    }

    fn with_session_instructions(&self, mut input: SessionStartInput) -> SessionStartInput {
        if matches!(self.delivery, Delivery::Session) {
            input.options.insert(
                DEVELOPER_INSTRUCTIONS.into(),
                Value::String(self.text.clone()),
            );
        }
        input
    }
}

#[async_trait]
impl Provider for InstructedProvider {
    fn kind(&self) -> ProviderKind {
        self.inner.kind()
    }
    fn capabilities(&self) -> ProviderCapabilities {
        self.inner.capabilities()
    }
    fn reasoning_effort_capabilities(&self) -> ReasoningEffortCapabilities {
        self.inner.reasoning_effort_capabilities()
    }
    fn native_history_capabilities(&self) -> NativeHistoryCapabilities {
        self.inner.native_history_capabilities()
    }
    fn subagent_capabilities(&self) -> SubagentCapabilities {
        self.inner.subagent_capabilities()
    }
    fn session(&self) -> Option<&ProviderSession> {
        self.inner.session()
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.inner.initialize().await
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        let input = self.with_session_instructions(input);
        let session = self.inner.start_session(input).await?;
        self.arm();
        Ok(session)
    }
    async fn send_turn(&mut self, mut input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        let wrapped = match self.delivery {
            Delivery::Prompt { pending: true } => self.wrapped(&input.input),
            _ => None,
        };
        let Some(wrapped) = wrapped else {
            return self.inner.send_turn(input).await;
        };
        input.input = wrapped;
        let started = self.inner.send_turn(input).await?;
        self.delivery = Delivery::Prompt { pending: false };
        Ok(started)
    }
    async fn steer_turn(
        &mut self,
        input: TurnInput,
        expected_turn_id: &str,
    ) -> Result<(), ProviderError> {
        self.inner.steer_turn(input, expected_turn_id).await
    }
    async fn fork_session(
        &mut self,
        mut input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        input.session = self.with_session_instructions(input.session);
        let forked = self.inner.fork_session(input).await?;
        self.arm();
        Ok(forked)
    }
    async fn rollback_session(
        &mut self,
        input: NativeRollbackInput,
    ) -> Result<NativeRollbackResult, ProviderError> {
        self.inner.rollback_session(input).await
    }
    async fn rewind_files(
        &mut self,
        input: NativeRewindFilesInput,
    ) -> Result<NativeRewindFilesResult, ProviderError> {
        self.inner.rewind_files(input).await
    }
    async fn await_background_tasks(
        &mut self,
        task_ids: &[String],
        awaited: bool,
    ) -> Result<Vec<String>, ProviderError> {
        self.inner.await_background_tasks(task_ids, awaited).await
    }
    async fn upload_feedback(
        &mut self,
        input: FeedbackUploadInput,
    ) -> Result<FeedbackUploadResult, ProviderError> {
        self.inner.upload_feedback(input).await
    }
    async fn stop_subagent(&mut self, task_id: &str) -> Result<(), ProviderError> {
        self.inner.stop_subagent(task_id).await
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.inner.interrupt(input).await
    }
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.inner.respond(response).await
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        let event = self.inner.next_event().await?;
        // A compaction drops what the first prompt carried.
        if let Some(event) = &event {
            if matches!(
                event.kind,
                EventKind::ItemStarted | EventKind::ItemCompleted
            ) && event.payload["itemType"] == "context_compaction"
            {
                self.arm();
            }
        }
        Ok(event)
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        self.inner.close().await
    }
}

#[cfg(test)]
#[path = "production_instructions_tests.rs"]
mod tests;
