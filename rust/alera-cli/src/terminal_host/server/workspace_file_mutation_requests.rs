//! `workspace.files.write|create|rename|copy|move|delete`: the desktop's
//! Explorer and editor mutations for a workspace whose checkout lives on this
//! host. Local clients only; mobile keeps its own `mobile.*` verbs.
//!
//! Every operation runs `alera_core::workspace_files` against the workspace
//! record's path, so the containment and protected-path rules are the ones
//! the desktop bridge applies to local checkouts. A file error is answered as
//! a typed conflict (`errorCode = workspaceFile`, `errorDetails.kind`) so the
//! Dart client can rebuild the same `WorkspaceFileError` the bridge throws.

use alera_core::runtime::RuntimeStore;
use alera_core::workspace_files::{self as files, WorkspaceExplorerEntry, WorkspaceFileError};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::{optional_string_key, require_string_key};

pub(super) const WORKSPACE_FILE_ERROR_CODE: &str = "workspaceFile";

pub(super) fn is_workspace_file_mutation(request_type: &str) -> bool {
    matches!(
        request_type,
        "workspace.files.write"
            | "workspace.files.create"
            | "workspace.files.rename"
            | "workspace.files.copy"
            | "workspace.files.move"
            | "workspace.files.delete"
    )
}

pub(super) async fn handle_workspace_file_mutation(
    runtime_store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let root = workspace.path.clone();
    let payload = payload.clone();
    match request_type {
        "workspace.files.write" => {
            let relative_path = require_string_key(&payload, "relativePath")?;
            let write = WriteRequest::parse(&payload)?;
            spawn_blocking_workspace("Workspace file write", move || {
                let content = write.encoded_content();
                let written = files::write_workspace_file(
                    &root,
                    &relative_path,
                    content.as_bytes(),
                    write.expected_content_token.as_deref(),
                    write.overwrite_if_changed,
                )
                .map_err(workspace_file_conflict)?;
                let mut response = json!({
                    "relativePath": written.relative_path,
                    "contentToken": written.content_token,
                    "modifiedMillis": written.modified_millis,
                    "size": written.size,
                });
                if let Some(tab_size) = write.tab_size {
                    response["rawContent"] = json!(content);
                    response["displayContent"] =
                        json!(files::expand_workspace_editor_tabs(&content, tab_size));
                }
                Ok(response)
            })
            .await
        }
        "workspace.files.create" => {
            let parent = optional_string_key(&payload, "parentRelativePath").unwrap_or_default();
            let name = require_string_key(&payload, "name")?;
            let directory = payload.get("kind").and_then(Value::as_str) == Some("directory");
            spawn_blocking_workspace("Workspace entry creation", move || {
                let entry = if directory {
                    files::create_workspace_directory(&root, &parent, &name)
                } else {
                    files::create_workspace_file(&root, &parent, &name)
                };
                entry.map(entry_json).map_err(workspace_file_conflict)
            })
            .await
        }
        "workspace.files.rename" => {
            let relative_path = require_string_key(&payload, "relativePath")?;
            let new_name = require_string_key(&payload, "newName")?;
            spawn_blocking_workspace("Workspace entry rename", move || {
                files::rename_workspace_entry(&root, &relative_path, &new_name)
                    .map(entry_json)
                    .map_err(workspace_file_conflict)
            })
            .await
        }
        "workspace.files.copy" | "workspace.files.move" => {
            let relative_path = require_string_key(&payload, "relativePath")?;
            let target =
                optional_string_key(&payload, "targetParentRelativePath").unwrap_or_default();
            let copy = request_type == "workspace.files.copy";
            spawn_blocking_workspace("Workspace entry copy or move", move || {
                let entry = if copy {
                    files::copy_workspace_entry(&root, &relative_path, &target)
                } else {
                    files::move_workspace_entry(&root, &relative_path, &target)
                };
                entry.map(entry_json).map_err(workspace_file_conflict)
            })
            .await
        }
        "workspace.files.delete" => {
            let relative_path = require_string_key(&payload, "relativePath")?;
            let use_trash = payload
                .get("useTrash")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            spawn_blocking_workspace("Workspace entry delete", move || {
                files::delete_workspace_entry(&root, &relative_path, use_trash)
                    .map(|()| json!({}))
                    .map_err(workspace_file_conflict)
            })
            .await
        }
        _ => Err(HostError::state(format!(
            "Unknown terminal host request: {request_type}"
        ))),
    }
}

/// Either raw bytes (`contentBase64`) or the editor triple, which the host
/// encodes with the shared codec so untouched lines keep their raw tabs.
struct WriteRequest {
    content: WriteContent,
    expected_content_token: Option<String>,
    overwrite_if_changed: bool,
    tab_size: Option<i32>,
}

enum WriteContent {
    Bytes(Vec<u8>),
    Editor {
        current_display_content: String,
        original_raw_content: Option<String>,
        original_display_content: Option<String>,
    },
}

impl WriteRequest {
    fn parse(payload: &Value) -> HostResult<Self> {
        let content = if let Some(encoded) = payload.get("contentBase64").and_then(Value::as_str) {
            WriteContent::Bytes(STANDARD.decode(encoded).map_err(|error| {
                HostError::format(format!("contentBase64 is not valid base64: {error}"))
            })?)
        } else if let Some(current) = payload.get("currentDisplayContent").and_then(Value::as_str) {
            // Editor contents are taken verbatim: trimming would drop the
            // trailing newline the line-segment encoder aligns on.
            let verbatim = |key: &str| payload.get(key).and_then(Value::as_str).map(str::to_string);
            WriteContent::Editor {
                current_display_content: current.to_string(),
                original_raw_content: verbatim("originalRawContent"),
                original_display_content: verbatim("originalDisplayContent"),
            }
        } else {
            return Err(HostError::format(
                "workspace.files.write requires contentBase64 or currentDisplayContent.",
            ));
        };
        Ok(Self {
            content,
            expected_content_token: optional_string_key(payload, "expectedContentToken"),
            overwrite_if_changed: payload
                .get("overwriteIfChanged")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            tab_size: payload
                .get("tabSize")
                .and_then(Value::as_i64)
                .and_then(|value| i32::try_from(value).ok()),
        })
    }

    fn encoded_content(&self) -> String {
        match &self.content {
            WriteContent::Bytes(bytes) => String::from_utf8_lossy(bytes).into_owned(),
            WriteContent::Editor {
                current_display_content,
                original_raw_content,
                original_display_content,
            } => files::encode_workspace_editor_text_for_save(
                current_display_content,
                original_raw_content.as_deref(),
                original_display_content.as_deref(),
            ),
        }
    }
}

fn entry_json(entry: WorkspaceExplorerEntry) -> Value {
    json!({
        "relativePath": entry.relative_path,
        "name": entry.name,
        "kind": entry.kind.as_str(),
        "size": entry.size,
        "isHidden": entry.is_hidden,
        "hasChildrenHint": entry.has_children_hint,
    })
}

pub(super) fn workspace_file_conflict(error: WorkspaceFileError) -> HostError {
    HostError::conflict(
        WORKSPACE_FILE_ERROR_CODE,
        error.context.clone(),
        json!({ "kind": error.kind.as_str(), "context": error.context }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn mutations_write_create_rename_and_delete_inside_the_workspace() {
        let directory = tempfile::tempdir().unwrap();
        let checkout = directory.path().join("checkout");
        std::fs::create_dir_all(checkout.join("src")).unwrap();
        std::fs::write(checkout.join("src/a.txt"), "one\ttwo\n").unwrap();
        let store = RuntimeStore::open(&directory.path().join("runtime"))
            .await
            .unwrap();
        let workspace =
            crate::project_management::register_project(&store, checkout.to_str().unwrap(), None)
                .await
                .unwrap()
                .initial_workspace
                .unwrap();
        let id = workspace.id.clone();
        let call = |verb: &'static str, mut payload: Value| {
            let store = store.clone();
            let id = id.clone();
            async move {
                payload["workspaceId"] = json!(id);
                handle_workspace_file_mutation(&store, verb, &payload).await
            }
        };

        let created = call(
            "workspace.files.create",
            json!({"parentRelativePath": "src", "name": "b.txt"}),
        )
        .await
        .unwrap();
        assert_eq!(created["relativePath"], "src/b.txt");
        assert_eq!(created["kind"], "file");
        let folder = call(
            "workspace.files.create",
            json!({"parentRelativePath": "", "name": "docs", "kind": "directory"}),
        )
        .await
        .unwrap();
        assert_eq!(folder["kind"], "directory");

        let written = call(
            "workspace.files.write",
            json!({"relativePath": "src/a.txt", "currentDisplayContent": "one     two\nthree\n",
                "originalRawContent": "one\ttwo\n", "originalDisplayContent": "one     two\n", "tabSize": 8}),
        )
        .await
        .unwrap();
        assert_eq!(written["rawContent"], "one\ttwo\nthree\n");
        assert_eq!(written["displayContent"], "one     two\nthree\n");
        assert_eq!(
            std::fs::read_to_string(checkout.join("src/a.txt")).unwrap(),
            "one\ttwo\nthree\n"
        );
        let conflict = call(
            "workspace.files.write",
            json!({"relativePath": "src/a.txt", "contentBase64": STANDARD.encode("x"), "expectedContentToken": "0:0"}),
        )
        .await
        .unwrap_err();
        let HostError::Conflict { code, details, .. } = conflict else {
            panic!("expected a typed conflict, got {conflict:?}");
        };
        assert_eq!(code, WORKSPACE_FILE_ERROR_CODE);
        assert_eq!(details["kind"], "conflict");
        let overwritten = call(
            "workspace.files.write",
            json!({"relativePath": "src/a.txt", "contentBase64": STANDARD.encode("x"), "expectedContentToken": "0:0", "overwriteIfChanged": true}),
        )
        .await
        .unwrap();
        assert_eq!(overwritten["size"], 1);
        assert!(overwritten.get("rawContent").is_none());

        let renamed = call(
            "workspace.files.rename",
            json!({"relativePath": "src/b.txt", "newName": "c.txt"}),
        )
        .await
        .unwrap();
        assert_eq!(renamed["relativePath"], "src/c.txt");
        let moved = call(
            "workspace.files.move",
            json!({"relativePath": "src/c.txt", "targetParentRelativePath": "docs"}),
        )
        .await
        .unwrap();
        assert_eq!(moved["relativePath"], "docs/c.txt");
        let copied = call(
            "workspace.files.copy",
            json!({"relativePath": "docs/c.txt", "targetParentRelativePath": "docs"}),
        )
        .await
        .unwrap();
        assert_eq!(copied["relativePath"], "docs/c copy.txt");
        call(
            "workspace.files.delete",
            json!({"relativePath": "docs", "useTrash": false}),
        )
        .await
        .unwrap();
        assert!(!checkout.join("docs").exists());

        let escape = call(
            "workspace.files.delete",
            json!({"relativePath": "../checkout", "useTrash": false}),
        )
        .await
        .unwrap_err();
        assert!(matches!(escape, HostError::Conflict { .. }), "{escape:?}");
        assert!(checkout.exists());
        assert!(call(
            "workspace.files.write",
            json!({"relativePath": "src/a.txt"})
        )
        .await
        .unwrap_err()
        .wire_message()
        .contains("contentBase64"));
    }
}
