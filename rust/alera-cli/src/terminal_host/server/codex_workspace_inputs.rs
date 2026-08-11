//! Compatibility normalization for Alera-only input items from older clients.

use std::path::{Component, Path};

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) async fn normalize_legacy_codex_inputs(
    input: Value,
    workspace_path: &str,
) -> HostResult<Value> {
    let Some(items) = input.as_array() else {
        return Ok(json!([]));
    };
    let root = tokio::fs::canonicalize(workspace_path)
        .await
        .map_err(|error| HostError::state(format!("Cannot open Codex workspace: {error}")))?;
    let mut normalized = Vec::with_capacity(items.len());
    for item in items {
        let next = match item.get("type").and_then(Value::as_str) {
            Some("workspaceFile") => validated_workspace_file_reference(item, &root).await,
            Some("localFile") => legacy_file_reference(item),
            _ => Some(item.clone()),
        };
        if let Some(next) = next {
            normalized.push(next);
        }
    }
    Ok(Value::Array(normalized))
}

async fn validated_workspace_file_reference(item: &Value, root: &Path) -> Option<Value> {
    let relative = item.get("path")?.as_str()?.trim();
    let relative_path = Path::new(relative);
    if relative_path.is_absolute()
        || relative_path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return None;
    }
    let candidate = tokio::fs::canonicalize(root.join(relative_path))
        .await
        .ok()?;
    if !candidate.starts_with(root)
        || !tokio::fs::metadata(&candidate)
            .await
            .is_ok_and(|metadata| metadata.is_file())
    {
        return None;
    }
    legacy_file_reference(item)
}

fn legacy_file_reference(item: &Value) -> Option<Value> {
    let path = item.get("path")?.as_str()?.trim();
    if path.is_empty() {
        return None;
    }
    let text = if path.chars().any(char::is_whitespace) && !path.contains('"') {
        format!("\"{path}\"")
    } else {
        path.to_string()
    };
    let placeholder = item
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .or_else(|| {
            Path::new(path)
                .file_name()
                .map(|value| value.to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| path.to_string());
    Some(json!({
        "type": "text",
        "text": text,
        "text_elements": [{
            "byteRange": {"start": 0, "end": text.len()},
            "placeholder": placeholder,
        }],
    }))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::normalize_legacy_codex_inputs;

    #[tokio::test]
    async fn translates_legacy_file_items_without_inlining_file_contents() {
        let workspace = tempfile::tempdir().unwrap();
        std::fs::create_dir(workspace.path().join("docs")).unwrap();
        std::fs::write(workspace.path().join("docs/my notes.md"), "notes").unwrap();
        let normalized = normalize_legacy_codex_inputs(
            json!([
                {"type": "workspaceFile", "name": "notes", "path": "docs/my notes.md"},
                {"type": "localFile", "path": "/tmp/report.csv"},
                {"type": "text", "text": "Review these files"}
            ]),
            workspace.path().to_str().unwrap(),
        )
        .await
        .unwrap();

        assert_eq!(normalized[0]["type"], "text");
        assert_eq!(normalized[0]["text"], "\"docs/my notes.md\"");
        assert_eq!(normalized[0]["text_elements"][0]["placeholder"], "notes");
        assert_eq!(normalized[1]["text"], "/tmp/report.csv");
        assert_eq!(normalized[2]["text"], "Review these files");
    }

    #[tokio::test]
    async fn rejects_workspace_file_paths_outside_the_workspace() {
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        std::fs::write(workspace.path().join("inside.txt"), "inside").unwrap();
        std::fs::write(outside.path().join("outside.txt"), "outside").unwrap();
        let normalized = normalize_legacy_codex_inputs(
            json!([
                {"type": "workspaceFile", "path": "inside.txt"},
                {"type": "workspaceFile", "path": "../outside.txt"},
                {"type": "workspaceFile", "path": outside.path().join("outside.txt")},
                {"type": "localFile", "path": outside.path().join("outside.txt")}
            ]),
            workspace.path().to_str().unwrap(),
        )
        .await
        .unwrap();

        assert_eq!(normalized.as_array().unwrap().len(), 2);
        assert_eq!(normalized[0]["text"], "inside.txt");
        assert_eq!(
            normalized[1]["text"],
            outside
                .path()
                .join("outside.txt")
                .to_string_lossy()
                .as_ref()
        );
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn rejects_workspace_file_symlinks_that_escape_the_workspace() {
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let outside_file = outside.path().join("outside.txt");
        std::fs::write(&outside_file, "outside").unwrap();
        std::os::unix::fs::symlink(&outside_file, workspace.path().join("escaped.txt")).unwrap();

        let normalized = normalize_legacy_codex_inputs(
            json!([{"type": "workspaceFile", "path": "escaped.txt"}]),
            workspace.path().to_str().unwrap(),
        )
        .await
        .unwrap();

        assert_eq!(normalized, json!([]));
    }
}
