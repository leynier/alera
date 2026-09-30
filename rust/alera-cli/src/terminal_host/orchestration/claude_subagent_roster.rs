//! Claude sub-agents that outlive the main agent's turn.
//!
//! A background sub-agent keeps working after the main turn fires `Stop`, and
//! the main agent often stops only to wait for it. The tab is not done until
//! those children are, and a child that asks a question needs attention even
//! when the main turn ended. Children are keyed by the `agent_id` Claude puts
//! on every hook fired inside a sub-agent.

use std::collections::{BTreeMap, VecDeque};

use serde_json::Value;

use super::agent_presence::AgentPresenceState;

/// Beyond this many children new ones are not tracked: a runaway fan-out must
/// not grow host memory, and the ones already tracked keep the tab working.
const MAX_ACTIVE_SUBAGENTS: usize = 32;

/// Claude never reuses a one-shot child's id, so a hook that lands after its
/// `SubagentStop` (hooks post concurrently) must not bring it back.
const MAX_FINISHED_SUBAGENTS: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubagentState {
    Working,
    Waiting,
}

/// What `observe` did with a child's hook.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Observed {
    Tracked,
    /// The child already stopped: its hook is late and changes nothing.
    Finished,
    /// The roster is full, so the child is alive but not tracked.
    Untracked,
}

#[derive(Debug, Clone)]
pub struct ClaudeSubagentRoster {
    active: BTreeMap<String, SubagentState>,
    finished: VecDeque<String>,
    /// State last reported by the main agent's own hooks, before children
    /// are taken into account.
    lead: AgentPresenceState,
    /// Carried from the main agent's `done` so the one emitted once the last
    /// child finishes still says how the turn ended.
    lead_interrupted: Option<bool>,
    lead_inferred_idle: bool,
    /// The main agent's `waiting`/`blocked` came from a notification or an
    /// untracked child rather than from its own tool hook, so a child's
    /// activity may answer it.
    lead_attention_answerable_by_child: bool,
}

impl Default for ClaudeSubagentRoster {
    fn default() -> Self {
        Self {
            active: BTreeMap::new(),
            finished: VecDeque::new(),
            lead: AgentPresenceState::Working,
            lead_interrupted: None,
            lead_inferred_idle: false,
            lead_attention_answerable_by_child: false,
        }
    }
}

impl ClaudeSubagentRoster {
    #[cfg(test)]
    pub fn lead(&self) -> AgentPresenceState {
        self.lead
    }

    pub fn lead_interrupted(&self) -> Option<bool> {
        self.lead_interrupted
    }

    pub fn lead_inferred_idle(&self) -> bool {
        self.lead_inferred_idle
    }

    pub fn set_lead(
        &mut self,
        state: AgentPresenceState,
        interrupted: Option<bool>,
        inferred_idle: bool,
    ) {
        self.lead = state;
        self.lead_interrupted = interrupted;
        self.lead_inferred_idle = inferred_idle;
        self.lead_attention_answerable_by_child = false;
    }

    /// Attention Claude announces without naming a child: a permission
    /// notification (which follows a child's prompt as well as the main
    /// agent's) or a question from a child the full roster could not track.
    /// A prompt the main agent's own tool hook already raised keeps its origin.
    pub fn raise_attention_a_child_may_answer(&mut self, state: AgentPresenceState) {
        let own_prompt = matches!(
            self.lead,
            AgentPresenceState::Waiting | AgentPresenceState::Blocked
        ) && !self.lead_attention_answerable_by_child;
        if own_prompt {
            return;
        }
        self.set_lead(state, None, false);
        self.lead_attention_answerable_by_child = true;
    }

    /// A child's own activity answers the prompt that stopped it. Only
    /// attention that may have been the child's is cleared: the main agent's
    /// own approval prompt stays up, and a finished main turn stays finished.
    pub fn child_resumed_lead(&mut self) {
        if self.lead_attention_answerable_by_child {
            self.set_lead(AgentPresenceState::Working, None, false);
        }
    }

    /// The silence sweep gave up on the children. A main turn that really
    /// ended keeps its confirmed `done`, so the next hook restores injection;
    /// one that never reported an end is concluded idle.
    pub fn settle_after_silence(&mut self) {
        if self.lead != AgentPresenceState::Done {
            self.set_lead(AgentPresenceState::Done, None, true);
        }
        self.clear_active();
    }

    /// `SubagentStart`. Teammates reuse their id for every turn, so an
    /// explicit start revives a finished id.
    pub fn start(&mut self, id: &str) {
        self.finished.retain(|finished| finished != id);
        self.insert(id, SubagentState::Working);
    }

    /// Activity from inside a child.
    pub fn observe(&mut self, id: &str, state: SubagentState) -> Observed {
        if self.finished.iter().any(|finished| finished == id) {
            return Observed::Finished;
        }
        if self.insert(id, state) {
            Observed::Tracked
        } else {
            Observed::Untracked
        }
    }

    /// `SubagentStop`, or a child's interrupted tool call.
    pub fn finish(&mut self, id: &str) {
        self.active.remove(id);
        if !self.finished.iter().any(|finished| finished == id) {
            if self.finished.len() >= MAX_FINISHED_SUBAGENTS {
                self.finished.pop_front();
            }
            self.finished.push_back(id.to_string());
        }
    }

    /// Foreground children die with an interrupted turn and a new
    /// conversation. A background child that survived reports again on its
    /// next hook.
    pub fn clear_active(&mut self) {
        self.active.clear();
    }

    pub fn has_working(&self) -> bool {
        self.active
            .values()
            .any(|state| *state == SubagentState::Working)
    }

    pub fn has_waiting(&self) -> bool {
        self.active
            .values()
            .any(|state| *state == SubagentState::Waiting)
    }

    #[cfg(test)]
    pub fn active_count(&self) -> usize {
        self.active.len()
    }

    /// The main turn ended but a child is still working, so the tab reports
    /// `working` on the children's behalf.
    pub fn holds_finished_turn_open(&self) -> bool {
        self.lead == AgentPresenceState::Done && self.has_working()
    }

    /// What the tab shows: attention from the main agent first, then a child
    /// waiting for an answer, then any work left, main or child.
    pub fn effective_state(&self) -> AgentPresenceState {
        match self.lead {
            AgentPresenceState::Waiting | AgentPresenceState::Blocked => self.lead,
            _ if self.has_waiting() => AgentPresenceState::Waiting,
            AgentPresenceState::Done if !self.has_working() => AgentPresenceState::Done,
            _ => AgentPresenceState::Working,
        }
    }

    /// Reconciles against the `background_tasks` inventory newer Claude
    /// releases attach to `Stop` and `SubagentStop`, which recovers a `SubagentStop` that never
    /// arrived and a child that started before this host saw it. Only
    /// `subagent` entries name lifecycle ids. `teammate` entries never do and
    /// read as running forever, so while any is listed a teammate-shaped id
    /// (`a<name>-<hex>`) that is not listed may still be alive. An absent field
    /// (older releases) leaves the roster to the lifecycle hooks.
    pub fn reconcile_background_tasks(&mut self, payload: &Value) {
        let Some(tasks) = payload.get("background_tasks").and_then(Value::as_array) else {
            return;
        };
        let mut listed = Vec::new();
        let mut has_teammates = false;
        for task in tasks {
            let kind = task.get("type").and_then(Value::as_str);
            if kind == Some("teammate") {
                has_teammates = true;
                continue;
            }
            if kind != Some("subagent") {
                continue;
            }
            let Some(id) = task
                .get("id")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|id| !id.is_empty())
            else {
                continue;
            };
            listed.push(id.to_string());
            if task.get("status").and_then(Value::as_str) == Some("running") {
                if !self.active.contains_key(id) {
                    self.observe(id, SubagentState::Working);
                }
            } else {
                self.finish(id);
            }
        }
        let unlisted = self
            .active
            .keys()
            .filter(|id| !listed.contains(id))
            .filter(|id| !(has_teammates && is_teammate_lifecycle_id(id)))
            .cloned()
            .collect::<Vec<_>>();
        for id in unlisted {
            self.finish(&id);
        }
    }

    fn insert(&mut self, id: &str, state: SubagentState) -> bool {
        if id.is_empty() {
            return false;
        }
        if !self.active.contains_key(id) && self.active.len() >= MAX_ACTIVE_SUBAGENTS {
            return false;
        }
        self.active.insert(id.to_string(), state);
        true
    }
}

/// Named agents and teammates get `a<name>-<hex>`, one-shot children a
/// hyphen-free `a<hex>`.
fn is_teammate_lifecycle_id(id: &str) -> bool {
    id.rsplit_once('-').is_some_and(|(name, suffix)| {
        name.len() > 1
            && name.starts_with('a')
            && !suffix.is_empty()
            && suffix.chars().all(|c| c.is_ascii_hexdigit())
    })
}

#[cfg(test)]
#[path = "claude_subagent_roster_tests.rs"]
mod tests;
