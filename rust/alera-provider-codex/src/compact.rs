//! T3 Code's Codex `/compact`: a turn whose whole text is the command runs
//! `thread/compact/start` instead of `turn/start`, and the composer lists it.

use crate::provider::CodexProvider;
use crate::{events, wire};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderKind, ProviderSession, ProviderSlashCommand,
    ProviderSlashCommandsUpdate, TurnInput, TurnStartResult,
};
use serde_json::{json, Value};

const COMPACT_DESCRIPTION: &str = "Summarize the conversation and reduce context usage";

/// The detection T3 Code's run execution uses: no attachments and the
/// trimmed, lowercased text is exactly `/compact`.
pub(crate) fn is_compact_turn(input: &TurnInput) -> bool {
    input.attachments.is_empty() && input.input.trim().to_lowercase() == "/compact"
}

impl<T: JsonTransport> CodexProvider<T> {
    /// Queues `session.commands.updated` with the commands T3 Code lists for
    /// Codex: `/compact`, and `/feedback`, which clients run themselves.
    pub(crate) fn queue_session_commands(&mut self) {
        let Some(session) = self.session.as_ref() else {
            return;
        };
        let commands = [
            ProviderSlashCommand::from_native("compact", Some(COMPACT_DESCRIPTION), None),
            crate::feedback::feedback_command(),
        ]
        .into_iter()
        .flatten();
        let event = ProviderEvent::new(
            ProviderKind::Codex,
            self.config.instance_id.clone(),
            session.thread_id.clone(),
            EventKind::SessionCommandsUpdated,
            ProviderSlashCommandsUpdate::new(commands).payload(),
            None,
        );
        self.queued_events.push_back(event);
    }

    /// Starts a compaction and returns the native turn Codex runs it in.
    /// `thread/compact/start` answers without a turn, so this reads on until
    /// the root `turn/started` that follows it; every message read on the
    /// way is queued in order, so the turn's own events keep its native id.
    pub(crate) async fn start_compaction(
        &mut self,
        session: &ProviderSession,
    ) -> Result<TurnStartResult, ProviderError> {
        let queued_before = self.queued_events.len();
        self.call(
            "thread/compact/start",
            json!({ "threadId": session.native_thread_id }),
        )
        .await?;
        let started = self
            .queued_events
            .range(queued_before..)
            .find_map(|event| started_turn_id(event, &session.native_thread_id));
        let turn_id = match started {
            Some(turn_id) => turn_id,
            None => {
                self.await_compaction_turn(&session.native_thread_id)
                    .await?
            }
        };
        self.compaction_turn_id = Some(turn_id.clone());
        Ok(TurnStartResult {
            thread_id: session.thread_id.clone(),
            turn_id: turn_id.clone(),
            native_turn_id: Some(turn_id),
        })
    }

    async fn await_compaction_turn(
        &mut self,
        native_thread_id: &str,
    ) -> Result<String, ProviderError> {
        tokio::time::timeout(self.config.request_timeout, async {
            loop {
                let message = self.transport.recv().await?.ok_or(ProviderError::Closed)?;
                if self.absorb_skills_message(&message) {
                    continue;
                }
                if wire::method(&message).is_none() {
                    return Err(ProviderError::Protocol(
                        "Codex received an unsolicited response".into(),
                    ));
                }
                if self.queued_events.len() >= self.config.max_queued_events {
                    return Err(ProviderError::InvalidState(
                        "Codex notification queue is full".into(),
                    ));
                }
                let event = events::map_message(self, message)?;
                let started = started_turn_id(&event, native_thread_id);
                self.queued_events.push_back(event);
                if let Some(turn_id) = started {
                    return Ok(turn_id);
                }
            }
        })
        .await
        .map_err(|_| ProviderError::Timeout {
            operation: "thread/compact/start".into(),
        })?
    }

    /// T3 Code's orchestrator refuses both, so a compaction stays one turn.
    pub(crate) fn ensure_steerable(
        &self,
        input: &TurnInput,
        expected_turn_id: &str,
    ) -> Result<(), ProviderError> {
        crate::feedback::refuse_feedback_turn(input)?;
        if is_compact_turn(input) {
            return Err(ProviderError::Unsupported(
                "Context compaction must run as a separate turn. Queue it or wait for the active turn to finish."
                    .into(),
            ));
        }
        if self.compaction_turn_id.as_deref() == Some(expected_turn_id) {
            return Err(ProviderError::Unsupported(
                "Wait for context compaction to finish before steering the thread.".into(),
            ));
        }
        Ok(())
    }
}

/// The turn a `turn/started` on [native_thread_id] starts, as T3 Code keys
/// its pending root turns by the notification's thread.
fn started_turn_id(event: &ProviderEvent, native_thread_id: &str) -> Option<String> {
    let thread = event
        .raw
        .as_ref()
        .and_then(|raw| raw.payload.get("params"))
        .and_then(|params| params.get("threadId"))
        .and_then(Value::as_str);
    (event.kind == EventKind::TurnStarted && thread == Some(native_thread_id))
        .then(|| event.turn_id.clone())
        .flatten()
}
