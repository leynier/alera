use std::collections::BTreeMap;

use super::{
    AutomationDefinition, AutomationRun, AUTOMATION_MAX_PROMPT_BYTES,
    AUTOMATION_MAX_RENDERED_PROMPT_BYTES,
};

const KNOWN_VARIABLES: &[&str] = &[
    "automation.id",
    "automation.name",
    "automation.slug",
    "run.id",
    "run.number",
    "run.scheduledAt",
    "workspace.id",
    "workspace.name",
    "workspace.path",
    "project.id",
    "project.name",
];

pub fn template_variables(template: &str) -> Vec<String> {
    let mut variables = Vec::new();
    let mut cursor = 0;
    while let Some(start) = template[cursor..].find("{{") {
        let start = cursor + start;
        let Some(end) = template[start + 2..]
            .find("}}")
            .map(|value| start + 2 + value)
        else {
            break;
        };
        let value = template[start + 2..end].trim();
        if !variables.iter().any(|item| item == value) {
            variables.push(value.to_string());
        }
        cursor = end + 2;
    }
    variables
}

pub fn validate_prompt_template(template: &str) -> Result<(), String> {
    if template.trim().is_empty() {
        return Err("prompt template is required".to_string());
    }
    if template.len() > AUTOMATION_MAX_PROMPT_BYTES {
        return Err("prompt template is too large".to_string());
    }
    let mut cursor = 0;
    while let Some(start_offset) = template[cursor..].find("{{") {
        let start = cursor + start_offset;
        let Some(end_offset) = template[start + 2..].find("}}") else {
            return Err("prompt template contains an unterminated variable".to_string());
        };
        let end = start + 2 + end_offset;
        let variable = template[start + 2..end].trim();
        if !KNOWN_VARIABLES.contains(&variable) {
            return Err(format!("unknown prompt variable: {{{{{variable}}}}}"));
        }
        cursor = end + 2;
    }
    if template[cursor..].contains("}}") {
        return Err("prompt template contains an unmatched closing delimiter".to_string());
    }
    Ok(())
}

pub fn render_prompt_template(
    definition: &AutomationDefinition,
    _run: &AutomationRun,
    values: &BTreeMap<String, String>,
) -> Result<String, String> {
    validate_prompt_template(&definition.prompt_template)?;
    let mut rendered = String::with_capacity(definition.prompt_template.len());
    let mut cursor = 0;
    while let Some(start_offset) = definition.prompt_template[cursor..].find("{{") {
        let start = cursor + start_offset;
        rendered.push_str(&definition.prompt_template[cursor..start]);
        let end_offset = definition.prompt_template[start + 2..]
            .find("}}")
            .ok_or_else(|| "prompt template contains an unterminated variable".to_string())?;
        let end = start + 2 + end_offset;
        let variable = definition.prompt_template[start + 2..end].trim();
        let value = values
            .get(variable)
            .ok_or_else(|| format!("could not resolve prompt variable: {variable}"))?;
        rendered.push_str(value);
        cursor = end + 2;
    }
    rendered.push_str(&definition.prompt_template[cursor..]);
    if rendered.len() > AUTOMATION_MAX_RENDERED_PROMPT_BYTES {
        return Err("rendered prompt is too large".to_string());
    }
    Ok(redact_known_patterns(&rendered))
}

/// Redacts common pasted credential shapes while intentionally leaving no
/// false promise that arbitrary user-provided secrets can be detected.
pub fn redact_known_patterns(value: &str) -> String {
    value
        .split_whitespace()
        .map(|token| {
            let lower = token.to_ascii_lowercase();
            if lower.starts_with("sk-")
                || lower.starts_with("ghp_")
                || lower.starts_with("github_pat_")
                || lower.starts_with("xoxb-")
                || lower.starts_with("bearer=")
                || lower.starts_with("token=")
            {
                "[redacted]"
            } else {
                token
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn prompt_value_map(
    definition: &AutomationDefinition,
    run: &AutomationRun,
    workspace: Option<(&str, &str, &str)>,
    project: Option<(&str, &str)>,
) -> BTreeMap<String, String> {
    let mut values = BTreeMap::from([
        ("automation.id".to_string(), definition.id.clone()),
        ("automation.name".to_string(), definition.name.clone()),
        ("automation.slug".to_string(), definition.slug.clone()),
        ("run.id".to_string(), run.id.clone()),
        ("run.number".to_string(), run.number.to_string()),
        ("run.scheduledAt".to_string(), run.scheduled_at.to_rfc3339()),
    ]);
    if let Some((id, name, path)) = workspace {
        values.insert("workspace.id".to_string(), id.to_string());
        values.insert("workspace.name".to_string(), name.to_string());
        values.insert("workspace.path".to_string(), path.to_string());
    }
    if let Some((id, name)) = project {
        values.insert("project.id".to_string(), id.to_string());
        values.insert("project.name".to_string(), name.to_string());
    }
    values
}

#[cfg(test)]
mod tests {
    use super::{redact_known_patterns, template_variables, validate_prompt_template};

    #[test]
    fn rejects_unknown_and_unbalanced_variables() {
        assert!(validate_prompt_template("Review {{workspace.name}}").is_ok());
        assert!(validate_prompt_template("Review {{secret.value}}").is_err());
        assert!(validate_prompt_template("Review {{workspace.name").is_err());
        assert!(validate_prompt_template("Review workspace.name}}").is_err());
    }

    #[test]
    fn lists_variables_once_and_redacts_known_patterns() {
        assert_eq!(
            template_variables("{{run.id}} {{run.id}} {{workspace.name}}"),
            vec!["run.id", "workspace.name"]
        );
        assert_eq!(
            redact_known_patterns("token=abc sk-secret value"),
            "[redacted] [redacted] value"
        );
    }
}
