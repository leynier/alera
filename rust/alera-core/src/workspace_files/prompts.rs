use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use super::{is_protected_workspace_path, relative_string, workspace_root, WorkspaceFileError};

const MAX_PROMPT_BYTES: u64 = 1024 * 1024;
const MAX_SAVED_PROMPT_COUNT: usize = 128;
const MAX_SAVED_PROMPT_TOTAL_BYTES: usize = 4 * 1024 * 1024;
const BUILTIN_COMMANDS: [&str; 14] = [
    "new",
    "clear",
    "compact",
    "review",
    "plan",
    "model",
    "permissions",
    "rename",
    "resume",
    "mention",
    "skills",
    "apps",
    "status",
    "logs",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodexSavedPromptScope {
    User,
    Repo,
}

#[derive(Debug, Clone)]
pub struct CodexSavedPrompt {
    pub name: String,
    pub description: String,
    pub argument_hint: Option<String>,
    pub body: String,
    pub scope: CodexSavedPromptScope,
}

pub fn list_codex_saved_prompts(
    workspace_path: String,
) -> Result<Vec<CodexSavedPrompt>, WorkspaceFileError> {
    let workspace = workspace_root(&workspace_path)?;
    let mut prompts = BTreeMap::<String, CodexSavedPrompt>::new();
    let mut budget = PromptBudget::default();
    discover_repository_directory(&workspace, &mut prompts, &mut budget);
    if let Some(user_directory) = user_prompts_directory() {
        discover_directory(
            &user_directory,
            CodexSavedPromptScope::User,
            &mut prompts,
            &mut budget,
            false,
        );
    }
    Ok(prompts.into_values().collect())
}

#[derive(Default)]
struct PromptBudget {
    item_count: usize,
    total_bytes: usize,
}

fn discover_repository_directory(
    workspace: &Path,
    prompts: &mut BTreeMap<String, CodexSavedPrompt>,
    budget: &mut PromptBudget,
) {
    let directory = workspace.join(".codex").join("prompts");
    let Ok(canonical) = fs::canonicalize(&directory) else {
        return;
    };
    if !canonical.starts_with(workspace) {
        return;
    }
    let Ok(relative) = relative_string(workspace, &canonical) else {
        return;
    };
    if is_protected_workspace_path(Path::new(&relative)) {
        return;
    }
    discover_directory(
        &canonical,
        CodexSavedPromptScope::Repo,
        prompts,
        budget,
        true,
    );
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
    budget: &mut PromptBudget,
    replace_existing: bool,
) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    let mut entries = entries.flatten().collect::<Vec<_>>();
    entries.sort_by_cached_key(|entry| {
        let name = entry.file_name().to_string_lossy().into_owned();
        (name.to_ascii_lowercase(), name)
    });
    for entry in entries {
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
        let key = name.to_ascii_lowercase();
        let existing = prompts.get(&key);
        if existing.is_some() && !replace_existing {
            continue;
        }
        if existing.is_none() && budget.item_count >= MAX_SAVED_PROMPT_COUNT {
            continue;
        }
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };
        let parsed = parse_frontmatter(&content);
        let prompt = CodexSavedPrompt {
            name: name.to_owned(),
            description: parsed
                .description
                .unwrap_or_else(|| "Run saved prompt".to_owned()),
            argument_hint: parsed.argument_hint,
            body: parsed.body,
            scope,
        };
        let existing_bytes = existing.map(prompt_payload_bytes).unwrap_or(0);
        let prompt_bytes = prompt_payload_bytes(&prompt);
        let total_bytes = budget
            .total_bytes
            .saturating_sub(existing_bytes)
            .saturating_add(prompt_bytes);
        if total_bytes > MAX_SAVED_PROMPT_TOTAL_BYTES {
            continue;
        }
        if existing.is_none() {
            budget.item_count += 1;
        }
        budget.total_bytes = total_bytes;
        prompts.insert(key, prompt);
    }
}

fn prompt_payload_bytes(prompt: &CodexSavedPrompt) -> usize {
    prompt
        .name
        .len()
        .saturating_add(prompt.description.len())
        .saturating_add(prompt.argument_hint.as_ref().map_or(0, String::len))
        .saturating_add(prompt.body.len())
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
            body: String::new(),
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
        if let Some((key, value)) = trimmed.split_once(':') {
            let value = strip_quotes(value.trim());
            match key.trim().to_ascii_lowercase().as_str() {
                "description" => description = Some(value.to_owned()),
                "argument-hint" | "argument_hint" => argument_hint = Some(value.to_owned()),
                _ => {}
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
    fn parses_frontmatter() {
        let prompt =
            parse_frontmatter("---\ndescription: Review\nargument-hint: <file>\n---\nInspect $1\n");
        assert_eq!(prompt.description.as_deref(), Some("Review"));
        assert_eq!(prompt.argument_hint.as_deref(), Some("<file>"));
        assert_eq!(prompt.body, "Inspect $1\n");
    }

    #[test]
    fn repository_prompts_override_case_insensitive_user_names() {
        let user_directory = tempfile::tempdir().unwrap();
        let repository_directory = tempfile::tempdir().unwrap();
        fs::write(user_directory.path().join("Audit.md"), "User prompt").unwrap();
        fs::write(
            repository_directory.path().join("audit.md"),
            "Repository prompt",
        )
        .unwrap();

        let mut prompts = BTreeMap::new();
        let mut budget = PromptBudget::default();
        discover_directory(
            user_directory.path(),
            CodexSavedPromptScope::User,
            &mut prompts,
            &mut budget,
            true,
        );
        discover_directory(
            repository_directory.path(),
            CodexSavedPromptScope::Repo,
            &mut prompts,
            &mut budget,
            true,
        );

        let prompts = prompts.into_values().collect::<Vec<_>>();
        assert_eq!(prompts.len(), 1);
        assert_eq!(prompts[0].name, "audit");
        assert_eq!(prompts[0].body, "Repository prompt");
        assert_eq!(prompts[0].scope, CodexSavedPromptScope::Repo);
    }

    #[test]
    fn local_session_commands_are_not_discovered_as_saved_prompts() {
        let directory = tempfile::tempdir().unwrap();
        fs::write(directory.path().join("resume.md"), "Shadow resume").unwrap();
        fs::write(directory.path().join("custom.md"), "Custom prompt").unwrap();

        let mut prompts = BTreeMap::new();
        let mut budget = PromptBudget::default();
        discover_directory(
            directory.path(),
            CodexSavedPromptScope::User,
            &mut prompts,
            &mut budget,
            true,
        );

        assert!(!prompts.contains_key("resume"));
        assert!(prompts.contains_key("custom"));
    }

    #[cfg(unix)]
    #[test]
    fn repository_prompts_never_follow_directories_outside_the_workspace() {
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        fs::create_dir(workspace.path().join(".codex")).unwrap();
        fs::write(outside.path().join("escaped.md"), "Escaped").unwrap();
        std::os::unix::fs::symlink(outside.path(), workspace.path().join(".codex/prompts"))
            .unwrap();

        let mut prompts = BTreeMap::new();
        let mut budget = PromptBudget::default();
        discover_repository_directory(workspace.path(), &mut prompts, &mut budget);

        assert!(!prompts.contains_key("escaped"));
    }

    #[test]
    fn saved_prompt_discovery_bounds_count_and_aggregate_payload() {
        let count_directory = tempfile::tempdir().unwrap();
        for index in 0..MAX_SAVED_PROMPT_COUNT + 4 {
            fs::write(
                count_directory.path().join(format!("prompt-{index:03}.md")),
                "Inspect",
            )
            .unwrap();
        }
        let mut prompts = BTreeMap::new();
        let mut budget = PromptBudget::default();
        discover_directory(
            count_directory.path(),
            CodexSavedPromptScope::Repo,
            &mut prompts,
            &mut budget,
            true,
        );
        assert_eq!(prompts.len(), MAX_SAVED_PROMPT_COUNT);
        assert!(prompts.contains_key("prompt-000"));
        assert!(prompts.contains_key("prompt-127"));
        assert!(!prompts.contains_key("prompt-128"));

        let bytes_directory = tempfile::tempdir().unwrap();
        let body = "x".repeat(900 * 1024);
        for index in 0..6 {
            fs::write(
                bytes_directory.path().join(format!("large-{index}.md")),
                &body,
            )
            .unwrap();
        }
        let mut prompts = BTreeMap::new();
        let mut budget = PromptBudget::default();
        discover_directory(
            bytes_directory.path(),
            CodexSavedPromptScope::Repo,
            &mut prompts,
            &mut budget,
            true,
        );
        assert!(budget.total_bytes <= MAX_SAVED_PROMPT_TOTAL_BYTES);
        assert_eq!(prompts.len(), 4);
        for index in 0..4 {
            assert!(prompts.contains_key(&format!("large-{index}")));
        }
        assert!(!prompts.contains_key("large-4"));
        assert!(!prompts.contains_key("large-5"));
    }
}
