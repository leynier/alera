use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use super::{workspace_root, CodexSavedPrompt, CodexSavedPromptScope, WorkspaceFileError};

const MAX_PROMPT_BYTES: u64 = 1024 * 1024;
const BUILTIN_COMMANDS: [&str; 13] = [
    "new",
    "clear",
    "compact",
    "review",
    "plan",
    "model",
    "permissions",
    "rename",
    "mention",
    "skills",
    "apps",
    "status",
    "logs",
];

pub(super) fn list_codex_saved_prompts(
    workspace_path: String,
) -> Result<Vec<CodexSavedPrompt>, WorkspaceFileError> {
    let workspace = workspace_root(&workspace_path)?;
    let mut prompts = BTreeMap::<String, CodexSavedPrompt>::new();
    if let Some(user_directory) = user_prompts_directory() {
        discover_directory(&user_directory, CodexSavedPromptScope::User, &mut prompts);
    }
    discover_directory(
        &workspace.join(".codex").join("prompts"),
        CodexSavedPromptScope::Repo,
        &mut prompts,
    );
    Ok(prompts.into_values().collect())
}

fn user_prompts_directory() -> Option<PathBuf> {
    if let Some(path) = env::var_os("CODEX_HOME").filter(|value| !value.is_empty()) {
        return Some(PathBuf::from(path).join("prompts"));
    }
    env::var_os("HOME")
        .or_else(|| env::var_os("USERPROFILE"))
        .filter(|value| !value.is_empty())
        .map(|path| PathBuf::from(path).join(".codex").join("prompts"))
}

fn discover_directory(
    directory: &Path,
    scope: CodexSavedPromptScope,
    prompts: &mut BTreeMap<String, CodexSavedPrompt>,
) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(metadata) = fs::symlink_metadata(&path) else {
            continue;
        };
        if !metadata.file_type().is_file() || metadata.len() > MAX_PROMPT_BYTES {
            continue;
        }
        if !path
            .extension()
            .and_then(|value| value.to_str())
            .is_some_and(|value| value.eq_ignore_ascii_case("md"))
        {
            continue;
        }
        let Some(name) = path.file_stem().and_then(|value| value.to_str()) else {
            continue;
        };
        if !valid_name(name) || BUILTIN_COMMANDS.contains(&name.to_ascii_lowercase().as_str()) {
            continue;
        }
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };
        let parsed = parse_frontmatter(&content);
        prompts.insert(
            name.to_owned(),
            CodexSavedPrompt {
                name: name.to_owned(),
                description: parsed
                    .description
                    .unwrap_or_else(|| "Run saved prompt".to_owned()),
                argument_hint: parsed.argument_hint,
                body: parsed.body,
                scope,
            },
        );
    }
}

fn valid_name(name: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    first.is_ascii_alphanumeric()
        && chars.all(|value| value.is_ascii_alphanumeric() || matches!(value, '.' | '_' | '-'))
}

struct ParsedPrompt {
    body: String,
    description: Option<String>,
    argument_hint: Option<String>,
}

fn parse_frontmatter(content: &str) -> ParsedPrompt {
    let mut lines = content.split_inclusive('\n');
    let Some(first_line) = lines.next() else {
        return ParsedPrompt {
            body: content.to_owned(),
            description: None,
            argument_hint: None,
        };
    };
    if first_line.trim() != "---" {
        return ParsedPrompt {
            body: content.to_owned(),
            description: None,
            argument_hint: None,
        };
    }
    let mut description = None;
    let mut argument_hint = None;
    let mut body_start = None;
    let mut byte_offset = first_line.len();
    for line in lines {
        let next_offset = byte_offset + line.len();
        let trimmed = line.trim();
        if trimmed == "---" {
            body_start = Some(next_offset.min(content.len()));
            break;
        }
        if !trimmed.is_empty() && !trimmed.starts_with('#') {
            if let Some((key, value)) = trimmed.split_once(':') {
                let value = strip_quotes(value.trim());
                match key.trim().to_ascii_lowercase().as_str() {
                    "description" => description = Some(value.to_owned()),
                    "argument-hint" | "argument_hint" => argument_hint = Some(value.to_owned()),
                    _ => {}
                }
            }
        }
        byte_offset = next_offset;
    }
    let Some(body_start) = body_start else {
        return ParsedPrompt {
            body: content.to_owned(),
            description: None,
            argument_hint: None,
        };
    };
    ParsedPrompt {
        body: content[body_start..].to_owned(),
        description,
        argument_hint,
    }
}

fn strip_quotes(value: &str) -> &str {
    if value.len() >= 2 {
        let bytes = value.as_bytes();
        if (bytes[0] == b'"' && bytes[value.len() - 1] == b'"')
            || (bytes[0] == b'\'' && bytes[value.len() - 1] == b'\'')
        {
            return &value[1..value.len() - 1];
        }
    }
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_prompt_frontmatter_and_body() {
        let parsed = parse_frontmatter(
            "---\ndescription: 'Review this change'\nargument-hint: <file>\n---\nInspect $1\n",
        );
        assert_eq!(parsed.description.as_deref(), Some("Review this change"));
        assert_eq!(parsed.argument_hint.as_deref(), Some("<file>"));
        assert_eq!(parsed.body, "Inspect $1\n");
    }

    #[test]
    fn parses_windows_frontmatter_without_cutting_the_body() {
        let parsed = parse_frontmatter(
            "---\r\ndescription: Review this change\r\nargument-hint: <file>\r\n---\r\nInspect $1\r\n",
        );
        assert_eq!(parsed.description.as_deref(), Some("Review this change"));
        assert_eq!(parsed.argument_hint.as_deref(), Some("<file>"));
        assert_eq!(parsed.body, "Inspect $1\r\n");
    }

    #[test]
    fn accepts_only_safe_command_names() {
        assert!(valid_name("review.deep_1"));
        assert!(!valid_name("../review"));
        assert!(!valid_name("review prompt"));
    }

    #[test]
    fn repo_prompts_override_user_prompts_by_name() {
        let user = tempfile::tempdir().unwrap();
        let repo = tempfile::tempdir().unwrap();
        fs::write(user.path().join("saved.md"), "User prompt").unwrap();
        fs::write(repo.path().join("saved.md"), "Repo prompt").unwrap();
        let mut prompts = BTreeMap::new();
        discover_directory(user.path(), CodexSavedPromptScope::User, &mut prompts);
        discover_directory(repo.path(), CodexSavedPromptScope::Repo, &mut prompts);
        let prompt = prompts.get("saved").unwrap();
        assert_eq!(prompt.body, "Repo prompt");
        assert_eq!(prompt.scope, CodexSavedPromptScope::Repo);
    }
}
