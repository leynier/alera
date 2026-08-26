use alera_native::api::workspace_files::{
    copy_workspace_entry, create_workspace_directory, create_workspace_file,
    delete_workspace_entry, list_workspace_children, move_workspace_entry,
    read_workspace_editor_text_file, rename_workspace_entry, write_workspace_editor_text_file,
    WorkspaceEditorTextFile, WorkspaceFileEntry, WorkspaceFileError, WorkspaceFileErrorKind,
    WorkspaceFileGitStatus, WorkspaceFileKind,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileListRequest {
    workspace_path: String,
    relative_path: String,
    hide_ignored: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFilePathRequest {
    workspace_path: String,
    relative_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileReadRequest {
    workspace_path: String,
    relative_path: String,
    tab_size: i32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileWriteRequest {
    workspace_path: String,
    relative_path: String,
    current_display_content: String,
    original_raw_content: Option<String>,
    original_display_content: Option<String>,
    expected_content_token: Option<String>,
    overwrite_if_changed: bool,
    tab_size: i32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileCreateRequest {
    workspace_path: String,
    parent_relative_path: String,
    name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileRenameRequest {
    workspace_path: String,
    relative_path: String,
    new_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileTransferRequest {
    workspace_path: String,
    relative_path: String,
    target_parent_relative_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceFileDeleteRequest {
    workspace_path: String,
    relative_path: String,
    use_trash: bool,
}

pub(super) async fn list_workspace_files(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileListRequest = parse(payload)?;
    let entries = tokio::task::spawn_blocking(move || {
        list_workspace_children(
            request.workspace_path,
            request.relative_path,
            request.hide_ignored,
        )
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace File Task Failed: {error}")))?
    .map_err(|error| HostError::state(explorer_error_message(error.kind)))?;
    Ok(Value::Array(entries.into_iter().map(entry_value).collect()))
}

pub(super) async fn read_workspace_file(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileReadRequest = parse(payload)?;
    let file = run(move || {
        read_workspace_editor_text_file(
            request.workspace_path,
            request.relative_path,
            request.tab_size,
        )
    })
    .await?;
    Ok(editor_file_value(file))
}

pub(super) async fn write_workspace_file(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileWriteRequest = parse(payload)?;
    let file = run(move || {
        write_workspace_editor_text_file(
            request.workspace_path,
            request.relative_path,
            request.current_display_content,
            request.original_raw_content,
            request.original_display_content,
            request.expected_content_token,
            request.overwrite_if_changed,
            request.tab_size,
        )
    })
    .await?;
    Ok(editor_file_value(file))
}

pub(super) async fn create_workspace_file_request(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileCreateRequest = parse(payload)?;
    let entry = run_explorer(move || {
        create_workspace_file(
            request.workspace_path,
            request.parent_relative_path,
            request.name,
        )
    })
    .await?;
    Ok(entry_value(entry))
}

pub(super) async fn create_workspace_directory_request(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileCreateRequest = parse(payload)?;
    let entry = run_explorer(move || {
        create_workspace_directory(
            request.workspace_path,
            request.parent_relative_path,
            request.name,
        )
    })
    .await?;
    Ok(entry_value(entry))
}

pub(super) async fn rename_workspace_file(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileRenameRequest = parse(payload)?;
    let entry = run_explorer(move || {
        rename_workspace_entry(
            request.workspace_path,
            request.relative_path,
            request.new_name,
        )
    })
    .await?;
    Ok(entry_value(entry))
}

pub(super) async fn copy_workspace_file(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileTransferRequest = parse(payload)?;
    let entry = run_explorer(move || {
        copy_workspace_entry(
            request.workspace_path,
            request.relative_path,
            request.target_parent_relative_path,
        )
    })
    .await?;
    Ok(entry_value(entry))
}

pub(super) async fn move_workspace_file(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileTransferRequest = parse(payload)?;
    let entry = run_explorer(move || {
        move_workspace_entry(
            request.workspace_path,
            request.relative_path,
            request.target_parent_relative_path,
        )
    })
    .await?;
    Ok(entry_value(entry))
}

pub(super) async fn delete_workspace_file(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFileDeleteRequest = parse(payload)?;
    run_explorer(move || {
        delete_workspace_entry(
            request.workspace_path,
            request.relative_path,
            request.use_trash,
        )
    })
    .await?;
    Ok(json!({}))
}

pub(super) async fn workspace_file_metadata(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceFilePathRequest = parse(payload)?;
    let relative_path = request.relative_path.clone();
    let parent_relative_path = relative_path
        .rsplit_once('/')
        .map_or("", |(parent, _)| parent)
        .to_string();
    let entries =
        run(move || list_workspace_children(request.workspace_path, parent_relative_path, false))
            .await?;
    let entry = entries
        .into_iter()
        .find(|entry| entry.relative_path == relative_path)
        .ok_or_else(|| HostError::state(format!("Workspace File Not Found: {relative_path}")))?;
    Ok(entry_value(entry))
}

async fn run<T: Send + 'static>(
    operation: impl FnOnce() -> Result<T, alera_native::api::workspace_files::WorkspaceFileError>
        + Send
        + 'static,
) -> HostResult<T> {
    tokio::task::spawn_blocking(operation)
        .await
        .map_err(|error| HostError::state(format!("Workspace File Task Failed: {error}")))?
        .map_err(|error| {
            let message = match error.kind {
                alera_native::api::workspace_files::WorkspaceFileErrorKind::Conflict => {
                    format!("Workspace File Conflict: {}", error.context)
                }
                _ => error.context,
            };
            HostError::state(message)
        })
}

/// Keep explorer action failures aligned with the Flutter workbench copy.
/// These operations are user-facing file actions, so leaking a platform IO
/// description here would make the two clients diverge and expose paths or
/// errno details that Flutter intentionally hides.
async fn run_explorer<T: Send + 'static>(
    operation: impl FnOnce() -> Result<T, WorkspaceFileError> + Send + 'static,
) -> HostResult<T> {
    tokio::task::spawn_blocking(operation)
        .await
        .map_err(|error| HostError::state(format!("Workspace File Task Failed: {error}")))?
        .map_err(|error| HostError::state(explorer_error_message(error.kind)))
}

fn explorer_error_message(kind: WorkspaceFileErrorKind) -> &'static str {
    match kind {
        WorkspaceFileErrorKind::AlreadyExists => "Item already exists",
        WorkspaceFileErrorKind::ProtectedPath => "Path is protected",
        WorkspaceFileErrorKind::OutsideWorkspace => "Path is outside the workspace",
        WorkspaceFileErrorKind::Unsupported => "Operation is unsupported",
        WorkspaceFileErrorKind::NotFound => "Item not found",
        WorkspaceFileErrorKind::Conflict => "File changed on disk",
        WorkspaceFileErrorKind::InvalidPath | WorkspaceFileErrorKind::Io => "File operation failed",
    }
}

fn parse<T: for<'de> Deserialize<'de>>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|error| HostError::format(format!("Invalid Workspace File Request: {error}")))
}

fn editor_file_value(file: WorkspaceEditorTextFile) -> Value {
    json!({
        "rawContent": file.raw_content,
        "displayContent": file.display_content,
        "contentToken": file.content_token,
        "modifiedMillis": file.modified_millis,
        "size": file.size,
    })
}

fn entry_value(entry: WorkspaceFileEntry) -> Value {
    json!({
        "relativePath": entry.relative_path,
        "name": entry.name,
        "kind": match entry.kind {
            WorkspaceFileKind::File => "file",
            WorkspaceFileKind::Directory => "directory",
            WorkspaceFileKind::Symlink => "symlink",
            WorkspaceFileKind::Other => "other",
        },
        "size": entry.size,
        "modifiedMillis": entry.modified_millis,
        "contentToken": entry.content_token,
        "isIgnored": entry.is_ignored,
        "isHidden": entry.is_hidden,
        "isSymlink": entry.is_symlink,
        "isProtected": entry.is_protected,
        "hasChildrenHint": entry.has_children_hint,
        "gitStatus": entry.git_status.map(|status| match status {
            WorkspaceFileGitStatus::Untracked => "untracked",
            WorkspaceFileGitStatus::Added => "added",
            WorkspaceFileGitStatus::Modified => "modified",
        }),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explorer_errors_use_flutter_copy() {
        let cases = [
            (WorkspaceFileErrorKind::AlreadyExists, "Item already exists"),
            (WorkspaceFileErrorKind::ProtectedPath, "Path is protected"),
            (
                WorkspaceFileErrorKind::OutsideWorkspace,
                "Path is outside the workspace",
            ),
            (
                WorkspaceFileErrorKind::Unsupported,
                "Operation is unsupported",
            ),
            (WorkspaceFileErrorKind::NotFound, "Item not found"),
            (WorkspaceFileErrorKind::Conflict, "File changed on disk"),
            (WorkspaceFileErrorKind::InvalidPath, "File operation failed"),
            (WorkspaceFileErrorKind::Io, "File operation failed"),
        ];
        for (kind, expected) in cases {
            assert_eq!(explorer_error_message(kind), expected);
        }
    }

    #[tokio::test]
    async fn lists_workspace_files_with_desktop_metadata() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::create_dir(directory.path().join("src")).unwrap();
        std::fs::write(directory.path().join("readme.md"), "hello").unwrap();
        let result = list_workspace_files(&json!({
            "workspacePath": directory.path(),
            "relativePath": "",
            "hideIgnored": false,
        }))
        .await
        .unwrap();
        let entries = result.as_array().unwrap();
        assert_eq!(entries[0]["name"], "src");
        assert_eq!(entries[0]["kind"], "directory");
        assert_eq!(entries[1]["name"], "readme.md");
        assert_eq!(entries[1]["kind"], "file");
    }
}
