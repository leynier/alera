use alera_core::runtime::RuntimeAiTextGenerationSettings;
use alera_native::api::git::{self, GitChangeStatus, GitRangeContext};
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_text_commit_message::clean_generated_text;
use super::ai_text_requests::{active_generations, plan_command, run_command};
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

const COMMIT_SUMMARY_BUDGET: usize = 8_000;
const FILE_SUMMARY_BUDGET: usize = 6_000;
const PATCH_BUDGET: usize = 200_000;
const CUSTOM_INSTRUCTIONS_BUDGET: usize = 4_000;

impl ServerActor {
    pub(super) fn start_ai_text_pull_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let workspace_path = required_non_blank(payload, "workspacePath")?;
        let base_branch = required_non_blank(payload, "baseBranch")?;
        let head_branch = payload
            .get("headBranch")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned);
        let runtime_store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let (cancel_tx, cancel_rx) = oneshot::channel();
        let mut active = active_generations()
            .lock()
            .map_err(|_| HostError::state("AI text generation state is unavailable."))?;
        if active.contains_key(&operation_id) {
            return Err(HostError::state(
                "AI text generation is already running for this operation.",
            ));
        }
        active.insert(operation_id.clone(), cancel_tx);
        drop(active);
        tokio::spawn(async move {
            let result = async {
                let settings = runtime_store
                    .effective_ai_text_generation_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                generate_pull_request_details(
                    &workspace_path,
                    &base_branch,
                    head_branch.as_deref(),
                    settings,
                    cancel_rx,
                )
                .await
            }
            .await;
            if let Ok(mut active) = active_generations().lock() {
                active.remove(&operation_id);
            }
            let _ = inbox.send(ServerCommand::AiTextGenerationFinished {
                client_id,
                request_id,
                result,
            });
        });
        Ok(())
    }
}

async fn generate_pull_request_details(
    workspace_path: &str,
    base_branch: &str,
    head_branch: Option<&str>,
    settings: RuntimeAiTextGenerationSettings,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<Value> {
    if !settings.enabled {
        return Err(HostError::state("AI text generation is disabled."));
    }
    let path = workspace_path.to_owned();
    let base = base_branch.to_owned();
    let requested_head = head_branch.map(str::to_owned);
    let instructions = settings
        .instructions_by_operation
        .get("pullRequestDetails")
        .cloned()
        .unwrap_or_default();
    let prompt = tokio::task::spawn_blocking(move || {
        let context = git::git_range_context(path, base, Some(40), requested_head.clone())
            .map_err(git_error)?;
        pull_request_prompt(context, requested_head.as_deref(), &instructions)
    })
    .await
    .map_err(|error| HostError::state(format!("AI Text Git Task Failed: {error}")))??;
    let plan = plan_command(&settings, "pullRequestDetails", &prompt)?;
    let agent_label = plan.label.clone();
    let timeout_seconds = settings.timeout_seconds;
    let raw = run_command(plan, workspace_path, timeout_seconds, cancel_rx).await?;
    let text = clean_generated_text(&raw);
    if text.trim().is_empty() {
        return Err(HostError::state(format!("{agent_label} returned no text.")));
    }
    Ok(json!({"text": text, "agentLabel": agent_label}))
}

fn pull_request_prompt(
    context: GitRangeContext,
    requested_head: Option<&str>,
    custom_instructions: &str,
) -> HostResult<String> {
    if context.commits.is_empty() && context.files.is_empty() {
        return Err(HostError::state(
            "No commits or changes found against the base branch.",
        ));
    }
    let head = requested_head
        .filter(|value| !value.trim().is_empty())
        .or(context.head_branch.as_deref());
    if head == Some(context.base_ref.as_str()) {
        return Err(HostError::state(
            "Head branch is the same as the base branch.",
        ));
    }
    let commit_summary = if context.commits.is_empty() {
        "(no commits in range)".to_owned()
    } else {
        context
            .commits
            .iter()
            .map(|commit| {
                let short = commit.oid.chars().take(7).collect::<String>();
                format!("- {short} {}", commit.subject)
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    let file_summary = if context.files.is_empty() {
        "(no file list)".to_owned()
    } else {
        context
            .files
            .iter()
            .map(|file| {
                let counts = match (file.added, file.removed) {
                    (None, None) => String::new(),
                    (added, removed) => format!(
                        " (+{} -{})",
                        added.unwrap_or_default(),
                        removed.unwrap_or_default()
                    ),
                };
                format!("- {} {}{counts}", status_badge(file.status), file.path)
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
        &format!("Base branch: {}", context.base_ref),
        &format!("Head branch: {}", head.unwrap_or("(detached)")),
        "",
        "Commits (newest first):",
        &limit_chars(&commit_summary, COMMIT_SUMMARY_BUDGET),
        "",
        "Changed files:",
        &limit_chars(&file_summary, FILE_SUMMARY_BUDGET),
        "",
        "Patch range:",
        "```diff",
        &limit_diff(&context.patch, PATCH_BUDGET),
        "```",
    ]
    .join("\n");
    if !custom_instructions.trim().is_empty() {
        prompt.push_str("\n\nAdditional user instructions:\n");
        prompt.push_str(&limit_chars(
            custom_instructions.trim(),
            CUSTOM_INSTRUCTIONS_BUDGET,
        ));
    }
    Ok(prompt)
}

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

fn limit_chars(value: &str, max_chars: usize) -> String {
    let count = value.chars().count();
    if count <= max_chars {
        return value.to_owned();
    }
    format!(
        "{}\n\n[truncated: {} characters omitted]",
        value.chars().take(max_chars).collect::<String>(),
        count - max_chars
    )
}

fn limit_diff(value: &str, max_chars: usize) -> String {
    let count = value.chars().count();
    if count <= max_chars {
        return value.to_owned();
    }
    format!(
        "{}\n...(diff truncated, {} characters omitted)",
        value.chars().take(max_chars).collect::<String>(),
        count - max_chars
    )
}

fn git_error(error: git::GitError) -> HostError {
    HostError::state(error.context)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_git_status_badges() {
        assert_eq!(status_badge(GitChangeStatus::Modified), "M");
        assert_eq!(status_badge(GitChangeStatus::Renamed), "R");
    }

    #[test]
    fn truncates_unicode_sections_safely() {
        assert_eq!(
            limit_chars("A🦀B", 2),
            "A🦀\n\n[truncated: 1 characters omitted]"
        );
    }
}
