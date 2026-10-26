//! T3 Code's `runGoalCommand`: `/goal` turns read and change the thread's
//! goal through `thread/goal/{get,set,clear}`. Show, pause and clear settle
//! as a turn that never reaches Codex; set and resume start the first goal
//! turn with this turn's configuration and only then activate the goal.

use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    GoalCommand, ProviderError, ProviderGoal, ProviderSession, SessionStatus, TurnInput,
    TurnStartResult,
};
use serde_json::{json, Value};

use crate::goal::goal_from_codex;
use crate::provider::CodexProvider;

const NO_GOAL: &str = "No goal is set.";
const UNSUPPORTED: &str = "This Codex version does not support goals.";
/// JSON-RPC "method not found".
const METHOD_NOT_FOUND: i64 = -32601;

/// Native turn ids of goal command turns, which never reach Codex.
pub(crate) const GOAL_COMMAND_TURN_PREFIX: &str = "goal-command:";

impl<T: JsonTransport> CodexProvider<T> {
    pub(crate) async fn run_goal_command(
        &mut self,
        command: GoalCommand,
        input: &TurnInput,
        session: &ProviderSession,
    ) -> Result<TurnStartResult, ProviderError> {
        let result = self.goal_command_inner(command, input, session).await;
        if self.goal.updates_held {
            self.goal.updates_held = false;
            self.queue_goal_update();
        }
        match result {
            Err(ProviderError::Rpc { code, .. }) if code == METHOD_NOT_FOUND => {
                self.goal.unsupported = true;
                self.goal.activation = None;
                self.queue_session_commands();
                Ok(self.complete_goal_command_turn(session, Some(UNSUPPORTED)))
            }
            other => other,
        }
    }

    async fn goal_command_inner(
        &mut self,
        command: GoalCommand,
        input: &TurnInput,
        session: &ProviderSession,
    ) -> Result<TurnStartResult, ProviderError> {
        let thread = session.native_thread_id.clone();
        let response = self
            .call("thread/goal/get", json!({ "threadId": thread }))
            .await?;
        let current = response.get("goal").and_then(goal_from_codex);
        self.set_goal(current.clone());
        let reply = match (&command, &current) {
            (GoalCommand::Show, None) => Some(NO_GOAL.to_owned()),
            (GoalCommand::Show, Some(goal)) => Some(goal.describe()),
            (GoalCommand::Clear, _) => {
                let response = self
                    .call("thread/goal/clear", json!({ "threadId": thread }))
                    .await?;
                self.set_goal(None);
                let cleared = response.get("cleared").and_then(Value::as_bool) == Some(true);
                (!cleared).then(|| NO_GOAL.to_owned())
            }
            (GoalCommand::Pause | GoalCommand::Resume, None) => Some(NO_GOAL.to_owned()),
            (GoalCommand::Pause, Some(_)) => {
                self.set_goal_status(&thread, "paused").await?;
                None
            }
            (GoalCommand::Set(_) | GoalCommand::Resume, _) => {
                return self.start_goal(command, input, session, current).await;
            }
        };
        self.queue_goal_update();
        Ok(self.complete_goal_command_turn(session, reply.as_deref()))
    }

    async fn set_goal_status(&mut self, thread: &str, status: &str) -> Result<(), ProviderError> {
        let response = self
            .call(
                "thread/goal/set",
                json!({ "threadId": thread, "status": status }),
            )
            .await?;
        if let Some(goal) = response.get("goal").and_then(goal_from_codex) {
            self.set_goal(Some(goal));
        }
        Ok(())
    }

    /// Keeps the goal paused until the first goal turn starts, so Codex
    /// cannot start one first, then activates it unless that turn stopped.
    async fn start_goal(
        &mut self,
        command: GoalCommand,
        input: &TurnInput,
        session: &ProviderSession,
        current: Option<ProviderGoal>,
    ) -> Result<TurnStartResult, ProviderError> {
        let thread = session.native_thread_id.clone();
        let mut turn_input = input.clone();
        if let GoalCommand::Set(objective) = &command {
            self.goal.updates_held = true;
            if current.is_some() {
                self.call("thread/goal/clear", json!({ "threadId": thread }))
                    .await?;
                self.set_goal(None);
            }
            let response = self
                .call(
                    "thread/goal/set",
                    json!({ "threadId": thread, "objective": objective, "status": "paused" }),
                )
                .await?;
            self.set_goal(response.get("goal").and_then(goal_from_codex));
            // A bare objective reads like a statement the model echoes back.
            turn_input.input = format!("Start working toward this goal: {objective}");
        } else {
            turn_input.input = String::new();
        }
        self.goal.activation = Some(false);
        let started = self.start_root_turn(&turn_input, session).await;
        let activated = match started {
            Ok(result) => self.activate_goal(&thread).await.map(|()| result),
            Err(error) => Err(error),
        };
        self.goal.activation = None;
        if !self.goal.active() {
            self.release_goal_hold();
        }
        self.flush_goal_requests().await?;
        self.queue_goal_update();
        activated
    }

    async fn activate_goal(&mut self, thread: &str) -> Result<(), ProviderError> {
        if self.goal.activation == Some(true) {
            return Ok(());
        }
        self.set_goal_status(thread, "active").await?;
        if self.goal.activation == Some(true) {
            self.set_goal_status(thread, "paused").await?;
        }
        Ok(())
    }

    /// `turn/start` for a root turn Alera starts, marking the turn as its
    /// own so the goal never reads it as one Codex started.
    pub(crate) async fn start_root_turn(
        &mut self,
        input: &TurnInput,
        session: &ProviderSession,
    ) -> Result<TurnStartResult, ProviderError> {
        let params = self.turn_params(input, session)?;
        self.goal.starting_turn = true;
        let response = self.call("turn/start", Value::Object(params)).await;
        self.goal.starting_turn = false;
        let native_turn_id = Self::decode_turn_id(&response?)?;
        let started = self
            .session
            .as_ref()
            .and_then(|session| session.active_turn_id.as_deref())
            == Some(native_turn_id.as_str());
        if !started {
            self.goal.expected_turn = Some(native_turn_id.clone());
        }
        let waiting_for_request = !self.pending_requests.is_empty();
        if let Some(session) = self.session.as_mut() {
            session.status = if waiting_for_request {
                SessionStatus::Waiting
            } else {
                SessionStatus::Running
            };
            session.active_turn_id = Some(native_turn_id.clone());
        }
        Ok(TurnStartResult {
            thread_id: session.thread_id.clone(),
            turn_id: native_turn_id.clone(),
            native_turn_id: Some(native_turn_id),
        })
    }

    /// T3 Code's `completeGoalCommandTurn`: a turn with the reply, if any,
    /// that settles without reaching Codex. Goal changes answer through the
    /// goal itself.
    fn complete_goal_command_turn(
        &mut self,
        session: &ProviderSession,
        reply: Option<&str>,
    ) -> TurnStartResult {
        self.goal.command_seq += 1;
        let turn = format!("{GOAL_COMMAND_TURN_PREFIX}{}", self.goal.command_seq);
        let thread = session.native_thread_id.clone();
        let mut messages = vec![(
            "turn/started",
            json!({ "threadId": thread, "turn": { "id": turn, "status": "inProgress", "items": [] } }),
        )];
        if let Some(reply) = reply {
            messages.push((
                "item/completed",
                json!({
                    "threadId": thread,
                    "turnId": turn,
                    "item": { "id": format!("{turn}:reply"), "type": "agentMessage", "text": reply },
                }),
            ));
        }
        messages.push((
            "turn/completed",
            json!({ "threadId": thread, "turn": { "id": turn, "status": "completed", "items": [] } }),
        ));
        for (method, params) in messages {
            match crate::events::map_synthetic(self, method, params) {
                Ok(event) => self.queued_events.push_back(event),
                Err(error) => {
                    // The shapes above are fixed; only a broken contract fails.
                    debug_assert!(false, "goal command turn event: {error}");
                }
            }
        }
        TurnStartResult {
            thread_id: session.thread_id.clone(),
            turn_id: turn.clone(),
            native_turn_id: Some(turn),
        }
    }
}
