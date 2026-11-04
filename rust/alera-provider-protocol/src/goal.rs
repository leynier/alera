//! A provider's long-running goal (Codex `/goal`), in the shape of T3 Code's
//! `OrchestrationV2ProviderGoal`, and the `/goal` control command.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::ProviderEvent;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderGoalStatus {
    Active,
    Paused,
    Blocked,
    UsageLimited,
    BudgetLimited,
    Complete,
}

impl ProviderGoalStatus {
    /// The wire word with its underscore read as a space, as T3 Code's
    /// `describeCodexGoal` prints it.
    pub fn label(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Paused => "paused",
            Self::Blocked => "blocked",
            Self::UsageLimited => "usage limited",
            Self::BudgetLimited => "budget limited",
            Self::Complete => "complete",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderGoal {
    pub objective: String,
    pub status: ProviderGoalStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tokens_used: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_budget: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub time_used_seconds: Option<u64>,
}

impl ProviderGoal {
    /// `Goal <status>: <objective>`, the reply to `/goal` with no argument.
    pub fn describe(&self) -> String {
        format!("Goal {}: {}", self.status.label(), self.objective)
    }
}

/// The payload of `session.goal.updated`: the whole goal, or none.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderGoalUpdate {
    #[serde(default)]
    pub goal: Option<ProviderGoal>,
}

impl ProviderGoalUpdate {
    pub fn payload(&self) -> Value {
        json!({ "goal": self.goal })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GoalCommand {
    Show,
    Clear,
    Pause,
    Resume,
    Set(String),
}

impl GoalCommand {
    /// T3 Code's `goalCommandStopsActiveRun`: setting or resuming starts goal
    /// work, and clearing or pausing ends it only while it is active.
    pub fn stops_active_turn(&self, status: Option<ProviderGoalStatus>) -> bool {
        match self {
            Self::Set(_) | Self::Resume => true,
            Self::Clear | Self::Pause => status == Some(ProviderGoalStatus::Active),
            Self::Show => false,
        }
    }
}

/// T3 Code's `parseGoalCommand`. A message with attachments is a prompt.
pub fn parse_goal_command(text: &str, has_attachments: bool) -> Option<GoalCommand> {
    if has_attachments {
        return None;
    }
    let rest = text.trim().strip_prefix("/goal")?;
    if !rest.is_empty() && !rest.starts_with(char::is_whitespace) {
        return None;
    }
    let argument = rest.trim();
    Some(match argument.to_lowercase().as_str() {
        "" | "edit" => GoalCommand::Show,
        "clear" => GoalCommand::Clear,
        "pause" => GoalCommand::Pause,
        "resume" => GoalCommand::Resume,
        _ => GoalCommand::Set(argument.to_owned()),
    })
}

impl ProviderEvent {
    /// The native turn a goal continues into, on the `turn.completed` of the
    /// turn before it. The host carries the run on into that turn instead of
    /// going idle between them.
    pub fn goal_continuation_turn(&self) -> Option<&str> {
        self.payload
            .get("goalContinuation")
            .and_then(|continuation| continuation.get("nextTurnId"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_like_t3_code() {
        assert_eq!(parse_goal_command("/goal", false), Some(GoalCommand::Show));
        assert_eq!(
            parse_goal_command("  /goal edit ", false),
            Some(GoalCommand::Show)
        );
        assert_eq!(
            parse_goal_command("/goal CLEAR", false),
            Some(GoalCommand::Clear)
        );
        assert_eq!(
            parse_goal_command("/goal pause", false),
            Some(GoalCommand::Pause)
        );
        assert_eq!(
            parse_goal_command("/goal\nresume", false),
            Some(GoalCommand::Resume)
        );
        assert_eq!(
            parse_goal_command("/goal  Ship the parser\nwith tests ", false),
            Some(GoalCommand::Set("Ship the parser\nwith tests".into()))
        );
        assert_eq!(parse_goal_command("/goals", false), None);
        assert_eq!(parse_goal_command("please /goal x", false), None);
        assert_eq!(parse_goal_command("/goal x", true), None);
    }

    #[test]
    fn only_goal_work_changes_stop_a_running_turn() {
        let active = Some(ProviderGoalStatus::Active);
        let paused = Some(ProviderGoalStatus::Paused);
        assert!(GoalCommand::Set("x".into()).stops_active_turn(None));
        assert!(GoalCommand::Resume.stops_active_turn(paused));
        assert!(GoalCommand::Pause.stops_active_turn(active));
        assert!(!GoalCommand::Pause.stops_active_turn(paused));
        assert!(GoalCommand::Clear.stops_active_turn(active));
        assert!(!GoalCommand::Clear.stops_active_turn(None));
        assert!(!GoalCommand::Show.stops_active_turn(active));
    }

    #[test]
    fn describes_with_spaced_status() {
        let goal = ProviderGoal {
            objective: "Ship".into(),
            status: ProviderGoalStatus::BudgetLimited,
            tokens_used: None,
            token_budget: None,
            time_used_seconds: None,
        };
        assert_eq!(goal.describe(), "Goal budget limited: Ship");
        assert_eq!(
            serde_json::to_value(&goal).unwrap(),
            json!({"objective": "Ship", "status": "budget_limited"})
        );
    }
}
