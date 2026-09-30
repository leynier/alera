//! Hook-independent correction of agent presence.
//!
//! Hooks only report what an agent chooses to announce. An interrupted turn,
//! an API error, a crash or a `Ctrl+C` exit can leave a tab `working` for as
//! long as the PTY lives. The sweep checks what the host can observe itself.

use std::time::Duration;

use chrono::{DateTime, Utc};
use serde_json::json;
use tokio::task::JoinHandle;

use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};
use crate::terminal_host::session::{process_alive, process_group_alive};

use super::{ServerActor, ServerCommand};

const SWEEP_INTERVAL: Duration = Duration::from_secs(5);

/// Every supported agent TUI redraws a spinner or an elapsed-time counter
/// several times a second while a turn runs, tool calls included. A minute of
/// silence is a turn that ended without telling anyone. It matches Claude's
/// own `idle_prompt` delay.
pub(super) const WORKING_SILENCE_THRESHOLD: Duration = Duration::from_secs(60);

/// A Claude sub-agent can outlive the main turn while the main agent sits
/// idle at its prompt, where nothing redraws. Its own hooks fire around every
/// tool call and Claude caps a single Bash call at ten minutes, so this much
/// silence means its `SubagentStop` was lost.
pub(super) const SUBAGENT_SILENCE_THRESHOLD: Duration = Duration::from_secs(15 * 60);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PresenceVerdict {
    Keep,
    AgentExited,
    SilentlyIdle,
}

pub(super) fn spawn(inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>) -> JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(SWEEP_INTERVAL).await;
            if inbox.send(ServerCommand::AgentPresenceSweepTick).is_err() {
                break;
            }
        }
    })
}

/// `group_alive` is `None` when the agent's process group is unknown.
pub(super) fn presence_verdict(
    presence: &AgentPresence,
    group_alive: Option<bool>,
    output_idle: Duration,
    now: DateTime<Utc>,
) -> PresenceVerdict {
    if group_alive == Some(false) {
        return PresenceVerdict::AgentExited;
    }
    let reported_for = now
        .signed_duration_since(presence.updated_at)
        .to_std()
        .unwrap_or_default();
    let threshold = if presence.claude_subagents.holds_finished_turn_open() {
        SUBAGENT_SILENCE_THRESHOLD
    } else {
        WORKING_SILENCE_THRESHOLD
    };
    if presence.state == AgentPresenceState::Working
        && !presence.inferred_idle
        && output_idle >= threshold
        && reported_for >= threshold
    {
        return PresenceVerdict::SilentlyIdle;
    }
    PresenceVerdict::Keep
}

impl ServerActor {
    pub(super) async fn reconcile_agent_presence(&mut self) {
        let now = Utc::now();
        let mut exited = Vec::new();
        let mut idle = Vec::new();
        for (handle, presence) in self.agent_presence.iter() {
            // Relayed presence belongs to the host that owns the process.
            if !presence.local_hook || self.voice.home_session_id.as_deref() == Some(handle) {
                continue;
            }
            let Some(session) = self
                .sessions
                .get(handle)
                .filter(|session| session.running())
            else {
                continue;
            };
            // The process group is the Unix signal; where there is none
            // (Windows), the pid an agent reports stands in for it.
            let group_alive = presence
                .process_group
                .map(|group| {
                    session.agent_process_group() == Some(group) || process_group_alive(group)
                })
                .or_else(|| presence.agent_pid.map(process_alive));
            match presence_verdict(presence, group_alive, session.output_idle_for(), now) {
                PresenceVerdict::Keep => {}
                PresenceVerdict::AgentExited => exited.push(handle.clone()),
                PresenceVerdict::SilentlyIdle => idle.push(handle.clone()),
            }
        }
        if !exited.is_empty() {
            let entries = exited
                .iter()
                .map(|handle| json!({ "terminalSessionId": handle, "removed": true }))
                .collect::<Vec<_>>();
            let _ = self
                .orchestration_agent_status(&json!({ "entries": entries }))
                .await;
        }
        if idle.is_empty() {
            return;
        }
        for handle in &idle {
            if let Some(presence) = self.agent_presence.get_mut(handle) {
                presence.state = AgentPresenceState::Done;
                presence.state_started_at = now;
                presence.updated_at = now;
                presence.inferred_idle = true;
                presence.claude_subagents.clear_active();
                presence
                    .claude_subagents
                    .set_lead(AgentPresenceState::Done, None, true);
            }
        }
        self.broadcast_agent_presence_changed();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn presence(state: AgentPresenceState, reported_ago: Duration) -> AgentPresence {
        let updated_at = Utc::now() - chrono::Duration::from_std(reported_ago).unwrap();
        AgentPresence {
            agent_type: "claude".into(),
            state,
            state_started_at: updated_at,
            updated_at,
            prompt: String::new(),
            tool_name: None,
            tool_input: None,
            last_assistant_message: None,
            interrupted: None,
            native_session_id: None,
            process_group: Some(42),
            agent_pid: None,
            turn_id: None,
            local_hook: true,
            inferred_idle: false,
            claude_subagents: Default::default(),
        }
    }

    const LONG: Duration = Duration::from_secs(120);
    const SHORT: Duration = Duration::from_secs(5);

    #[test]
    fn a_dead_agent_group_removes_presence_in_any_state() {
        for state in [
            AgentPresenceState::Working,
            AgentPresenceState::Waiting,
            AgentPresenceState::Done,
        ] {
            assert_eq!(
                presence_verdict(&presence(state, SHORT), Some(false), SHORT, Utc::now()),
                PresenceVerdict::AgentExited
            );
        }
    }

    #[test]
    fn a_silent_working_agent_is_idle_only_after_both_output_and_hooks_stop() {
        let working = presence(AgentPresenceState::Working, LONG);
        assert_eq!(
            presence_verdict(&working, Some(true), LONG, Utc::now()),
            PresenceVerdict::SilentlyIdle
        );
        assert_eq!(
            presence_verdict(&working, None, LONG, Utc::now()),
            PresenceVerdict::SilentlyIdle
        );
        assert_eq!(
            presence_verdict(&working, Some(true), SHORT, Utc::now()),
            PresenceVerdict::Keep
        );
        let recent_hook = presence(AgentPresenceState::Working, SHORT);
        assert_eq!(
            presence_verdict(&recent_hook, Some(true), LONG, Utc::now()),
            PresenceVerdict::Keep
        );
    }

    #[test]
    fn a_turn_held_open_by_a_sub_agent_waits_longer_before_reading_as_idle() {
        let mut working = presence(AgentPresenceState::Working, LONG);
        working
            .claude_subagents
            .set_lead(AgentPresenceState::Done, None, false);
        working.claude_subagents.start("a1");
        assert_eq!(
            presence_verdict(&working, Some(true), LONG, Utc::now()),
            PresenceVerdict::Keep
        );
        let silent = SUBAGENT_SILENCE_THRESHOLD + SHORT;
        let mut lost = presence(AgentPresenceState::Working, silent);
        lost.claude_subagents = working.claude_subagents.clone();
        assert_eq!(
            presence_verdict(&lost, Some(true), silent, Utc::now()),
            PresenceVerdict::SilentlyIdle
        );
    }

    #[test]
    fn waiting_and_already_inferred_presence_is_left_alone() {
        let waiting = presence(AgentPresenceState::Waiting, LONG);
        assert_eq!(
            presence_verdict(&waiting, Some(true), LONG, Utc::now()),
            PresenceVerdict::Keep
        );
        let mut inferred = presence(AgentPresenceState::Working, LONG);
        inferred.inferred_idle = true;
        assert_eq!(
            presence_verdict(&inferred, Some(true), LONG, Utc::now()),
            PresenceVerdict::Keep
        );
    }
}
