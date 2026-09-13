//! Pull request title and description for a paired phone. The context, prompt
//! and parsing mirror the desktop generator (`ai_assist_service.dart`,
//! `ai_assist_prompt.dart`), so both surfaces describe the same range the
//! same way.

use alera_core::runtime::{RuntimeAiAssistSettings, RuntimeStore, LOCAL_HOST_ID};
use alera_core::source_control::{self, GitChangeStatus, GitRangeContext};
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_commit_message::{
    clean_generated_text, limit_prompt_section, truncate_diff_for_prompt,
};
use super::ai_assist_requests::{active_generations, plan_command, run_command};
use super::host_service_requests::required_non_blank;
use super::mobile_source_control_snapshot::git_host_error;
use super::mobile_workspace_file_requests::spawn_blocking_workspace;
use super::{ServerActor, ServerCommand};

const OPERATION: &str = "pullRequestDetails";
const COMMITS_BUDGET: usize = 8000;
const FILES_BUDGET: usize = 6000;
const INSTRUCTIONS_BUDGET: usize = 4000;
const MAX_TITLE_CHARS: usize = 72;

pub(super) struct PullRequestDetails {
    pub(super) title: String,
    pub(super) body: Option<String>,
}

impl ServerActor {
    pub(super) fn start_ai_assist_pull_request_details(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let workspace_id = required_non_blank(payload, "workspaceId")?;
        let base_branch = required_non_blank(payload, "baseBranch")?;
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let (cancel_tx, cancel_rx) = oneshot::channel();
        let mut active = active_generations()
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))?;
        if active.contains_key(&operation_id) {
            return Err(HostError::state(
                "AI Assist is already running for this operation.",
            ));
        }
        active.insert(operation_id.clone(), cancel_tx);
        drop(active);
        tokio::spawn(async move {
            let result =
                generate_pull_request_details(&store, &workspace_id, &base_branch, cancel_rx)
                    .await
                    .map(|(details, agent_label)| {
                        json!({
                            "title": details.title,
                            "body": details.body,
                            "agentLabel": agent_label,
                        })
                    });
            if let Ok(mut active) = active_generations().lock() {
                active.remove(&operation_id);
            }
            let _ = inbox.send(ServerCommand::AiAssistFinished {
                client_id,
                request_id,
                result,
            });
        });
        Ok(())
    }
}

/// Generates the details for the range between `base_branch` and HEAD, and
/// the label of the agent that wrote them.
pub(super) async fn generate_pull_request_details(
    store: &RuntimeStore,
    workspace_id: &str,
    base_branch: &str,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<(PullRequestDetails, String)> {
    let workspace = store
        .find_workspace(workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "Pull request details can only be generated for workspaces on this runtime.",
        ));
    }
    let settings = store
        .effective_ai_assist_settings()
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    if !settings.enabled {
        return Err(HostError::state("AI Assist is disabled."));
    }
    let base = base_branch.trim().to_string();
    if base.is_empty() {
        return Err(HostError::state(
            "Select a base branch before generating pull request details.",
        ));
    }
    let root = workspace.path.clone();
    let range_base = base.clone();
    let range = spawn_blocking_workspace("Pull request context", move || {
        source_control::git_range_context(root, range_base, None, None).map_err(git_host_error)
    })
    .await?;
    let prompt = pull_request_details_prompt(&base, &range, instructions(&settings))?;
    let plan = plan_command(&settings, OPERATION, &prompt)?;
    let label = plan.label.clone();
    let output = run_command(plan, &workspace.path, settings.timeout_seconds, cancel_rx).await?;
    Ok((parse_pull_request_details(&output), label))
}

fn instructions(settings: &RuntimeAiAssistSettings) -> &str {
    settings
        .instructions_by_operation
        .get(OPERATION)
        .map(String::as_str)
        .unwrap_or_default()
}

fn pull_request_details_prompt(
    base: &str,
    range: &GitRangeContext,
    custom_instructions: &str,
) -> HostResult<String> {
    if range.commits.is_empty() && range.files.is_empty() && range.patch.trim().is_empty() {
        return Err(HostError::state(
            "No commits or changes found against the base branch.",
        ));
    }
    if range.head_branch.as_deref() == Some(base) {
        return Err(HostError::state(
            "Head branch is the same as the base branch.",
        ));
    }
    let commits = if range.commits.is_empty() {
        "(no commits in range)".to_string()
    } else {
        range
            .commits
            .iter()
            .map(|commit| {
                let short: String = commit.oid.chars().take(7).collect();
                format!("- {short} {}", commit.subject)
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    let files = if range.files.is_empty() {
        "(no file list)".to_string()
    } else {
        range
            .files
            .iter()
            .map(|file| {
                let counts = [
                    file.added.map(|added| format!("+{added}")),
                    file.removed.map(|removed| format!("-{removed}")),
                ]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" ");
                let badge = status_badge(file.status);
                if counts.is_empty() {
                    format!("- {badge} {}", file.path)
                } else {
                    format!("- {badge} {} ({counts})", file.path)
                }
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    let mut prompt = [
        "You are generating a GitHub-style pull request title and description.",
        "Return only the PR text. Do not include a preamble, quotes, or code fences.",
        "",
        "Rules:",
        "- First line: concise PR title (imperative mood preferred, <= 72 chars, no trailing period).",
        "- Then a blank line.",
        "- Then a markdown-friendly description explaining WHAT changed and WHY.",
        "- Use only the commits and patch range below as context.",
        "- Do not invent reviewers, issue numbers, or screenshots that are not in the context.",
        "",
        &format!("Base branch: {base}"),
        &format!(
            "Head branch: {}",
            range.head_branch.as_deref().unwrap_or("(detached)")
        ),
        "",
        "Commits (newest first):",
        &limit_prompt_section(&commits, COMMITS_BUDGET),
        "",
        "Changed files:",
        &limit_prompt_section(&files, FILES_BUDGET),
        "",
        "Patch range:",
        "```diff",
        &truncate_diff_for_prompt(&range.patch),
        "```",
    ]
    .join("\n");
    let custom_instructions = custom_instructions.trim();
    if !custom_instructions.is_empty() {
        prompt.push_str("\n\nAdditional user instructions:\n");
        prompt.push_str(&limit_prompt_section(
            custom_instructions,
            INSTRUCTIONS_BUDGET,
        ));
    }
    Ok(prompt)
}

/// The desktop's single-letter change badges.
fn status_badge(status: GitChangeStatus) -> &'static str {
    match status {
        GitChangeStatus::Modified => "M",
        GitChangeStatus::Added => "A",
        GitChangeStatus::Deleted => "D",
        GitChangeStatus::Renamed => "R",
        GitChangeStatus::Copied => "C",
        GitChangeStatus::Untracked => "U",
    }
}

/// The desktop's `parseGeneratedPullRequestDetails`: the first line is the
/// title, capped at 72 characters without a trailing period; the rest is the
/// body.
pub(super) fn parse_pull_request_details(raw: &str) -> PullRequestDetails {
    let normalized = clean_generated_text(raw);
    let mut lines = normalized.split('\n');
    let subject = lines
        .next()
        .unwrap_or_default()
        .trim()
        .trim_end_matches('.');
    let title = if subject.is_empty() {
        "Update Project".to_string()
    } else {
        subject
            .chars()
            .take(MAX_TITLE_CHARS)
            .collect::<String>()
            .trim_end()
            .to_string()
    };
    let body = lines.collect::<Vec<_>>().join("\n").trim().to_string();
    PullRequestDetails {
        title,
        body: (!body.is_empty()).then_some(body),
    }
}

#[cfg(test)]
#[path = "ai_assist_pull_request_details_tests.rs"]
mod tests;
