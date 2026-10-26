//! Claude Code workflows: a `local_workflow` task runs a script that starts
//! sub-agents in phases. Its progress arrives on the task's own frames in
//! fields the SDK does not declare (`workflow_name`, `workflow_progress`,
//! `usage`), and the Workflow tool's result names the run's files. All of
//! it is read defensively, as T3 Code's `claudeWorkflowProgress` reads it: an
//! unknown or malformed field is dropped, never fails the frame.

use super::canonical_payload::text_field;
use super::*;
use crate::skills::SkillEnvironment;
use alera_provider_protocol::{
    NativeTask, SubagentWorkflow, WorkflowAgent, WorkflowAgentState, WorkflowPhase,
    WorkflowRunHandles,
};
use claude_agent_sdk::UserMessage;
use std::collections::HashSet;

pub(super) const WORKFLOW_TASK_TYPE: &str = "local_workflow";
const MAX_SAFE_INTEGER: u64 = 9_007_199_254_740_991;
/// The latest instant a JavaScript `Date` holds, in epoch milliseconds.
const MAX_TIMESTAMP_MS: u64 = 8_640_000_000_000_000;

fn text(value: Option<&Value>) -> Option<String> {
    let trimmed = value?.as_str()?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

/// Prompt and result excerpts keep their whitespace.
fn preview(value: Option<&Value>) -> Option<String> {
    value?
        .as_str()
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

fn count(value: Option<&Value>) -> Option<u64> {
    let value = value?;
    value
        .as_u64()
        .or_else(|| {
            let float = value.as_f64()?;
            (float >= 0.0 && float.fract() == 0.0 && float <= MAX_SAFE_INTEGER as f64)
                .then_some(float as u64)
        })
        .filter(|count| *count <= MAX_SAFE_INTEGER)
}

fn timestamp(value: Option<&Value>) -> Option<u64> {
    count(value).filter(|millis| *millis <= MAX_TIMESTAMP_MS)
}

fn agent_state(reported: Option<String>) -> WorkflowAgentState {
    match reported.as_deref() {
        Some("queued") => WorkflowAgentState::Queued,
        Some("done") => WorkflowAgentState::Completed,
        Some("error") => WorkflowAgentState::Failed,
        _ => WorkflowAgentState::Running,
    }
}

fn parse_phase(entry: &Value) -> Option<WorkflowPhase> {
    Some(WorkflowPhase {
        index: count(entry.get("index"))?,
        title: text(entry.get("title"))?,
    })
}

fn parse_agent(entry: &Value) -> Option<WorkflowAgent> {
    Some(WorkflowAgent {
        index: count(entry.get("index"))?,
        label: text(entry.get("label"))?,
        state: agent_state(text(entry.get("state"))),
        agent_id: text(entry.get("agentId")),
        phase_index: count(entry.get("phaseIndex")),
        phase_title: text(entry.get("phaseTitle")),
        model: text(entry.get("model")),
        attempt: count(entry.get("attempt")),
        total_tokens: count(entry.get("tokens")),
        tool_calls: count(entry.get("toolCalls")),
        duration_ms: count(entry.get("durationMs")),
        queued_at: timestamp(entry.get("queuedAt")),
        started_at: timestamp(entry.get("startedAt")),
        prompt: preview(entry.get("promptPreview")),
        result: preview(entry.get("resultPreview")),
    })
}

/// The phases and members a frame's `workflow_progress` lists, or `None`
/// when it lists none that parse.
fn parse_snapshot(payload: &Value) -> Option<(Vec<WorkflowPhase>, Vec<WorkflowAgent>)> {
    let entries = payload.get("workflow_progress")?.as_array()?;
    let mut phases = Vec::new();
    let mut agents = Vec::new();
    for entry in entries {
        match text(entry.get("type")).as_deref() {
            Some("workflow_phase") => phases.extend(parse_phase(entry)),
            Some("workflow_agent") => agents.extend(parse_agent(entry)),
            _ => {}
        }
    }
    (!phases.is_empty() || !agents.is_empty()).then_some((phases, agents))
}

/// The run's files, from the Workflow tool's structured result. A background
/// launch answers with an acknowledgement, the only place they appear.
pub(super) fn run_handles(tool_use_result: &Value) -> Option<WorkflowRunHandles> {
    if text(tool_use_result.get("taskType")).as_deref() != Some(WORKFLOW_TASK_TYPE) {
        return None;
    }
    let handles = WorkflowRunHandles {
        run_id: text(tool_use_result.get("runId")),
        transcript_dir: text(tool_use_result.get("transcriptDir")),
        script_path: text(tool_use_result.get("scriptPath")),
    };
    (!handles.is_empty()).then_some(handles)
}

/// What one task frame reports about its workflow. `None` when nothing marks
/// the task as one: progress frames do not repeat `task_type`, so without
/// `known` every ordinary sub-agent's usage frame would read as a workflow.
pub(super) fn frame(payload: &Value, known: bool) -> Option<SubagentWorkflow> {
    let launched =
        text_field(payload, &["task_type", "taskType"]).as_deref() == Some(WORKFLOW_TASK_TYPE);
    let snapshot = parse_snapshot(payload);
    if !known && !launched && snapshot.is_none() {
        return None;
    }
    let (phases, agents) = snapshot.unwrap_or_default();
    let usage = payload.get("usage");
    let usage = |key: &str| count(usage.and_then(|usage| usage.get(key)));
    Some(
        SubagentWorkflow {
            // `meta.name` from the script; only workflow tasks carry it.
            name: launched
                .then(|| text(payload.get("workflow_name")))
                .flatten(),
            phases,
            agents,
            total_tokens: usage("total_tokens"),
            tool_calls: usage("tool_uses"),
            duration_ms: usage("duration_ms"),
            ..Default::default()
        }
        .bounded(),
    )
}

/// The session's workflow tasks, and run handles that arrived before the
/// task they belong to, by the Workflow call.
#[derive(Default)]
pub(super) struct WorkflowTasks {
    tasks: HashSet<String>,
    calls: HashMap<String, String>,
    early_handles: HashMap<String, WorkflowRunHandles>,
}

impl ClaudeProvider {
    /// The `workflow` a task event carries, remembering the task as one.
    pub(super) fn workflow_frame(&mut self, task_id: &str, payload: &Value) -> Option<Value> {
        let known = self.workflow_tasks.tasks.contains(task_id);
        let mut workflow = frame(payload, known)?;
        if !known {
            self.workflow_tasks.tasks.insert(task_id.to_owned());
        }
        if let Some(call) = text_field(payload, &["tool_use_id", "toolUseId"]) {
            if let Some(handles) = self.workflow_tasks.early_handles.remove(&call) {
                workflow.run_handles = Some(handles);
                workflow.files_root = self.workflow_files_root();
            }
            self.workflow_tasks.calls.insert(call, task_id.to_owned());
        }
        serde_json::to_value(workflow).ok()
    }

    /// Where Claude keeps run files: `<config dir>/projects`, the config dir
    /// resolved as the spawned CLI resolves it.
    fn workflow_files_root(&self) -> Option<String> {
        let cwd = self
            .session
            .as_ref()
            .and_then(|session| session.cwd.clone());
        let config = SkillEnvironment::new(&self.config.options, cwd.as_deref()).config_dir()?;
        Some(config.join("projects").to_string_lossy().into_owned())
    }

    /// A task update naming the run's files, when [message] is the Workflow
    /// tool's launch acknowledgement. It reports no status, so it never
    /// settles or revives the workflow. Handles that arrive before their task
    /// wait for its start.
    pub(super) fn workflow_handles_event(
        &mut self,
        message: &UserMessage,
    ) -> Option<ProviderEvent> {
        let result = message.tool_use_result.as_ref()?;
        let handles = run_handles(result)?;
        let call = message.content.as_array()?.iter().find_map(|block| {
            (text(block.get("type")).as_deref() == Some("tool_result"))
                .then(|| text(block.get("tool_use_id")))
                .flatten()
        })?;
        let Some(task_id) = self.workflow_tasks.calls.get(&call).cloned() else {
            self.workflow_tasks.early_handles.insert(call, handles);
            return None;
        };
        let workflow = SubagentWorkflow {
            run_handles: Some(handles),
            files_root: self.workflow_files_root(),
            ..Default::default()
        };
        Some(self.event(
            EventKind::TaskUpdated,
            json!({
                "taskId": task_id.clone(),
                "taskType": WORKFLOW_TASK_TYPE,
                "nativeTask": NativeTask {
                    native_task_id: Some(task_id),
                    native_tool_call_id: Some(call),
                    ..Default::default()
                },
                "workflow": workflow,
            }),
            self.raw("user", message.raw.clone()),
        ))
    }
}

#[cfg(test)]
#[path = "workflow_tests.rs"]
mod tests;
