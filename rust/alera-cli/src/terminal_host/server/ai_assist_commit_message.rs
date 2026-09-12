//! Commit message generation for a paired phone. The prompt, budgets and
//! cleanup mirror the desktop generator (`ai_assist_prompt.dart`) so both
//! surfaces ask the agent the same question about the same staged changes.

use alera_core::runtime::{RuntimeAiAssistSettings, RuntimeStore, LOCAL_HOST_ID};
use alera_core::source_control::{self, GitChangeArea, GitDiffResult};
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_requests::{active_generations, plan_command, run_command};
use super::host_service_requests::required_non_blank;
use super::mobile_source_control_snapshot::git_host_error;
use super::mobile_workspace_file_requests::spawn_blocking_workspace;
use super::{ServerActor, ServerCommand};

const OPERATION: &str = "commitMessage";
const STAGED_FILES_BUDGET: usize = 6000;
const STAGED_PATCH_BUDGET: usize = 200_000;
const INSTRUCTIONS_BUDGET: usize = 4000;
const MAX_SUBJECT_CHARS: usize = 72;

struct CommitContext {
    branch: Option<String>,
    staged_summary: String,
    staged_patch: String,
}

impl ServerActor {
    pub(super) fn start_ai_assist_commit_message(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let workspace_id = required_non_blank(payload, "workspaceId")?;
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
            let result = generate_commit_message(&store, &workspace_id, cancel_rx).await;
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

/// Whether a phone should offer generation at all. Read per snapshot because
/// the setting syncs from the desktop and can change while the panel is open.
pub(super) async fn ai_commit_message_enabled(store: &RuntimeStore) -> bool {
    store
        .effective_ai_assist_settings()
        .await
        .is_ok_and(|settings| settings.enabled)
}

async fn generate_commit_message(
    store: &RuntimeStore,
    workspace_id: &str,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<Value> {
    let workspace = store
        .find_workspace(workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "Commit messages can only be generated for workspaces on this runtime.",
        ));
    }
    let settings = store
        .effective_ai_assist_settings()
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    if !settings.enabled {
        return Err(HostError::state("AI Assist is disabled."));
    }
    let root = workspace.path.clone();
    let context = spawn_blocking_workspace("Commit context", move || commit_context(&root)).await?;
    let prompt = commit_message_prompt(&context, instructions(&settings));
    let plan = plan_command(&settings, OPERATION, &prompt)?;
    let label = plan.label.clone();
    let output = run_command(plan, &workspace.path, settings.timeout_seconds, cancel_rx).await?;
    Ok(json!({
        "message": clean_generated_commit_message(&output),
        "agentLabel": label,
    }))
}

fn instructions(settings: &RuntimeAiAssistSettings) -> &str {
    settings
        .instructions_by_operation
        .get(OPERATION)
        .map(String::as_str)
        .unwrap_or_default()
}

fn commit_context(root: &str) -> HostResult<CommitContext> {
    let status = source_control::git_status(root.to_string()).map_err(git_host_error)?;
    let staged = status
        .entries
        .iter()
        .filter(|entry| entry.area == GitChangeArea::Staged)
        .collect::<Vec<_>>();
    if staged.is_empty() {
        return Err(HostError::state("No staged changes to summarize."));
    }
    let branch = source_control::git_repository_state(root.to_string())
        .map_err(git_host_error)?
        .branch;
    let staged_summary = staged
        .iter()
        .map(|entry| {
            let counts = [
                entry.added.map(|added| format!("+{added}")),
                entry.removed.map(|removed| format!("-{removed}")),
            ]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" ");
            let name = match &entry.old_path {
                Some(old_path) => format!("{old_path} -> {}", entry.path),
                None => entry.path.clone(),
            };
            if counts.is_empty() {
                format!("- {name}")
            } else {
                format!("- {name} ({counts})")
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    let mut patches = Vec::with_capacity(staged.len());
    for entry in staged {
        let diff =
            source_control::git_diff(root.to_string(), entry.path.clone(), GitChangeArea::Staged)
                .map_err(git_host_error)?;
        patches.push(diff_to_patch(&diff));
    }
    Ok(CommitContext {
        branch: (branch != "HEAD").then_some(branch),
        staged_summary,
        staged_patch: patches.join("\n"),
    })
}

fn diff_to_patch(diff: &GitDiffResult) -> String {
    diff.files
        .iter()
        .map(|file| {
            let mut lines = vec![format!(
                "diff --git a/{} b/{}",
                file.old_path.as_deref().unwrap_or(&file.path),
                file.path
            )];
            if file.is_binary {
                lines.push("Binary file changed".to_string());
            }
            if file.is_large {
                lines.push("Large file preview truncated".to_string());
            }
            lines.extend(file.lines.iter().map(|line| line.text.clone()));
            lines.join("\n")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn commit_message_prompt(context: &CommitContext, custom_instructions: &str) -> String {
    let mut prompt = [
        "You are generating a single git commit message.",
        "Return only the commit message text. Do not include a preamble, quotes, or code fences.",
        "",
        "Rules:",
        "- First line: imperative mood, <= 72 chars, no trailing period.",
        "- Optional body: blank line, then short wrapped bullet points or prose explaining WHY.",
        "- Capture the primary user-visible or developer-visible change.",
        "- Use only the staged changes below as context.",
        "- Do not include \"Co-authored-by\" or other git trailers.",
        "",
        &format!(
            "Branch: {}",
            context.branch.as_deref().unwrap_or("(detached)")
        ),
        "",
        "Staged files:",
        &limit_prompt_section(&context.staged_summary, STAGED_FILES_BUDGET),
        "",
        "Staged patch:",
        "```diff",
        &truncate_diff_for_prompt(&context.staged_patch),
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
    prompt
}

fn limit_prompt_section(value: &str, max_chars: usize) -> String {
    match value.char_indices().nth(max_chars) {
        None => value.to_string(),
        Some((cut, _)) => {
            let omitted = value[cut..].chars().count();
            format!(
                "{}\n\n[truncated: {omitted} characters omitted]",
                &value[..cut]
            )
        }
    }
}

fn truncate_diff_for_prompt(diff: &str) -> String {
    match diff.char_indices().nth(STAGED_PATCH_BUDGET) {
        None => diff.to_string(),
        Some((cut, _)) => {
            let omitted = diff[cut..].chars().count();
            format!(
                "{}\n...(diff truncated, {omitted} characters omitted)",
                &diff[..cut]
            )
        }
    }
}

fn clean_generated_text(raw: &str) -> String {
    let mut text = raw.replace("\r\n", "\n").trim().to_string();
    if let Some((first_line, rest)) = text.split_once('\n') {
        let first_line = first_line.trim();
        let lowered = first_line.to_lowercase();
        let is_progress = ["generating", "thinking"].iter().any(|word| {
            lowered
                .strip_prefix(word)
                .is_some_and(|tail| !tail.starts_with(|c: char| c.is_alphanumeric() || c == '_'))
        });
        let is_ellipsis =
            !first_line.is_empty() && first_line.chars().all(|c| c == '.' || c == '…');
        if is_progress || is_ellipsis {
            text = rest.trim().to_string();
        }
    }
    if let Some(inner) = text
        .strip_prefix("```")
        .and_then(|rest| rest.strip_suffix("```"))
    {
        if let Some((language, body)) = inner.split_once('\n') {
            let is_language = language
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-');
            if is_language && body.ends_with('\n') {
                text = body.trim().to_string();
            }
        }
    }
    text
}

fn clean_generated_commit_message(raw: &str) -> String {
    let normalized = clean_generated_text(raw);
    let mut lines = normalized.split('\n');
    let subject = lines
        .next()
        .unwrap_or_default()
        .trim()
        .trim_end_matches('.');
    let subject = if subject.is_empty() {
        "Update project files"
    } else {
        subject
    };
    let subject = subject
        .chars()
        .take(MAX_SUBJECT_CHARS)
        .collect::<String>()
        .trim_end()
        .to_string();
    let body = lines.collect::<Vec<_>>().join("\n").trim().to_string();
    if body.is_empty() {
        subject
    } else {
        format!("{subject}\n\n{body}")
    }
}

#[cfg(test)]
#[path = "ai_assist_commit_message_tests.rs"]
mod tests;
