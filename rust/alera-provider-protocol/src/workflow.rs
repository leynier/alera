//! A provider-native workflow: a script that runs several sub-agents in
//! phases (Claude Code's `local_workflow` task), in the shape of T3 Code's
//! `OrchestrationV2SubagentWorkflow`. A provider attaches what one frame
//! reported as `workflow` on a task event; the host folds frames into the
//! coordinator sub-agent with [`SubagentWorkflow::merge`].

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::ProviderEvent;

/// The most members and phases a workflow keeps, and the longest text it
/// keeps for a label, a prompt or a result. The provider already caps its
/// excerpts at a few hundred characters; these only bound a runaway frame.
pub const WORKFLOW_MAX_AGENTS: usize = 256;
pub const WORKFLOW_MAX_PHASES: usize = 64;
pub const WORKFLOW_MAX_LABEL_CHARS: usize = 200;
pub const WORKFLOW_MAX_TEXT_CHARS: usize = 2_000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkflowPhase {
    pub index: u64,
    pub title: String,
}

/// Where a member is. A state the provider names that Alera does not know
/// is read as running: guessing settled would freeze a live row, while
/// running corrects itself on the next frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WorkflowAgentState {
    Queued,
    Running,
    Completed,
    Failed,
}

impl WorkflowAgentState {
    fn settled(self) -> bool {
        matches!(self, Self::Completed | Self::Failed)
    }
}

/// One member of the run, identified by its spawn ordinal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowAgent {
    pub index: u64,
    pub label: String,
    pub state: WorkflowAgentState,
    /// Provider-assigned, once the member starts; names its transcript.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phase_index: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phase_title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// Retry counter; above 1 the member restarted after an error.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attempt: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
    /// Epoch milliseconds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub queued_at: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub started_at: Option<u64>,
    /// Excerpts of what the member was asked and answered.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
}

macro_rules! overlay_fields {
    ($top:expr, $base:expr, $($field:ident),+) => {
        WorkflowAgent {
            index: $top.index,
            label: $top.label.clone(),
            state: $top.state,
            $($field: $top.$field.clone().or_else(|| $base.$field.clone()),)+
        }
    };
}

impl WorkflowAgent {
    /// `top`'s fields, with `base` filling the ones it lacks.
    fn overlay(top: &Self, base: &Self) -> Self {
        overlay_fields!(
            top,
            base,
            agent_id,
            phase_index,
            phase_title,
            model,
            attempt,
            total_tokens,
            tool_calls,
            duration_ms,
            queued_at,
            started_at,
            prompt,
            result
        )
    }

    /// Only the phase a restarted member keeps from its earlier attempt.
    fn phase_only(&self) -> Self {
        Self {
            index: self.index,
            label: self.label.clone(),
            state: self.state,
            agent_id: None,
            phase_index: self.phase_index,
            phase_title: self.phase_title.clone(),
            model: None,
            attempt: None,
            total_tokens: None,
            tool_calls: None,
            duration_ms: None,
            queued_at: None,
            started_at: None,
            prompt: None,
            result: None,
        }
    }
}

/// Filesystem handles the provider reports when a run launches: the script
/// it runs and where its members' transcripts go.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRunHandles {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transcript_dir: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub script_path: Option<String>,
}

impl WorkflowRunHandles {
    pub fn is_empty(&self) -> bool {
        self.run_id.is_none() && self.transcript_dir.is_none() && self.script_path.is_none()
    }
}

/// A workflow run as its coordinator sub-agent carries it. As a task event's
/// `workflow`, it is what that one frame reported.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubagentWorkflow {
    /// `meta.name` from the workflow script.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_handles: Option<WorkflowRunHandles>,
    /// The directory the provider keeps run files under. Files are only read
    /// from inside it; the provider names it, never a client.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub files_root: Option<String>,
    #[serde(default)]
    pub phases: Vec<WorkflowPhase>,
    #[serde(default)]
    pub agents: Vec<WorkflowAgent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
}

impl SubagentWorkflow {
    /// Folds one frame into what the coordinator already shows. Usage keeps
    /// climbing between snapshots. A phase only ever joins the plan: a late
    /// frame that omits one must not shorten the arc on screen. A member's
    /// older attempt is ignored, a newer one restarts it keeping only its
    /// phase, and within an attempt a settled member never goes back to
    /// running nor a running one to queued.
    pub fn merge(previous: Option<&Self>, frame: &Self) -> Self {
        let mut phases: BTreeMap<u64, WorkflowPhase> = previous
            .map(|previous| previous.phases.clone())
            .unwrap_or_default()
            .into_iter()
            .map(|phase| (phase.index, phase))
            .collect();
        for phase in &frame.phases {
            phases.insert(phase.index, phase.clone());
        }
        let mut agents: BTreeMap<u64, WorkflowAgent> = previous
            .map(|previous| previous.agents.clone())
            .unwrap_or_default()
            .into_iter()
            .map(|agent| (agent.index, agent))
            .collect();
        for agent in &frame.agents {
            let prior = agents.get(&agent.index);
            let prior_attempt = prior.map(|prior| prior.attempt.unwrap_or(1));
            let attempt = agent
                .attempt
                .or_else(|| prior.and_then(|prior| prior.attempt))
                .unwrap_or(1);
            if prior_attempt.is_some_and(|prior| attempt < prior) {
                continue;
            }
            let restarted = prior_attempt.is_some_and(|prior| attempt > prior);
            let merged = match prior {
                None => agent.clone(),
                Some(prior) if restarted => WorkflowAgent::overlay(agent, &prior.phase_only()),
                Some(prior)
                    if (prior.state.settled() && agent.state != prior.state)
                        || (prior.state == WorkflowAgentState::Running
                            && agent.state == WorkflowAgentState::Queued) =>
                {
                    WorkflowAgent::overlay(prior, agent)
                }
                Some(prior) => WorkflowAgent::overlay(agent, prior),
            };
            agents.insert(agent.index, merged);
        }
        let run_handles = match (
            previous.and_then(|previous| previous.run_handles.as_ref()),
            frame.run_handles.as_ref(),
        ) {
            (previous, None) => previous.cloned(),
            (None, Some(frame)) => Some(frame.clone()),
            (Some(previous), Some(frame)) => Some(WorkflowRunHandles {
                run_id: frame.run_id.clone().or_else(|| previous.run_id.clone()),
                transcript_dir: frame
                    .transcript_dir
                    .clone()
                    .or_else(|| previous.transcript_dir.clone()),
                script_path: frame
                    .script_path
                    .clone()
                    .or_else(|| previous.script_path.clone()),
            }),
        };
        let kept = |pick: fn(&Self) -> Option<u64>| pick(frame).or_else(|| previous.and_then(pick));
        Self {
            name: frame
                .name
                .clone()
                .or_else(|| previous.and_then(|previous| previous.name.clone())),
            run_handles,
            files_root: frame
                .files_root
                .clone()
                .or_else(|| previous.and_then(|previous| previous.files_root.clone())),
            phases: phases.into_values().collect(),
            agents: agents.into_values().collect(),
            total_tokens: kept(|workflow| workflow.total_tokens),
            tool_calls: kept(|workflow| workflow.tool_calls),
            duration_ms: kept(|workflow| workflow.duration_ms),
        }
        .bounded()
    }

    /// Caps the roster and every text at the `WORKFLOW_MAX_*` limits.
    pub fn bounded(mut self) -> Self {
        self.phases.truncate(WORKFLOW_MAX_PHASES);
        self.agents.truncate(WORKFLOW_MAX_AGENTS);
        for phase in &mut self.phases {
            clip(&mut phase.title, WORKFLOW_MAX_LABEL_CHARS);
        }
        for agent in &mut self.agents {
            clip(&mut agent.label, WORKFLOW_MAX_LABEL_CHARS);
            for text in [&mut agent.phase_title, &mut agent.model]
                .into_iter()
                .flatten()
            {
                clip(text, WORKFLOW_MAX_LABEL_CHARS);
            }
            for text in [&mut agent.prompt, &mut agent.result].into_iter().flatten() {
                clip(text, WORKFLOW_MAX_TEXT_CHARS);
            }
        }
        if let Some(name) = &mut self.name {
            clip(name, WORKFLOW_MAX_LABEL_CHARS);
        }
        self
    }
}

fn clip(text: &mut String, max_chars: usize) {
    if let Some((cut, _)) = text.char_indices().nth(max_chars) {
        text.truncate(cut);
    }
}

impl ProviderEvent {
    /// The workflow frame a task event carries. A malformed one is ignored
    /// rather than failing the event.
    pub fn workflow(&self) -> Option<SubagentWorkflow> {
        self.payload
            .get("workflow")
            .and_then(|value| serde_json::from_value(value.clone()).ok())
    }
}

#[cfg(test)]
#[path = "workflow_tests.rs"]
mod tests;
