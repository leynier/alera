use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn workspace_identity_prompt(initial_prompt: &str, custom_instructions: &str) -> String {
    let mut sections = vec![
        "Generate the identity for a new development workspace from the user's task.".to_string(),
        "Return only one compact JSON object with exactly these string fields: workspaceName and branchName.".to_string(),
        String::new(),
        "Rules:".to_string(),
        "- workspaceName: concise human-readable title, title case, 2 to 6 words.".to_string(),
        "- branchName: lowercase valid Git branch, use kebab-case, and start with feat/, fix/, chore/, docs/, refactor/, test/, or perf/.".to_string(),
        "- Describe the requested outcome, not the implementation process.".to_string(),
        "- Do not include markdown, explanations, quotes around the whole object, or extra fields.".to_string(),
        String::new(),
        "User task:".to_string(),
        initial_prompt.trim().to_string(),
    ];
    if !custom_instructions.trim().is_empty() {
        sections.extend([
            String::new(),
            "Additional user instructions:".to_string(),
            custom_instructions.trim().to_string(),
        ]);
    }
    sections.join("\n")
}

pub(super) fn parse_workspace_identity(raw: &str) -> HostResult<Value> {
    let trimmed = raw.trim();
    let unfenced = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .and_then(|value| value.strip_suffix("```"))
        .map(str::trim)
        .unwrap_or(trimmed);
    let start = unfenced
        .find('{')
        .ok_or_else(|| HostError::format("AI text returned an invalid workspace identity."))?;
    let end = unfenced
        .rfind('}')
        .ok_or_else(|| HostError::format("AI text returned an invalid workspace identity."))?;
    let value: Value = serde_json::from_str(&unfenced[start..=end])
        .map_err(|_| HostError::format("AI text returned an invalid workspace identity."))?;
    let workspace_name = value
        .get("workspaceName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty() && value.len() <= 80)
        .ok_or_else(|| HostError::format("AI text returned an invalid workspace name."))?;
    let branch_name = value
        .get("branchName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty() && value.len() <= 200)
        .ok_or_else(|| HostError::format("AI text returned an invalid branch name."))?;
    if !alera_core::git::is_valid_branch_name(branch_name)
        .map_err(|error| HostError::state(error.to_string()))?
    {
        return Err(HostError::format(
            "AI text returned an invalid Git branch name.",
        ));
    }
    Ok(json!({
        "workspaceName": workspace_name,
        "branchName": branch_name,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_prompt_includes_custom_workspace_instructions() {
        let prompt = workspace_identity_prompt("Add offline mode", "Use fix/ branches.");
        assert!(prompt.contains("Add offline mode"));
        assert!(prompt.contains("Use fix/ branches."));
        assert!(prompt.contains("workspaceName"));
    }

    #[test]
    fn parses_fenced_workspace_identity() {
        let value = parse_workspace_identity(
            "```json\n{\"workspaceName\":\"Offline Mode\",\"branchName\":\"feat/offline-mode\"}\n```",
        )
        .unwrap();
        assert_eq!(value["workspaceName"], "Offline Mode");
        assert_eq!(value["branchName"], "feat/offline-mode");
    }

    #[test]
    fn rejects_invalid_generated_branch() {
        let result = parse_workspace_identity(
            "{\"workspaceName\":\"Offline Mode\",\"branchName\":\"invalid branch\"}",
        );
        assert!(result.is_err());
    }
}
