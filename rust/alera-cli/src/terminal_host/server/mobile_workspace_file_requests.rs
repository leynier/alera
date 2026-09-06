use std::fs;
use std::path::{Path, PathBuf};

use alera_core::runtime::{RuntimeStore, Workspace};
use alera_core::workspace_files::{
    is_protected_workspace_path, open_workspace_file_root, read_workspace_file_range_from_root,
    search_workspace_quick_open_session, start_workspace_quick_open_session_without_symlinks,
    stop_workspace_quick_open_session, WorkspaceFileRoot, WorkspaceQuickOpenSession,
};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::mobile_workspace_file_paths::prompt_attachment_root;
use super::requests::{optional_string_key, require_string_key};
use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) fn start_mobile_workspace_file_request(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<()> {
        let runtime_store = self.runtime_store.clone();
        let runtime_dir = self.runtime_dir.clone();
        let request_type = request_type.to_string();
        let payload = payload.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let operation = request_type.clone();
            let result = handle_mobile_workspace_file_request(
                runtime_store,
                runtime_dir,
                &request_type,
                &payload,
            )
            .await;
            let _ = inbox.send(ServerCommand::MobileWorkspaceFileFinished {
                client_id,
                request_id,
                request_type: operation,
                result,
            });
        });
        Ok(())
    }

    pub(super) fn handle_mobile_workspace_file_finished(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        result: HostResult<Value>,
    ) {
        if !self.clients.contains_key(&client_id) {
            cleanup_orphaned_workspace_file_result(request_type, &result);
            return;
        }
        let response = match &result {
            Ok(value) => ok_response(request_id, value.clone()),
            Err(error) => error_response(request_id, error),
        };
        if !self.try_client_write(client_id, response) {
            cleanup_orphaned_workspace_file_result(request_type, &result);
        }
    }

    pub(super) fn stop_mobile_workspace_quick_open(&self, payload: &Value) -> HostResult<Value> {
        let session_id = require_string_key(payload, "sessionId")?;
        stop_workspace_quick_open_session(WorkspaceQuickOpenSession {
            id: session_id,
            indexed_file_count: 0,
        });
        Ok(json!({}))
    }
}

async fn handle_mobile_workspace_file_request(
    runtime_store: RuntimeStore,
    runtime_dir: PathBuf,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    match request_type {
        "mobile.workspaceQuickOpen.start" => {
            let workspace = workspace_for_mobile_file_request(&runtime_store, payload).await?;
            let root = mobile_workspace_file_root(&runtime_store, payload, &workspace).await?;
            spawn_blocking_workspace("Quick Open indexing", move || {
                start_workspace_quick_open_session_without_symlinks(root)
                    .map_err(workspace_file_error)
                    .map(|session| {
                        json!({
                            "sessionId": session.id,
                            "indexedFileCount": session.indexed_file_count,
                        })
                    })
            })
            .await
        }
        "mobile.workspaceQuickOpen.search" => search_mobile_workspace_quick_open(payload).await,
        "mobile.workspaceFile.read" => read_mobile_workspace_file(&runtime_store, payload).await,
        "mobile.promptAttachment.read" => read_mobile_prompt_attachment(runtime_dir, payload).await,
        _ => Err(HostError::state(
            "Unsupported mobile workspace file operation.",
        )),
    }
}

fn cleanup_orphaned_workspace_file_result(request_type: &str, result: &HostResult<Value>) {
    if request_type != "mobile.workspaceQuickOpen.start" {
        return;
    }
    if let Some(session_id) = result
        .as_ref()
        .ok()
        .and_then(|value| value.get("sessionId"))
        .and_then(Value::as_str)
    {
        stop_workspace_quick_open_session(WorkspaceQuickOpenSession {
            id: session_id.to_string(),
            indexed_file_count: 0,
        });
    }
}

async fn search_mobile_workspace_quick_open(payload: &Value) -> HostResult<Value> {
    let session_id = require_string_key(payload, "sessionId")?;
    let indexed_file_count = payload
        .get("indexedFileCount")
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .unwrap_or(0);
    let query = optional_string_key(payload, "query").unwrap_or_default();
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .unwrap_or(20)
        .min(100);
    spawn_blocking_workspace("Quick Open search", move || {
        search_workspace_quick_open_session(
            WorkspaceQuickOpenSession {
                id: session_id,
                indexed_file_count,
            },
            query,
            limit,
        )
        .map_err(workspace_file_error)
        .map(|matches| {
            json!({
                "items": matches.into_iter().map(|item| json!({
                    "relativePath": item.relative_path,
                    "score": item.score,
                })).collect::<Vec<_>>(),
            })
        })
    })
    .await
}

async fn read_mobile_workspace_file(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let requested_path = require_string_key(payload, "relativePath")?;
    let candidate_root =
        optional_string_key(payload, "cwd").unwrap_or_else(|| workspace.path.clone());
    let known_roots = known_workspace_paths(runtime_store).await?;
    let offset = payload.get("offset").and_then(Value::as_u64).unwrap_or(0);
    let length = payload
        .get("length")
        .and_then(Value::as_u64)
        .unwrap_or(alera_core::workspace_files::MAX_REMOTE_READ_BYTES);
    spawn_blocking_workspace("Workspace file read", move || {
        let (root, relative_path) = if Path::new(&requested_path).is_absolute() {
            absolute_workspace_file_target(&requested_path, known_roots)?
        } else {
            (
                open_validated_mobile_workspace_root(&candidate_root, known_roots)?,
                requested_path,
            )
        };
        let range = read_workspace_file_range_from_root(&root, &relative_path, offset, length)
            .map_err(workspace_file_error)?;
        Ok(workspace_range_response(relative_path, range))
    })
    .await
}

async fn read_mobile_prompt_attachment(runtime_dir: PathBuf, payload: &Value) -> HostResult<Value> {
    let requested_path = require_string_key(payload, "path")?;
    let offset = payload.get("offset").and_then(Value::as_u64).unwrap_or(0);
    let length = payload
        .get("length")
        .and_then(Value::as_u64)
        .unwrap_or(alera_core::workspace_files::MAX_REMOTE_READ_BYTES);
    spawn_blocking_workspace("Prompt attachment read", move || {
        let canonical_path = fs::canonicalize(&requested_path)
            .map_err(|_| HostError::state("Prompt attachment is unavailable."))?;
        let root = prompt_attachment_root(&runtime_dir, &canonical_path)?;
        let root =
            open_workspace_file_root(&root.to_string_lossy()).map_err(workspace_file_error)?;
        let relative_path = canonical_path
            .strip_prefix(root.canonical_path())
            .ok()
            .and_then(|path| path.to_str())
            .filter(|path| !path.is_empty())
            .ok_or_else(|| HostError::state("Prompt attachment path is invalid."))?
            .to_string();
        let range = read_workspace_file_range_from_root(&root, &relative_path, offset, length)
            .map_err(workspace_file_error)?;
        Ok(workspace_range_response(relative_path, range))
    })
    .await
}

fn workspace_range_response(
    relative_path: String,
    range: alera_core::workspace_files::WorkspaceFileRange,
) -> Value {
    json!({
        "relativePath": relative_path,
        "offset": range.offset,
        "nextOffset": range.next_offset,
        "totalBytes": range.total_bytes,
        "mimeType": range.mime_type,
        "isText": range.is_text,
        "dataBase64": STANDARD.encode(range.bytes),
    })
}

async fn workspace_for_mobile_file_request(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Workspace> {
    let workspace_id = require_string_key(payload, "workspaceId")?;
    runtime_store
        .find_workspace(&workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))
}

async fn mobile_workspace_file_root(
    runtime_store: &RuntimeStore,
    payload: &Value,
    workspace: &Workspace,
) -> HostResult<String> {
    let candidate = optional_string_key(payload, "cwd").unwrap_or_else(|| workspace.path.clone());
    let roots = known_workspace_paths(runtime_store).await?;
    let display_candidate = candidate.clone();
    spawn_blocking_workspace("Workspace root validation", move || {
        let candidate_root = fs::canonicalize(&candidate).map_err(|error| {
            HostError::state(format!("Codex working directory is unavailable: {error}"))
        })?;
        let roots = roots
            .iter()
            .filter_map(|path| fs::canonicalize(path).ok())
            .collect();
        if !candidate_root.is_dir() {
            return Err(HostError::state(format!(
                "Codex working directory is not a directory: {}",
                candidate_root.display()
            )));
        }
        validated_mobile_workspace_root(&candidate_root, roots).map_err(|error| {
            HostError::state(format!(
                "Codex working directory is unavailable: {} ({error})",
                Path::new(&display_candidate).display()
            ))
        })
    })
    .await
}

async fn known_workspace_paths(runtime_store: &RuntimeStore) -> HostResult<Vec<String>> {
    Ok(runtime_store
        .list_all_workspaces()
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .into_iter()
        .map(|workspace| workspace.path)
        .collect())
}

async fn spawn_blocking_workspace<T: Send + 'static>(
    operation: &'static str,
    task: impl FnOnce() -> HostResult<T> + Send + 'static,
) -> HostResult<T> {
    tokio::task::spawn_blocking(task)
        .await
        .map_err(|error| HostError::state(format!("{operation} failed: {error}")))?
}

fn absolute_workspace_file_target(
    requested: &str,
    roots: Vec<String>,
) -> HostResult<(WorkspaceFileRoot, String)> {
    let candidate = fs::canonicalize(requested)
        .map_err(|_| HostError::state("Workspace file is unavailable."))?;
    let root = roots
        .into_iter()
        .filter_map(|root| open_workspace_file_root(&root).ok())
        .filter(|root| candidate.starts_with(root.canonical_path()))
        .max_by_key(|root| root.canonical_path().components().count())
        .ok_or_else(|| HostError::state("Workspace file is outside known workspaces."))?;
    let relative = candidate
        .strip_prefix(root.canonical_path())
        .ok()
        .and_then(|path| path.to_str())
        .filter(|path| !path.is_empty())
        .ok_or_else(|| HostError::state("Workspace file path is invalid."))?;
    let relative = relative.to_string();
    #[cfg(windows)]
    let relative = relative.replace('\\', "/");
    Ok((root, relative))
}

fn open_validated_mobile_workspace_root(
    candidate: &str,
    roots: Vec<String>,
) -> HostResult<WorkspaceFileRoot> {
    let candidate_root = open_workspace_file_root(candidate).map_err(workspace_file_error)?;
    let known_roots = roots
        .into_iter()
        .filter_map(|root| open_workspace_file_root(&root).ok())
        .map(|root| root.canonical_path().to_path_buf())
        .collect();
    validated_mobile_workspace_root(candidate_root.canonical_path(), known_roots).map_err(
        |error| {
            HostError::state(format!(
                "Codex working directory is unavailable: {} ({error})",
                Path::new(candidate).display()
            ))
        },
    )?;
    Ok(candidate_root)
}

fn validated_mobile_workspace_root(candidate: &Path, roots: Vec<PathBuf>) -> HostResult<String> {
    let root = roots
        .into_iter()
        .filter(|root| candidate.starts_with(root))
        .max_by_key(|root| root.components().count())
        .ok_or_else(|| HostError::state("outside known workspaces"))?;
    let relative = candidate
        .strip_prefix(&root)
        .map_err(|_| HostError::state("outside known workspaces"))?;
    if is_protected_workspace_path(relative) {
        return Err(HostError::state("protected workspace metadata"));
    }
    Ok(candidate.to_string_lossy().into_owned())
}

fn workspace_file_error(error: alera_core::workspace_files::WorkspaceFileError) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(all(test, unix))]
#[path = "mobile_workspace_file_requests_platform_tests.rs"]
mod platform_tests;

#[cfg(test)]
mod tests {
    use super::super::actor_test_harness::test_actor;
    use super::{
        absolute_workspace_file_target, prompt_attachment_root, validated_mobile_workspace_root,
    };
    use serde_json::json;
    use std::collections::HashMap;
    use std::path::Path;

    #[test]
    fn prompt_attachment_reads_are_limited_to_runtime_upload_stores() {
        let runtime = tempfile::tempdir().unwrap();
        let files = runtime.path().join("prompt-files");
        let outside = runtime.path().join("outside");
        std::fs::create_dir_all(&files).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        let attachment = files.join("attachment.txt");
        let unrelated = outside.join("private.txt");
        std::fs::write(&attachment, b"attachment").unwrap();
        std::fs::write(&unrelated, b"private").unwrap();

        let attachment = std::fs::canonicalize(attachment).unwrap();
        let unrelated = std::fs::canonicalize(unrelated).unwrap();
        assert!(prompt_attachment_root(runtime.path(), &attachment).is_ok());
        assert!(prompt_attachment_root(runtime.path(), &unrelated).is_err());
    }

    #[test]
    fn mobile_roots_reject_protected_workspace_metadata() {
        let workspace = tempfile::tempdir().unwrap();
        let metadata = workspace.path().join(".git");
        std::fs::create_dir(&metadata).unwrap();

        let error =
            validated_mobile_workspace_root(&metadata, vec![workspace.path().to_path_buf()])
                .unwrap_err();

        assert!(error
            .wire_message()
            .contains("protected workspace metadata"));
    }

    #[test]
    fn absolute_files_use_the_most_specific_known_workspace() {
        let directory = tempfile::tempdir().unwrap();
        let parent = directory.path().join("workspace");
        let nested = parent.join("packages/app");
        let file = nested.join("lib/main.dart");
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(&file, b"void main() {}").unwrap();
        let nested_canonical = std::fs::canonicalize(&nested).unwrap();

        let (root, relative) = absolute_workspace_file_target(
            &file.to_string_lossy(),
            vec![
                parent.to_string_lossy().into_owned(),
                nested.to_string_lossy().into_owned(),
            ],
        )
        .unwrap();

        assert_eq!(root.canonical_path(), nested_canonical);
        assert_eq!(relative, Path::new("lib/main.dart").to_string_lossy());
    }

    #[test]
    fn absolute_files_outside_known_workspaces_are_rejected() {
        let directory = tempfile::tempdir().unwrap();
        let workspace = directory.path().join("workspace");
        let outside = directory.path().join("outside.txt");
        std::fs::create_dir_all(&workspace).unwrap();
        std::fs::write(&outside, b"outside").unwrap();

        let result = absolute_workspace_file_target(
            &outside.to_string_lossy(),
            vec![workspace.to_string_lossy().into_owned()],
        );

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn filesystem_requests_are_parked_before_runtime_lookup() {
        let directory = tempfile::tempdir().unwrap();
        let actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;

        let started = actor.start_mobile_workspace_file_request(
            1,
            1,
            "mobile.workspaceFile.read",
            &json!({
                "workspaceId": "missing",
                "relativePath": "README.md",
            }),
        );

        assert!(started.is_ok());
        tokio::task::yield_now().await;
    }
}
