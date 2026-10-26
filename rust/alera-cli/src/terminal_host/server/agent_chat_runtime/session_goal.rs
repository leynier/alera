//! The agent's goal (Codex `/goal`): its state on the session, the turns the
//! agent starts on its own to keep working toward it, and T3 Code's rule
//! that a goal command never joins a running turn.

use alera_provider_protocol::{parse_goal_command, ProviderEvent, ProviderGoalUpdate};
use serde_json::Value;

use crate::terminal_host::host_error::HostResult;

use super::commands::{CallerCtx, SendInput};
use super::ids::{new_id, now};
use super::session::ChatSession;
use super::session_turns::TurnEnd;
use super::wire::ChatTurn;

/// `ChatTurn.origin` of a turn the agent started for its goal.
pub(super) const GOAL_CONTINUATION_ORIGIN: &str = "goalContinuation";

impl ChatSession {
    pub(super) fn apply_goal_update(&mut self, event: &ProviderEvent) {
        let Ok(update) = serde_json::from_value::<ProviderGoalUpdate>(event.payload.clone()) else {
            return;
        };
        if self.header.session.goal != update.goal {
            self.header.session.goal = update.goal;
            self.pending.session();
        }
    }

    /// Ends the running turn. When the provider says the goal continues
    /// into [next_native_turn], that turn becomes the running one in the
    /// same step, so nothing queued starts and the chat never reads idle.
    pub(super) async fn end_turn_into_goal(&mut self, end: TurnEnd, next_native_turn: &str) {
        let previous = self
            .header
            .session
            .active_turn_id
            .clone()
            .and_then(|turn_id| self.header.turns.iter().find(|t| t.turn_id == turn_id))
            .map(|turn| (turn.model.clone(), turn.reasoning_effort.clone()));
        let continues = end.status == "completed" && self.provider.is_some();
        self.goal_continuing = continues;
        self.end_turn(end).await;
        if continues {
            let (model, reasoning_effort) = previous.unwrap_or_else(|| {
                (
                    self.header.session.model.clone(),
                    self.header.session.reasoning_effort.clone(),
                )
            });
            self.adopt_native_turn(
                next_native_turn,
                model,
                reasoning_effort,
                GOAL_CONTINUATION_ORIGIN,
            )
            .await;
        }
        self.goal_continuing = false;
    }

    /// Starts the app turn for a native turn the agent started on its own.
    /// It has no user message; its origin says why it runs. Codex reuses the
    /// last turn's settings for it, so the turn records those.
    pub(super) async fn adopt_native_turn(
        &mut self,
        native_turn: &str,
        model: Option<String>,
        reasoning_effort: Option<String>,
        origin: &str,
    ) {
        if self.header.session.active_turn_id.is_some() {
            return;
        }
        let turn = ChatTurn {
            turn_id: new_id("turn"),
            status: "running".into(),
            started_at: now(),
            completed_at: None,
            error_message: None,
            failure_class: None,
            reason: None,
            model,
            reasoning_effort,
            provider: self.header.provider.clone(),
            provider_instance_id: self.header.provider_instance_id.clone(),
            generation: self.generation,
            origin: Some(origin.into()),
        };
        let turn_id = turn.turn_id.clone();
        self.header.upsert_turn(turn);
        self.header.session.active_turn_id = Some(turn_id.clone());
        self.provider_turn_id = Some(native_turn.to_string());
        self.map_native_turn(native_turn, &turn_id).await;
        self.set_status("running");
        let _ = self.flush().await;
    }

    fn offers_goal(&self) -> bool {
        self.header
            .session
            .commands
            .iter()
            .any(|command| command.name.eq_ignore_ascii_case("goal"))
    }

    /// T3 Code's goal command dispatch while a turn runs: one that starts or
    /// ends goal work goes first in the queue and stops the turn; the rest
    /// wait their turn. A send that asked to be queued only queues. Hands
    /// [input] back when it is not a goal command sent over a running turn.
    pub(super) async fn admit_goal_command(
        &mut self,
        input: SendInput,
        ctx: &CallerCtx,
    ) -> HostResult<Result<Value, SendInput>> {
        if input.delivery != "auto"
            || self.header.session.active_turn_id.is_none()
            || !self.offers_goal()
        {
            return Ok(Err(input));
        }
        let Some(command) = parse_goal_command(&input.text, !input.attachments.is_empty()) else {
            return Ok(Err(input));
        };
        let status = self.header.session.goal.as_ref().map(|goal| goal.status);
        let response = self.enqueue(input, ctx);
        if !command.stops_active_turn(status) || self.active_turn_is_compaction() {
            return Ok(Ok(response));
        }
        if let Some(entry) = self.header.queue.pop() {
            self.header.queue.insert(0, entry);
        }
        // A failed stop leaves the command waiting for the turn to end.
        if let Err(error) = self.interrupt(None).await {
            tracing::warn!(chat_id = %self.header.chat_id, error = %error, "goal command could not stop the running turn");
        }
        // A turn that never reached a provider ends here, not through events.
        self.drain_queue().await;
        Ok(Ok(response))
    }

    /// T3 Code never stops a context compaction for a goal command.
    fn active_turn_is_compaction(&self) -> bool {
        let Some(turn_id) = self.header.session.active_turn_id.as_deref() else {
            return false;
        };
        self.items.values().any(|item| {
            item.turn_id.as_deref() == Some(turn_id)
                && item.item_type == "user_message"
                && item
                    .text
                    .as_deref()
                    .is_some_and(|text| text.trim().eq_ignore_ascii_case("/compact"))
        })
    }
}
