//! T3 Code's Codex `/goal`: the goal Codex keeps on the thread, published as
//! `session.goal.updated`, and the turns Codex starts on its own for it.
//!
//! While a goal is active, a completed root turn is held for a short grace
//! window. When Codex starts the next turn inside it, the held completion is
//! released with `goalContinuation` naming that turn, so the host carries its
//! run on into it; otherwise the goal is paused and the turn settles. A root
//! turn Codex starts with no run to own it is paused and stopped.

use std::collections::HashSet;
use std::time::Duration;

use alera_provider_protocol::{
    EventKind, ProviderEvent, ProviderGoal, ProviderGoalStatus, ProviderGoalUpdate, ProviderKind,
    ProviderSlashCommand,
};
use serde_json::{json, Value};
use tokio::time::Instant;

use crate::provider::CodexProvider;
use crate::wire;

/// Codex starts the next goal turn milliseconds after the last one completes.
pub(crate) const GOAL_CONTINUATION_GRACE: Duration = Duration::from_secs(5);

const GOAL_DESCRIPTION: &str = "Set a goal Codex keeps working toward until it is done";
const GOAL_HINT: &str = "Objective, or pause, resume, clear";

/// A completed root turn waiting to learn whether Codex continues the goal.
pub(crate) struct GoalHold {
    pub completion: ProviderEvent,
    pub native_turn_id: String,
    pub deadline: Instant,
}

#[derive(Default)]
pub(crate) struct GoalState {
    /// The goal as Codex last reported it.
    pub current: Option<ProviderGoal>,
    /// The goal last announced with `session.goal.updated`; `None` until
    /// the first announcement, which the host may hold an older goal than.
    pub published: Option<Option<ProviderGoal>>,
    /// Setting a goal passes through cleared and paused states; only the
    /// result is announced.
    pub updates_held: bool,
    pub hold: Option<GoalHold>,
    /// `Some(stopped)` while a set or resume waits to activate its goal. A
    /// first turn that does not complete in that window stops activation.
    pub activation: Option<bool>,
    /// A pause Alera sent has not been confirmed yet, so a turn Codex starts
    /// meanwhile has no run to own it.
    pub stopping: bool,
    /// Set while Alera itself starts a root turn.
    pub starting_turn: bool,
    /// The root turn Alera started, until its `turn/started` arrives.
    pub expected_turn: Option<String>,
    pub orphan_turns: HashSet<String>,
    /// Requests decided while reading a message, sent at the next await.
    pub deferred_requests: Vec<(&'static str, Value)>,
    /// The app-server answered a goal method as unknown.
    pub unsupported: bool,
    pub command_seq: u64,
}

impl GoalState {
    pub(crate) fn active(&self) -> bool {
        self.current
            .as_ref()
            .is_some_and(|goal| goal.status == ProviderGoalStatus::Active)
    }

    /// Whether goal work is in progress: an active goal, a held turn, or an
    /// activation that has not finished.
    pub(crate) fn working(&self) -> bool {
        self.active() || self.hold.is_some() || self.activation.is_some()
    }

    pub(crate) fn reset(&mut self) {
        let unsupported = self.unsupported;
        let command_seq = self.command_seq;
        *self = Self {
            unsupported,
            command_seq,
            ..Self::default()
        };
    }
}

/// T3 Code's `providerGoalFromCodex`. `None` for a blank objective or a
/// status this version does not know.
pub(crate) fn goal_from_codex(goal: &Value) -> Option<ProviderGoal> {
    let objective = goal.get("objective")?.as_str()?.trim();
    if objective.is_empty() {
        return None;
    }
    let status = match goal.get("status")?.as_str()? {
        "active" => ProviderGoalStatus::Active,
        "paused" => ProviderGoalStatus::Paused,
        "blocked" => ProviderGoalStatus::Blocked,
        "usageLimited" => ProviderGoalStatus::UsageLimited,
        "budgetLimited" => ProviderGoalStatus::BudgetLimited,
        "complete" => ProviderGoalStatus::Complete,
        _ => return None,
    };
    let count = |key: &str| {
        goal.get(key)
            .and_then(Value::as_i64)
            .map(|value| value.max(0) as u64)
    };
    Some(ProviderGoal {
        objective: objective.to_owned(),
        status,
        tokens_used: count("tokensUsed"),
        token_budget: count("tokenBudget"),
        time_used_seconds: count("timeUsedSeconds"),
    })
}

pub(crate) fn goal_command() -> Option<ProviderSlashCommand> {
    ProviderSlashCommand::from_native("goal", Some(GOAL_DESCRIPTION), Some(GOAL_HINT))
}

fn turn_id(params: &Value) -> Option<String> {
    wire::string(params, "turnId").or_else(|| wire::nested_string(params, "turn", "id"))
}

impl<T> CodexProvider<T> {
    fn root_thread<'a>(&self, params: &'a Value) -> Option<&'a str> {
        let thread = params.get("threadId").and_then(Value::as_str)?;
        self.session
            .as_ref()
            .is_some_and(|session| session.native_thread_id == thread)
            .then_some(thread)
    }

    /// Announces the goal when it changed since the last announcement.
    pub(crate) fn goal_update_event(&mut self) -> Option<ProviderEvent> {
        if self.goal.updates_held || self.goal.published.as_ref() == Some(&self.goal.current) {
            return None;
        }
        let session = self.session.as_ref()?;
        self.goal.published = Some(self.goal.current.clone());
        Some(ProviderEvent::new(
            ProviderKind::Codex,
            self.config.instance_id.clone(),
            session.thread_id.clone(),
            EventKind::SessionGoalUpdated,
            ProviderGoalUpdate {
                goal: self.goal.current.clone(),
            }
            .payload(),
            None,
        ))
    }

    pub(crate) fn queue_goal_update(&mut self) {
        if let Some(event) = self.goal_update_event() {
            self.queued_events.push_back(event);
        }
    }

    pub(crate) fn set_goal(&mut self, goal: Option<ProviderGoal>) {
        self.goal.current = goal;
        if !self.goal.active() {
            self.goal.stopping = false;
        }
    }

    /// Pauses the goal without waiting for Codex: the answer is dropped and
    /// the `thread/goal/updated` that follows confirms it.
    pub(crate) fn defer_goal_pause(&mut self, native_thread_id: &str) {
        self.goal.deferred_requests.push((
            "thread/goal/set",
            json!({ "threadId": native_thread_id, "status": "paused" }),
        ));
        if let Some(goal) = self.goal.current.as_mut() {
            goal.status = ProviderGoalStatus::Paused;
        }
        self.goal.stopping = true;
        self.queue_goal_update();
    }

    /// Releases the held turn as it completed.
    pub(crate) fn release_goal_hold(&mut self) {
        if let Some(hold) = self.goal.hold.take() {
            self.queued_events.push_back(hold.completion);
        }
    }

    /// Before mapping a message: drops the notifications of a root turn
    /// Codex started with no run to own it, pausing the goal and stopping
    /// that turn the first time.
    pub(crate) fn drops_goal_orphan(&mut self, method: &str, params: &Value) -> bool {
        let Some(thread) = self.root_thread(params).map(str::to_owned) else {
            return false;
        };
        let turn = turn_id(params);
        if let Some(turn) = turn.as_deref() {
            if self.goal.orphan_turns.contains(turn) {
                if matches!(method, "turn/completed" | "turn/aborted") {
                    self.goal.orphan_turns.remove(turn);
                }
                return true;
            }
        }
        let orphan = method == "turn/started"
            && !self.owns_started_turn(turn.as_deref())
            && self.goal.hold.is_none()
            && (self.goal.active() || self.goal.stopping);
        let Some(turn) = turn.filter(|_| orphan) else {
            return false;
        };
        if self.goal.active() {
            self.defer_goal_pause(&thread);
        }
        self.goal.deferred_requests.push((
            "turn/interrupt",
            json!({ "threadId": thread, "turnId": turn }),
        ));
        self.goal.orphan_turns.insert(turn);
        true
    }

    fn owns_started_turn(&self, turn: Option<&str>) -> bool {
        self.goal.starting_turn || (turn.is_some() && self.goal.expected_turn.as_deref() == turn)
    }

    /// After mapping a root notification: tracks the goal, holds a completed
    /// turn while the goal continues, and releases it into the next one.
    /// Returns what to queue in place of [event]; extra events it queues
    /// itself go first.
    pub(crate) fn apply_goal_notification(
        &mut self,
        method: &str,
        params: &Value,
        mut event: ProviderEvent,
    ) -> Option<ProviderEvent> {
        if self.root_thread(params).is_none() {
            return Some(event);
        }
        match method {
            "thread/goal/updated" => {
                let Some(goal) = params.get("goal").and_then(goal_from_codex) else {
                    return Some(event);
                };
                let active = goal.status == ProviderGoalStatus::Active;
                self.set_goal(Some(goal));
                let update = self.goal_update_event();
                if active {
                    return update;
                }
                self.queued_events.extend(update);
                self.release_goal_hold();
                None
            }
            "thread/goal/cleared" => {
                self.set_goal(None);
                let update = self.goal_update_event();
                self.queued_events.extend(update);
                self.release_goal_hold();
                None
            }
            "turn/started" => {
                let turn = turn_id(params);
                if self.owns_started_turn(turn.as_deref()) {
                    if turn.is_some() && self.goal.expected_turn == turn {
                        self.goal.expected_turn = None;
                    }
                    return Some(event);
                }
                if let (Some(mut hold), Some(turn)) = (self.goal.hold.take(), turn) {
                    hold.completion.payload["goalContinuation"] = json!({ "nextTurnId": turn });
                    self.queued_events.push_back(hold.completion);
                    event.payload["goalContinuation"] = Value::Bool(true);
                }
                Some(event)
            }
            "turn/completed" => {
                let completed = event.payload["state"] == "completed";
                if !completed {
                    if let Some(stopped) = self.goal.activation.as_mut() {
                        *stopped = true;
                    }
                }
                let continues = self.goal.active() || self.goal.activation == Some(false);
                let turn = turn_id(params);
                match turn {
                    Some(native_turn_id) if completed && continues && !self.goal.unsupported => {
                        self.release_goal_hold();
                        self.goal.hold = Some(GoalHold {
                            completion: event,
                            native_turn_id,
                            deadline: Instant::now() + GOAL_CONTINUATION_GRACE,
                        });
                        None
                    }
                    _ => Some(event),
                }
            }
            "turn/aborted" => {
                if let Some(stopped) = self.goal.activation.as_mut() {
                    *stopped = true;
                }
                Some(event)
            }
            _ => Some(event),
        }
    }

    /// The session commands Codex runs: `/compact` always, `/goal` unless
    /// this app-server does not know the goal methods.
    pub(crate) fn session_command_list(&self) -> Vec<ProviderSlashCommand> {
        let mut commands: Vec<ProviderSlashCommand> =
            crate::compact::compact_command().into_iter().collect();
        if !self.goal.unsupported {
            commands.extend(goal_command());
        }
        commands.extend(crate::feedback::feedback_command());
        commands
    }
}
