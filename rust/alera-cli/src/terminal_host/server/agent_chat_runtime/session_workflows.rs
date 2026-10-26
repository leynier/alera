//! Provider-native workflows (Claude Code's `local_workflow`): a sub-agent
//! that runs a script starting other sub-agents in phases. The call that
//! launched it keeps the run in `normalized.subagent.workflow`, folded from
//! each task event's frame; its script and each member's answers are read
//! on request (`agentChatWorkflowsV1`). A workflow stops with the turn that
//! started it unless the provider says children continue, and never
//! outlives the provider process that ran it.

use std::path::Path;
use std::time::Duration;

use alera_provider_protocol::{EventKind, ProviderEvent, SubagentWorkflow};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::conflict;
use super::ids::{native_key, now};
use super::session::ChatSession;
use super::workflow_files::{
    read_agent_answers, read_contained, WorkflowFileError, SCRIPT_BYTE_CAP,
};

/// Bounds the best-effort stop of a workflow its turn no longer follows.
const STOP_TIMEOUT: Duration = Duration::from_secs(5);

/// Folds the event's workflow frame into the sub-agent record.
pub(super) fn fold_workflow(subagent: &mut Value, event: &ProviderEvent) {
    let Some(frame) = event.workflow() else {
        return;
    };
    let previous: Option<SubagentWorkflow> = subagent
        .get("workflow")
        .and_then(|value| serde_json::from_value(value.clone()).ok());
    let merged = SubagentWorkflow::merge(previous.as_ref(), &frame);
    if let Ok(value) = serde_json::to_value(merged) {
        subagent["workflow"] = value;
    }
}

/// The status a task event leaves a sub-agent in. A workflow frame that
/// reports no status of its own (the launch acknowledgement, a late progress
/// frame) never revives a settled workflow.
pub(super) fn workflow_status<'a>(
    event: &ProviderEvent,
    reported: &'a str,
    previous: Option<&'a str>,
) -> &'a str {
    let silent = event.payload.get("workflow").is_some()
        && matches!(event.kind, EventKind::TaskProgress | EventKind::TaskUpdated)
        && event.payload.get("status").is_none();
    match previous {
        Some(previous) if silent && previous != "running" => previous,
        _ => reported,
    }
}

fn file_error(error: WorkflowFileError) -> HostError {
    conflict(error.code(), error.message())
}

fn not_a_workflow() -> HostError {
    conflict("notWorkflow", "The item did not start a workflow.")
}

impl ChatSession {
    /// The workflow the call `item_id` started, as the chat stores it.
    async fn stored_workflow(&mut self, item_id: &str) -> HostResult<SubagentWorkflow> {
        self.load_item(item_id).await;
        let workflow = match self.items.get(item_id) {
            Some(call) => call.normalized.get("subagent").cloned(),
            None => self
                .deps
                .store
                .agent_chat_item(&self.header.chat_id, item_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| conflict("itemNotFound", "The item no longer exists."))?
                .pointer("/normalized/subagent")
                .cloned(),
        }
        .and_then(|subagent| subagent.get("workflow").cloned())
        .ok_or_else(not_a_workflow)?;
        serde_json::from_value(workflow).map_err(|_| not_a_workflow())
    }

    /// `agentChat.workflowScript`: the script the workflow runs, capped at
    /// 256 KiB, read only from inside the provider's run files.
    pub(super) async fn workflow_script(&mut self, item_id: &str) -> HostResult<Value> {
        let workflow = self.stored_workflow(item_id).await?;
        let (Some(root), Some(script)) = (
            workflow.files_root,
            workflow.run_handles.and_then(|handles| handles.script_path),
        ) else {
            return Err(conflict(
                "workflowScriptUnavailable",
                "The workflow has not named its script.",
            ));
        };
        let file = tokio::task::spawn_blocking(move || {
            read_contained(Path::new(&root), &script, "js", SCRIPT_BYTE_CAP, false)
        })
        .await
        .map_err(|_| HostError::state("The workflow script could not be read."))?
        .map_err(|error| match error {
            WorkflowFileError::InvalidPath | WorkflowFileError::WrongExtension => {
                conflict("notJs", "Workflow scripts must be absolute .js paths.")
            }
            other => file_error(other),
        })?;
        Ok(json!({
            "itemId": item_id,
            "scriptPath": file.path.to_string_lossy(),
            "contents": file.contents,
            "truncated": file.truncated,
        }))
    }

    /// `agentChat.workflowAgent`: what one member answered, from the
    /// transcript the provider wrote for it. A member is not a provider task
    /// and streams nothing, so the progress snapshot only has an excerpt.
    pub(super) async fn workflow_agent(
        &mut self,
        item_id: &str,
        agent_index: u64,
    ) -> HostResult<Value> {
        let workflow = self.stored_workflow(item_id).await?;
        let member = workflow
            .agents
            .iter()
            .find(|agent| agent.index == agent_index)
            .ok_or_else(|| conflict("workflowAgentNotFound", "The workflow has no such agent."))?;
        let (Some(root), Some(dir), Some(agent_id)) = (
            workflow.files_root.clone(),
            workflow
                .run_handles
                .as_ref()
                .and_then(|handles| handles.transcript_dir.clone()),
            member.agent_id.clone(),
        ) else {
            return Err(conflict(
                "workflowTranscriptUnavailable",
                "The workflow has not named this agent's transcript.",
            ));
        };
        let answers = tokio::task::spawn_blocking(move || {
            read_agent_answers(Path::new(&root), &dir, &agent_id)
        })
        .await
        .map_err(|_| HostError::state("The agent's transcript could not be read."))?
        .map_err(file_error)?;
        Ok(json!({"itemId": item_id, "agentIndex": agent_index, "answers": answers}))
    }

    /// Settles the running workflows among `task_ids` as `status`, first
    /// asking the provider to stop each when `stop` holds.
    async fn settle_workflows(&mut self, task_ids: Vec<String>, status: &str, stop: bool) {
        for task_id in task_ids {
            let key = native_key(
                &self.epoch_kind("subagentTask"),
                &Value::String(task_id.clone()),
            );
            let Some(call_id) = self.native_ids.get(&key).cloned() else {
                continue;
            };
            self.load_item(&call_id).await;
            let running = self
                .items
                .get(&call_id)
                .and_then(|call| call.normalized.get("subagent"))
                .is_some_and(|subagent| {
                    subagent.get("workflow").is_some()
                        && subagent.get("status").and_then(Value::as_str) == Some("running")
                });
            if !running {
                continue;
            }
            if let Some(provider) = self.provider.as_mut().filter(|_| stop) {
                // Best effort: an unanswered stop must not hold the turn's end.
                let _ = tokio::time::timeout(STOP_TIMEOUT, provider.stop_subagent(&task_id)).await;
            }
            let Some(call) = self.items.get_mut(&call_id) else {
                continue;
            };
            if let Some(subagent) = call.normalized.get_mut("subagent") {
                subagent["status"] = json!(status);
                subagent["completedAt"] = json!(now());
            }
            call.updated_at = now();
            self.pending.item(&call_id);
        }
    }

    /// A failed or stopped turn takes the workflows it started down with it,
    /// unless the provider says its children continue: nothing would follow
    /// them otherwise.
    pub(super) async fn end_workflows_of(
        &mut self,
        turn_id: &str,
        status: &str,
        child_turns_continue: bool,
    ) {
        if status == "completed" || child_turns_continue {
            return;
        }
        let task_ids: Vec<String> = self
            .awaited_tasks
            .iter()
            .filter(|(_, task)| task.started_in.as_deref() == Some(turn_id))
            .map(|(task_id, _)| task_id.clone())
            .collect();
        let settled = if status == "failed" {
            "failed"
        } else {
            "stopped"
        };
        self.settle_workflows(task_ids, settled, true).await;
    }

    /// A workflow can outlive its turn but not the provider process: when
    /// the process ends, every workflow still running ends with it.
    pub(super) async fn end_workflows_of_process(&mut self, status: &str) {
        let task_ids: Vec<String> = self.awaited_tasks.keys().cloned().collect();
        self.settle_workflows(task_ids, status, false).await;
    }
}

#[cfg(test)]
#[path = "session_workflows_unit_tests.rs"]
mod tests;
