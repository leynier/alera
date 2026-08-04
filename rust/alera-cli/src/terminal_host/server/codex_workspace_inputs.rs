//! Expansion of Alera-only workspace file references before app-server calls.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use serde_json::{json, Value};
use tokio::io::AsyncReadExt;

use crate::terminal_host::host_error::{HostError, HostResult};

const MAX_USER_INPUT_TEXT_CHARS: usize = 1 << 20;

pub(super) async fn expand_workspace_inputs(
    input: Value,
    workspace_path: &str,
) -> HostResult<Value> {
    let root = tokio::fs::canonicalize(workspace_path)
        .await
        .map_err(|error| HostError::state(format!("Cannot open Codex workspace: {error}")))?;
    let Some(items) = input.as_array() else {
        return Ok(json!([]));
    };
    let existing_text_chars = items
        .iter()
        .filter(|item| item.get("type").and_then(Value::as_str) == Some("text"))
        .filter_map(|item| item.get("text").and_then(Value::as_str))
        .map(str::chars)
        .map(Iterator::count)
        .sum::<usize>();
    let mut expanded = Vec::with_capacity(items.len());
    let mut seen = HashSet::<PathBuf>::new();
    let mut remaining = MAX_USER_INPUT_TEXT_CHARS.saturating_sub(existing_text_chars);
    for item in items {
        let item_type = item.get("type").and_then(Value::as_str);
        if item_type == Some("localFile") {
            let Some(path) = item.get("path").and_then(Value::as_str) else {
                continue;
            };
            let path = Path::new(path);
            if tokio::fs::metadata(path)
                .await
                .is_ok_and(|metadata| metadata.is_file())
            {
                push_instruction_if_fits(&mut expanded, &mut remaining, path);
            }
            continue;
        }
        if item_type != Some("workspaceFile") {
            expanded.push(item.clone());
            continue;
        }
        let Some(relative) = item.get("path").and_then(Value::as_str) else {
            continue;
        };
        let relative_path = Path::new(relative);
        if relative_path.is_absolute() {
            continue;
        }
        let Ok(path) = tokio::fs::canonicalize(root.join(relative_path)).await else {
            continue;
        };
        if !path.starts_with(&root) || !seen.insert(path.clone()) {
            continue;
        }
        let Ok(metadata) = tokio::fs::metadata(&path).await else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }
        if metadata.len() > remaining as u64 {
            push_instruction_if_fits(&mut expanded, &mut remaining, &path);
            continue;
        }
        let Ok(file) = tokio::fs::File::open(&path).await else {
            continue;
        };
        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        let mut bounded = file.take((remaining as u64).saturating_add(1));
        if bounded.read_to_end(&mut bytes).await.is_err() {
            continue;
        }
        if bytes.len() > remaining {
            push_instruction_if_fits(&mut expanded, &mut remaining, &path);
            continue;
        }
        if bytes.contains(&0) {
            push_instruction_if_fits(&mut expanded, &mut remaining, &path);
            continue;
        }
        let Ok(content) = String::from_utf8(bytes) else {
            push_instruction_if_fits(&mut expanded, &mut remaining, &path);
            continue;
        };
        let expanded_file = json!({
            "type": "text",
            "text": format!("--- File: {} ---\n{content}", path.display()),
        });
        let expanded_chars = expanded_file["text"]
            .as_str()
            .map(str::chars)
            .map(Iterator::count)
            .unwrap_or_default();
        if expanded_chars <= remaining {
            remaining -= expanded_chars;
            expanded.push(expanded_file);
        } else {
            push_instruction_if_fits(&mut expanded, &mut remaining, &path);
        }
    }
    Ok(Value::Array(expanded))
}

fn read_tool_instruction(path: &Path) -> Value {
    json!({
        "type": "text",
        "text": format!(
            "[File: {} - Use the Read tool to view this file]",
            path.display()
        ),
    })
}

fn push_instruction_if_fits(expanded: &mut Vec<Value>, remaining: &mut usize, path: &Path) {
    let instruction = read_tool_instruction(path);
    let chars = instruction["text"]
        .as_str()
        .map(str::chars)
        .map(Iterator::count)
        .unwrap_or_default();
    if chars <= *remaining {
        *remaining -= chars;
        expanded.push(instruction);
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::expand_workspace_inputs;

    #[tokio::test]
    async fn expands_selected_text_files_and_preserves_other_input() {
        let workspace = tempfile::tempdir().unwrap();
        std::fs::create_dir(workspace.path().join("docs")).unwrap();
        std::fs::write(workspace.path().join("docs/file name.md"), "Hello").unwrap();
        let attachment = workspace.path().join("notes.bin");
        std::fs::write(&attachment, [0, 1, 2]).unwrap();
        let expanded = expand_workspace_inputs(
            json!([
                {"type": "workspaceFile", "path": "docs/file name.md"},
                {"type": "localFile", "path": attachment},
                {"type": "text", "text": "Review it"}
            ]),
            workspace.path().to_str().unwrap(),
        )
        .await
        .unwrap();
        assert!(expanded[0]["text"].as_str().unwrap().contains("Hello"));
        assert!(expanded[1]["text"]
            .as_str()
            .unwrap()
            .contains("Use the Read tool"));
        assert_eq!(expanded[2]["text"], "Review it");
    }

    #[tokio::test]
    async fn rejects_workspace_escapes_and_deduplicates_files() {
        let workspace = tempfile::tempdir().unwrap();
        std::fs::write(workspace.path().join("inside.txt"), "Safe").unwrap();
        let expanded = expand_workspace_inputs(
            json!([
                {"type": "workspaceFile", "path": "../outside.txt"},
                {"type": "workspaceFile", "path": "inside.txt"},
                {"type": "workspaceFile", "path": "inside.txt"}
            ]),
            workspace.path().to_str().unwrap(),
        )
        .await
        .unwrap();
        assert_eq!(expanded.as_array().unwrap().len(), 1);
        assert!(expanded[0]["text"].as_str().unwrap().contains("Safe"));
    }
}
