//! Workspace identity for a prompt that does not name its project.
//!
//! `aiText.workspaceIdentity.generate` with `inferProject` and no `projectId`
//! asks AI Assist to pick one of the registered projects together with the
//! name, branch, and section, in one call. An answer that names no listed
//! project returns `projectUnknown` instead of a guess.

use alera_core::runtime::{Project, WorkspaceSection};
use serde_json::{json, Value};

use super::ai_assist_operation_registry::active_generations;
use super::ai_assist_workspace_identity::parse_workspace_identity;
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};

/// Projects listed in the prompt; more would crowd out the task itself.
const MAX_PROJECT_CHOICES: usize = 50;
const UNKNOWN_PROJECT: &str = "Unknown";

impl ServerActor {
    pub(super) fn start_ai_assist_project_identity(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let prompt = required_non_blank(payload, "prompt")?;
        let auto_assign_section = payload
            .get("autoAssignSection")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let (registration, cancel_rx) = active_generations().register(operation_id, None)?;
        tokio::spawn(async move {
            let result = async {
                let projects = store
                    .list_projects()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if projects.is_empty() {
                    return Err(HostError::state("No projects are registered in Alera."));
                }
                let settings = store
                    .effective_ai_assist_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if !settings.enabled {
                    return Err(HostError::state("AI Assist is disabled."));
                }
                let sections = if auto_assign_section {
                    store.list_workspace_sections().await.unwrap_or_default()
                } else {
                    Vec::new()
                };
                let choices = &projects[..projects.len().min(MAX_PROJECT_CHOICES)];
                let custom = settings
                    .instructions_by_operation
                    .get("workspaceIdentity")
                    .cloned()
                    .unwrap_or_default();
                let text = project_identity_prompt(&prompt, &custom, choices, &sections);
                let directory = neutral_working_directory();
                let (raw, _) = super::ai_assist_generation::generate_ai_assist_output(
                    &settings,
                    "workspaceIdentity",
                    &text,
                    &directory,
                    cancel_rx,
                )
                .await?;
                parse_project_identity(&raw, choices, &sections)
            }
            .await;
            drop(registration);
            let _ = inbox
                .send_wait(ServerCommand::AiAssistFinished {
                    client_id,
                    request_id,
                    result,
                })
                .await;
        });
        Ok(())
    }
}

/// AI Assist runs outside any one project when choosing between them.
fn neutral_working_directory() -> String {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| std::env::temp_dir().to_string_lossy().into_owned())
}

pub(super) fn project_identity_prompt(
    task: &str,
    custom_instructions: &str,
    projects: &[Project],
    sections: &[WorkspaceSection],
) -> String {
    let fields = if sections.is_empty() {
        "project, workspaceName, and branchName"
    } else {
        "project, workspaceName, branchName, and section"
    };
    let mut lines = vec![
        "Choose the project for a new development workspace and generate its identity from the user's task.".to_owned(),
        format!("Return only one compact JSON object with exactly these string fields: {fields}."),
        String::new(),
        "Rules:".to_owned(),
        format!("- project: exactly one project name from the list below that the task belongs to, or \"{UNKNOWN_PROJECT}\" when the task does not clearly belong to one of them."),
        "- workspaceName: concise human-readable title, title case, 2 to 6 words.".to_owned(),
        "- branchName: lowercase valid Git branch, use kebab-case, and start with feat/, fix/, chore/, docs/, refactor/, test/, or perf/.".to_owned(),
    ];
    if !sections.is_empty() {
        lines.push("- section: the workspace section the task belongs to. Answer with exactly one of the section names listed below, or \"Others\" when none fits.".to_owned());
    }
    lines.extend([
        "- Describe the requested outcome, not the implementation process.".to_owned(),
        "- Do not include markdown, explanations, quotes around the whole object, or extra fields."
            .to_owned(),
        String::new(),
        "Projects:".to_owned(),
    ]);
    for project in projects {
        let name: String = project.name.trim().chars().take(200).collect();
        let path: String = project.repo_path.trim().chars().take(500).collect();
        lines.push(format!("- {name} ({path})"));
    }
    if !sections.is_empty() {
        lines.push(String::new());
        lines.push("Sections:".to_owned());
        for section in sections {
            lines.push(format!("- {}", section.name));
        }
    }
    lines.extend([
        String::new(),
        "User task:".to_owned(),
        task.trim().to_owned(),
    ]);
    if !custom_instructions.trim().is_empty() {
        lines.extend([
            String::new(),
            "Additional user instructions:".to_owned(),
            custom_instructions.trim().to_owned(),
        ]);
    }
    lines.join("\n")
}

/// The identity plus `projectId`, or `projectUnknown: true` with no identity
/// when the answer names no listed project. A name shared by two projects is
/// unknown too: guessing between them is what this avoids.
pub(super) fn parse_project_identity(
    raw: &str,
    projects: &[Project],
    sections: &[WorkspaceSection],
) -> HostResult<Value> {
    let project_answer = project_field(raw);
    let matches = project_answer
        .as_deref()
        .map(|answer| {
            projects
                .iter()
                .filter(|project| project.name.trim().eq_ignore_ascii_case(answer))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let [project] = matches.as_slice() else {
        return Ok(json!({ "projectUnknown": true, "projectAnswer": project_answer }));
    };
    let mut identity = parse_workspace_identity(raw, sections)?;
    identity["projectId"] = json!(project.id);
    Ok(identity)
}

fn project_field(raw: &str) -> Option<String> {
    let start = raw.find('{')?;
    let end = raw.rfind('}')?;
    let value: Value = serde_json::from_str(raw.get(start..=end)?).ok()?;
    let answer = value.get("project")?.as_str()?.trim();
    (!answer.is_empty() && !answer.eq_ignore_ascii_case(UNKNOWN_PROJECT) && answer.len() <= 200)
        .then(|| answer.to_owned())
}

#[cfg(test)]
#[path = "ai_assist_project_inference_tests.rs"]
mod tests;
