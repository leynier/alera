use alera_core::runtime::RuntimeAiAssistSettings;
use alera_native::api::git;
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_requests::{active_generations, plan_command, run_command};
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

const STAGED_SUMMARY_BUDGET: usize = 6_000;
const STAGED_DIFF_BUDGET: usize = 200_000;
const CUSTOM_INSTRUCTIONS_BUDGET: usize = 4_000;

impl ServerActor {
    pub(super) fn start_ai_assist_commit_message(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let workspace_path = required_non_blank(payload, "workspacePath")?;
        let runtime_store = self.runtime_store.clone();
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
            let result = async {
                let settings = runtime_store
                    .effective_ai_assist_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                generate_commit_message(&workspace_path, settings, cancel_rx).await
            }
            .await;
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

async fn generate_commit_message(
    workspace_path: &str,
    settings: RuntimeAiAssistSettings,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<Value> {
    if !settings.enabled {
        return Err(HostError::state("AI Assist is disabled."));
    }
    let prompt_path = workspace_path.to_owned();
    let instructions = settings
        .instructions_by_operation
        .get("commitMessage")
        .cloned()
        .unwrap_or_default();
    let prompt =
        tokio::task::spawn_blocking(move || commit_message_prompt(&prompt_path, &instructions))
            .await
            .map_err(|error| HostError::state(format!("AI Assist Git Task Failed: {error}")))??;
    let plan = plan_command(&settings, "commitMessage", &prompt)?;
    let agent_label = plan.label.clone();
    let timeout_seconds = settings.timeout_seconds;
    let raw = run_command(plan, workspace_path, timeout_seconds, cancel_rx).await?;
    let text = clean_generated_commit_message(&raw);
    if text.trim().is_empty() {
        return Err(HostError::state(format!("{agent_label} returned no text.")));
    }
    Ok(json!({"text": text, "agentLabel": agent_label}))
}

fn commit_message_prompt(workspace_path: &str, custom_instructions: &str) -> HostResult<String> {
    let status = git::git_status(workspace_path.to_owned()).map_err(git_error)?;
    let staged = status
        .entries
        .into_iter()
        .filter(|entry| entry.area == git::GitChangeArea::Staged)
        .collect::<Vec<_>>();
    if staged.is_empty() {
        return Err(HostError::state("No staged changes to summarize."));
    }
    let repository = git::git_repository_state(workspace_path.to_owned()).map_err(git_error)?;
    let summary = staged
        .iter()
        .map(|entry| {
            let path = entry
                .old_path
                .as_deref()
                .map(|old_path| format!("{old_path} -> {}", entry.path))
                .unwrap_or_else(|| entry.path.clone());
            let counts = match (entry.added, entry.removed) {
                (None, None) => String::new(),
                (added, removed) => format!(
                    " (+{} -{})",
                    added.unwrap_or_default(),
                    removed.unwrap_or_default()
                ),
            };
            format!("- {path}{counts}")
        })
        .collect::<Vec<_>>()
        .join("\n");
    let mut patches = Vec::with_capacity(staged.len());
    for entry in &staged {
        let diff = git::git_diff(
            workspace_path.to_owned(),
            entry.path.clone(),
            git::GitChangeArea::Staged,
        )
        .map_err(git_error)?;
        patches.push(diff_to_patch(diff));
    }
    let branch = if repository.branch == "HEAD" {
        "(detached)"
    } else {
        repository.branch.as_str()
    };
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
        &format!("Branch: {branch}"),
        "",
        "Staged files:",
        &limit_chars(&summary, STAGED_SUMMARY_BUDGET),
        "",
        "Staged patch:",
        "```diff",
        &limit_diff(&patches.join("\n"), STAGED_DIFF_BUDGET),
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

fn diff_to_patch(diff: git::GitDiffResult) -> String {
    diff.files
        .into_iter()
        .map(|file| {
            let old_path = file.old_path.as_deref().unwrap_or(&file.path);
            let mut lines = vec![format!("diff --git a/{old_path} b/{}", file.path)];
            if file.is_binary {
                lines.push("Binary file changed".to_owned());
            }
            if file.is_large {
                lines.push("Large file preview truncated".to_owned());
            }
            lines.extend(file.lines.into_iter().map(|line| line.text));
            lines.join("\n")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn clean_generated_commit_message(raw: &str) -> String {
    let normalized = clean_generated_text(raw);
    let mut lines = normalized.lines();
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
    let safe_subject = truncate_chars(subject, 72).trim_end().to_owned();
    let body = lines.collect::<Vec<_>>().join("\n").trim().to_owned();
    if body.is_empty() {
        safe_subject
    } else {
        format!("{safe_subject}\n\n{body}")
    }
}

pub(super) fn clean_generated_text(raw: &str) -> String {
    let mut text = raw.replace("\r\n", "\n").trim().to_owned();
    if let Some((first, rest)) = text.split_once('\n') {
        let first = first.trim().to_ascii_lowercase();
        if first.starts_with("generating")
            || first.starts_with("thinking")
            || first
                .chars()
                .all(|character| matches!(character, '.' | '…'))
        {
            text = rest.trim().to_owned();
        }
    }
    if text.starts_with("```") && text.ends_with("```") {
        if let Some(first_newline) = text.find('\n') {
            text = text[first_newline + 1..text.len() - 3].trim().to_owned();
        }
    }
    let trimmed = text.trim_start();
    for prefix in ["- ", "* "] {
        if let Some(value) = trimmed.strip_prefix(prefix) {
            return value.trim().to_owned();
        }
    }
    text.trim().to_owned()
}

fn limit_chars(value: &str, max_chars: usize) -> String {
    let count = value.chars().count();
    if count <= max_chars {
        return value.to_owned();
    }
    format!(
        "{}\n\n[truncated: {} characters omitted]",
        truncate_chars(value, max_chars),
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
        truncate_chars(value, max_chars),
        count - max_chars
    )
}

fn truncate_chars(value: &str, max_chars: usize) -> String {
    value.chars().take(max_chars).collect()
}

fn git_error(error: git::GitError) -> HostError {
    HostError::state(error.context)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleans_fenced_commit_message_and_trailing_period() {
        assert_eq!(
            clean_generated_commit_message("```text\nUpdate files.\n\nExplain why\n```"),
            "Update files\n\nExplain why"
        );
    }

    #[test]
    fn truncates_unicode_without_splitting_a_character() {
        assert_eq!(truncate_chars("A🦀B", 2), "A🦀");
    }
}
