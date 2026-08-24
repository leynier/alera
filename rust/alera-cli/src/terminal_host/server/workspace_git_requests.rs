use alera_native::api::git;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceGitSnapshotRequest {
    workspace_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceGitActionRequest {
    workspace_path: String,
    action: String,
    path: Option<String>,
    message: Option<String>,
    index: Option<u32>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceGitCommitCompareRequest {
    workspace_path: String,
    commit_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceGitDiffRequest {
    workspace_path: String,
    file_path: Option<String>,
    old_path: Option<String>,
    area: Option<String>,
    commit_id: Option<String>,
    parent_id: Option<String>,
}

pub(super) async fn snapshot(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceGitSnapshotRequest = parse(payload)?;
    tokio::task::spawn_blocking(move || snapshot_sync(request.workspace_path))
        .await
        .map_err(|error| HostError::state(format!("Workspace Git Task Failed: {error}")))?
}

pub(super) async fn action(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceGitActionRequest = parse(payload)?;
    tokio::task::spawn_blocking(move || action_sync(request))
        .await
        .map_err(|error| HostError::state(format!("Workspace Git Task Failed: {error}")))?
}

pub(super) async fn commit_compare(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceGitCommitCompareRequest = parse(payload)?;
    tokio::task::spawn_blocking(move || {
        let result = git::git_commit_compare(request.workspace_path, request.commit_id)
            .map_err(git_error)?;
        Ok(json!({
            "commitId": result.summary.commit_oid,
            "parentId": result.summary.parent_oid,
            "files": result.entries.into_iter().map(|entry| json!({
                "path": entry.path,
                "oldPath": entry.old_path,
                "status": format!("{:?}", entry.status),
                "added": entry.added,
                "removed": entry.removed,
            })).collect::<Vec<_>>(),
        }))
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace Git Task Failed: {error}")))?
}

pub(super) async fn diff(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceGitDiffRequest = parse(payload)?;
    tokio::task::spawn_blocking(move || {
        let result = if let Some(commit_id) = request.commit_id {
            git::git_commit_diff(
                request.workspace_path,
                commit_id,
                request.parent_id,
                request.file_path,
                request.old_path,
            )
        } else if let (Some(file_path), Some(area)) = (request.file_path.clone(), request.area) {
            git::git_diff(request.workspace_path, file_path, parse_change_area(&area)?)
        } else {
            git::git_diff_all(request.workspace_path, request.file_path)
        }
        .map_err(git_error)?;
        Ok(serialize_diff(result))
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace Git Task Failed: {error}")))?
}

fn snapshot_sync(workspace_path: String) -> HostResult<Value> {
    let state = git::git_repository_state(workspace_path.clone()).map_err(git_error)?;
    let status = git::git_status(workspace_path.clone()).map_err(git_error)?;
    let diff = git::git_diff_all(workspace_path.clone(), None).map_err(git_error)?;
    let history = git::git_history(workspace_path.clone(), Some(50), None).map_err(git_error)?;
    let stashes = git::git_list_stashes(workspace_path).map_err(git_error)?;
    let current_ref = history.current_ref.as_ref().map(serialize_history_ref);
    let remote_ref = history.remote_ref.as_ref().map(serialize_history_ref);
    let base_ref = history.base_ref.as_ref().map(serialize_history_ref);
    let merge_base = history.merge_base.clone();
    let has_incoming_changes = history.has_incoming_changes;
    let has_outgoing_changes = history.has_outgoing_changes;
    let history_has_more = history.has_more;
    let history_limit = history.limit;
    Ok(json!({
        "branch": state.branch,
        "upstream": state.upstream,
        "ahead": state.ahead,
        "behind": state.behind,
        "hasConflicts": state.has_conflicts,
        "headMessage": state.head_message,
        "changes": status.entries.into_iter().map(|entry| json!({
            "path": entry.path,
            "oldPath": entry.old_path,
            "area": format!("{:?}", entry.area),
            "status": format!("{:?}", entry.status),
            "added": entry.added,
            "removed": entry.removed,
        })).collect::<Vec<_>>(),
        "patch": diff.files.into_iter().flat_map(|file| {
            let path = file.path;
            file.lines.into_iter().map(move |line| format!("{path}: {}", line.text))
        }).take(2_000).collect::<Vec<_>>(),
        "history": history.items.into_iter().map(|item| {
            let full_id = item.id;
            json!({
                "id": item.display_id.unwrap_or_else(|| full_id.clone()),
                "fullId": full_id,
                "parentIds": item.parent_ids,
                "subject": item.subject,
                "message": item.message,
                "author": item.author,
                "timestampMillis": item.timestamp,
                "references": item.references.iter().map(serialize_history_ref).collect::<Vec<_>>(),
            })
        }).collect::<Vec<_>>(),
        "historyMetadata": {
            "currentRef": current_ref,
            "remoteRef": remote_ref,
            "baseRef": base_ref,
            "mergeBase": merge_base,
            "hasIncomingChanges": has_incoming_changes,
            "hasOutgoingChanges": has_outgoing_changes,
            "hasMore": history_has_more,
            "limit": history_limit,
        },
        "stashes": stashes.into_iter().map(|item| json!({
            "index": item.index,
            "reference": item.reference,
            "message": item.message,
            "oid": item.oid,
        })).collect::<Vec<_>>(),
    }))
}

fn serialize_history_ref(item_ref: &git::GitHistoryItemRef) -> Value {
    json!({
        "id": item_ref.id,
        "name": item_ref.name,
        "revision": item_ref.revision,
        "category": item_ref.category.map(|category| format!("{category:?}"))
            .unwrap_or_else(|| "Commits".to_owned()),
    })
}

fn action_sync(request: WorkspaceGitActionRequest) -> HostResult<Value> {
    let workspace_path = request.workspace_path;
    let message = match request.action.as_str() {
        "stageAll" => git::git_stage(workspace_path, None)
            .map(|_| "Staged".to_owned())
            .map_err(git_error)?,
        "stagePath" => git::git_stage(workspace_path, Some(required(request.path, "path")?))
            .map(|_| "Staged File".to_owned())
            .map_err(git_error)?,
        "unstageAll" => git::git_unstage(workspace_path, None)
            .map(|_| "Unstaged".to_owned())
            .map_err(git_error)?,
        "unstagePath" => git::git_unstage(workspace_path, Some(required(request.path, "path")?))
            .map(|_| "Unstaged File".to_owned())
            .map_err(git_error)?,
        "discardAll" => git::git_discard(workspace_path, None)
            .map(|_| "Discarded".to_owned())
            .map_err(git_error)?,
        "discardPath" => git::git_discard(workspace_path, Some(required(request.path, "path")?))
            .map(|_| "Discarded File".to_owned())
            .map_err(git_error)?,
        "commit" => git::git_commit(workspace_path, required(request.message, "message")?)
            .map_err(git_error)?,
        "amend" => git::git_commit_amend(workspace_path, required(request.message, "message")?)
            .map_err(git_error)?,
        "fetch" => git::git_fetch(workspace_path)
            .map(|_| "Fetched".to_owned())
            .map_err(git_error)?,
        "pull" => git::git_pull(workspace_path)
            .map(|_| "Pulled".to_owned())
            .map_err(git_error)?,
        "push" => git::git_push(workspace_path)
            .map(|_| "Pushed".to_owned())
            .map_err(git_error)?,
        "sync" => {
            git::git_pull(workspace_path.clone()).map_err(git_error)?;
            git::git_push(workspace_path)
                .map(|_| "Synced".to_owned())
                .map_err(git_error)?
        }
        "stash" => git::git_stash(workspace_path)
            .map(|_| "Stashed".to_owned())
            .map_err(git_error)?,
        "stashPop" => git::git_stash_pop(
            workspace_path,
            request
                .index
                .ok_or_else(|| HostError::format("Workspace Git Action Omitted index."))?,
        )
        .map(|_| "Applied Stash".to_owned())
        .map_err(git_error)?,
        action => {
            return Err(HostError::format(format!(
                "Unsupported Workspace Git Action: {action}"
            )))
        }
    };
    Ok(json!({ "message": message }))
}

fn required<T>(value: Option<T>, name: &str) -> HostResult<T> {
    value.ok_or_else(|| HostError::format(format!("Workspace Git Action Omitted {name}.")))
}

fn git_error(error: git::GitError) -> HostError {
    HostError::state(error.context)
}

fn parse_change_area(area: &str) -> HostResult<git::GitChangeArea> {
    match area.to_ascii_lowercase().as_str() {
        "staged" => Ok(git::GitChangeArea::Staged),
        "unstaged" => Ok(git::GitChangeArea::Unstaged),
        "untracked" => Ok(git::GitChangeArea::Untracked),
        _ => Err(HostError::format(format!(
            "Unsupported Workspace Git Change Area: {area}"
        ))),
    }
}

fn serialize_diff(result: git::GitDiffResult) -> Value {
    json!({
        "truncated": result.truncated,
        "files": result.files.into_iter().map(|file| json!({
            "path": file.path,
            "oldPath": file.old_path,
            "area": format!("{:?}", file.area),
            "status": format!("{:?}", file.status),
            "lines": file.lines.into_iter().map(|line| json!({
                "text": line.text,
                "kind": format!("{:?}", line.kind),
            })).collect::<Vec<_>>(),
            "added": file.added,
            "removed": file.removed,
            "isBinary": file.is_binary,
            "isLarge": file.is_large,
            "isGitlink": file.is_gitlink,
            "truncated": file.truncated,
            "linePreviewTruncated": file.line_preview_truncated,
        })).collect::<Vec<_>>(),
    })
}

fn parse<T: for<'de> Deserialize<'de>>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|error| HostError::format(format!("Invalid Workspace Git Request: {error}")))
}
