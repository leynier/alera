use alera_core::runtime::WorkspaceSection;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn handoff_identity_context(
    context: &str,
    tab: &alera_core::runtime::WorkspaceTabRecord,
) -> String {
    let bounded = |text: &str, max| text.chars().take(max).collect::<String>();
    let profile = tab
        .payload
        .pointer("/agentProfileLaunchV1/profile/name")
        .and_then(Value::as_str)
        .unwrap_or("");
    let task = tab
        .payload
        .get("initialPrompt")
        .and_then(Value::as_str)
        .or_else(|| {
            tab.payload
                .pointer("/pendingAgentPrompt/prompt")
                .and_then(Value::as_str)
        })
        .unwrap_or("");
    format!(
        "{}\nActive agent title: {}\nProfile: {}\nOriginal task (context only): {}",
        bounded(context, 12000),
        bounded(&tab.title, 200),
        bounded(profile, 200),
        bounded(task, 2000)
    )
}

pub(super) fn workspace_identity_prompt(
    initial_prompt: &str,
    custom_instructions: &str,
    sections: &[WorkspaceSection],
) -> String {
    let fields = if sections.is_empty() {
        "workspaceName and branchName".to_string()
    } else {
        "workspaceName, branchName, and section".to_string()
    };
    let mut lines = vec![
        "Generate the identity for a new development workspace from the user's task.".to_string(),
        format!("Return only one compact JSON object with exactly these string fields: {fields}."),
        String::new(),
        "Rules:".to_string(),
        "- workspaceName: concise human-readable title, title case, 2 to 6 words.".to_string(),
        "- branchName: lowercase valid Git branch, use kebab-case, and start with feat/, fix/, chore/, docs/, refactor/, test/, or perf/.".to_string(),
    ];
    if !sections.is_empty() {
        lines.push(
            "- section: the workspace section the task belongs to. Answer with exactly one of the section names listed below, or \"Others\" when none fits."
                .to_string(),
        );
    }
    lines.extend([
        "- Describe the requested outcome, not the implementation process.".to_string(),
        "- Do not include markdown, explanations, quotes around the whole object, or extra fields."
            .to_string(),
    ]);
    if !sections.is_empty() {
        lines.push(String::new());
        lines.push("Sections:".to_string());
        for section in sections {
            lines.push(format!("- {}", section.name));
        }
    }
    lines.extend([
        String::new(),
        "User task:".to_string(),
        initial_prompt.trim().to_string(),
    ]);
    if !custom_instructions.trim().is_empty() {
        lines.extend([
            String::new(),
            "Additional user instructions:".to_string(),
            custom_instructions.trim().to_string(),
        ]);
    }
    lines.join("\n")
}

pub(super) fn parse_workspace_identity(
    raw: &str,
    sections: &[WorkspaceSection],
) -> HostResult<Value> {
    let trimmed = raw.trim();
    let unfenced = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .and_then(|value| value.strip_suffix("```"))
        .map(str::trim)
        .unwrap_or(trimmed);
    let start = unfenced
        .find('{')
        .ok_or_else(|| HostError::format("AI Assist returned an invalid workspace identity."))?;
    let end = unfenced
        .rfind('}')
        .ok_or_else(|| HostError::format("AI Assist returned an invalid workspace identity."))?;
    let value: Value = serde_json::from_str(&unfenced[start..=end])
        .map_err(|_| HostError::format("AI Assist returned an invalid workspace identity."))?;
    let workspace_name = value
        .get("workspaceName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty() && value.len() <= 80)
        .ok_or_else(|| HostError::format("AI Assist returned an invalid workspace name."))?;
    let branch_name = value
        .get("branchName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty() && value.len() <= 200)
        .ok_or_else(|| HostError::format("AI Assist returned an invalid branch name."))?;
    if !alera_core::git::is_valid_branch_name(branch_name)
        .map_err(|error| HostError::state(error.to_string()))?
    {
        return Err(HostError::format(
            "AI Assist returned an invalid Git branch name.",
        ));
    }
    let mut response = json!({
        "workspaceName": workspace_name,
        "branchName": branch_name,
    });
    if !sections.is_empty() {
        // The store keeps section names unique case-insensitively, so a
        // case-insensitive match here cannot be ambiguous. A missing, unknown,
        // or "Others" answer leaves the workspace unassigned.
        let section_name = value
            .get("section")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty() && value.len() <= 200);
        if let Some(section) = section_name.and_then(|name| {
            sections
                .iter()
                .find(|section| section.name.to_lowercase() == name.to_lowercase())
        }) {
            response["sectionId"] = json!(section.id);
        }
    }
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn section(id: &str, name: &str) -> WorkspaceSection {
        WorkspaceSection {
            id: id.to_string(),
            name: name.to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    #[test]
    fn identity_prompt_includes_custom_workspace_instructions() {
        let prompt = workspace_identity_prompt("Add offline mode", "Use fix/ branches.", &[]);
        assert!(prompt.contains("Add offline mode"));
        assert!(prompt.contains("Use fix/ branches."));
        assert!(prompt.contains("workspaceName"));
    }

    #[test]
    fn identity_prompt_without_sections_omits_the_section_rule() {
        let prompt = workspace_identity_prompt("Add offline mode", "", &[]);
        assert!(prompt.contains("workspaceName and branchName"));
        assert!(!prompt.contains("Sections:"));
        assert!(!prompt.contains("Others"));
    }

    #[test]
    fn identity_prompt_lists_sections_with_others_fallback() {
        let sections = vec![section("a", "Work"), section("b", "Personal")];
        let prompt = workspace_identity_prompt("Add offline mode", "", &sections);
        assert!(prompt.contains("workspaceName, branchName, and section"));
        assert!(prompt.contains("Sections:\n- Work\n- Personal"));
        assert!(prompt.contains("\"Others\" when none fits"));
    }

    #[test]
    fn parses_fenced_workspace_identity() {
        let value = parse_workspace_identity(
            "```json\n{\"workspaceName\":\"Offline Mode\",\"branchName\":\"feat/offline-mode\"}\n```",
            &[],
        )
        .unwrap();
        assert_eq!(value["workspaceName"], "Offline Mode");
        assert_eq!(value["branchName"], "feat/offline-mode");
        assert!(value.get("sectionId").is_none());
    }

    #[test]
    fn resolves_a_returned_section_name_case_insensitively() {
        let sections = vec![section("a", "Work"), section("b", "Personal")];
        let value = parse_workspace_identity(
            "{\"workspaceName\":\"Offline Mode\",\"branchName\":\"feat/offline-mode\",\"section\":\"work\"}",
            &sections,
        )
        .unwrap();
        assert_eq!(value["sectionId"], "a");
    }

    #[test]
    fn others_and_unknown_sections_leave_the_workspace_unassigned() {
        let sections = vec![section("a", "Work")];
        for answer in ["Others", "unknown", ""] {
            let value = parse_workspace_identity(
                &format!("{{\"workspaceName\":\"Offline Mode\",\"branchName\":\"feat/offline-mode\",\"section\":\"{answer}\"}}"),
                &sections,
            )
            .unwrap();
            assert!(value.get("sectionId").is_none(), "answer: {answer}");
        }
        let value = parse_workspace_identity(
            "{\"workspaceName\":\"Offline Mode\",\"branchName\":\"feat/offline-mode\"}",
            &sections,
        )
        .unwrap();
        assert!(value.get("sectionId").is_none());
    }

    #[test]
    fn ignores_a_returned_section_when_assignment_was_not_requested() {
        let value = parse_workspace_identity(
            "{\"workspaceName\":\"Offline Mode\",\"branchName\":\"feat/offline-mode\",\"section\":\"Work\"}",
            &[],
        )
        .unwrap();
        assert!(value.get("sectionId").is_none());
    }

    #[test]
    fn rejects_invalid_generated_branch() {
        let result = parse_workspace_identity(
            "{\"workspaceName\":\"Offline Mode\",\"branchName\":\"invalid branch\"}",
            &[],
        );
        assert!(result.is_err());
    }
}
