//! `git.*`: the desktop `GitBackend` surface for a workspace whose checkout
//! lives on this host. Local clients only; mobile keeps its `mobile.git.*`
//! snapshot verbs.
//!
//! Every verb runs the same `alera_core::source_control` function the desktop
//! bridge calls for a local checkout, so a remote Source Control panel shows
//! the same entries, diffs and history it would show locally. Results are the
//! core types serialized as camelCase JSON; a `GitError` is answered as a typed
//! conflict (`errorCode = gitError`, `errorDetails.kind`) so the Dart client can
//! rebuild the same `GitException` the bridge throws.
//!
//! `path` may name the workspace root or a directory inside it (the Source
//! Control root setting); anything outside the workspace is refused.

use std::path::{Component, Path};

use alera_core::git as core_git;
use alera_core::runtime::{RuntimeStore, Workspace};
use alera_core::source_control::{self as sc, GitChangeArea, GitError};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde::Serialize;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::{optional_string_key, require_string_key};

pub(super) const GIT_ERROR_CODE: &str = "gitError";

pub(super) fn is_workspace_git_verb(request_type: &str) -> bool {
    request_type.starts_with("git.")
}

/// Verbs that change the working tree, index or refs; they take the runtime's
/// mutation queue like a file write does.
pub(super) fn is_workspace_git_write(request_type: &str) -> bool {
    matches!(
        request_type,
        "git.stage"
            | "git.stageArea"
            | "git.unstage"
            | "git.unstageArea"
            | "git.discard"
            | "git.discardArea"
            | "git.commit"
            | "git.commitAmend"
            | "git.pull"
            | "git.stash"
            | "git.stashPop"
            | "git.createAndCheckoutBranch"
            | "git.checkoutBranch"
    )
}

pub(super) async fn handle_workspace_git_request(
    runtime_store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let path = git_path(&workspace, payload)?;
    let payload = payload.clone();
    let request_type = request_type.to_string();
    spawn_blocking_workspace("Workspace git request", move || {
        run_git_verb(&request_type, path, &payload)
    })
    .await
}

fn run_git_verb(request_type: &str, path: String, payload: &Value) -> HostResult<Value> {
    let file_path = optional_string_key(payload, "filePath");
    match request_type {
        "git.isRepository" => encode(sc::is_git_repository(path)),
        "git.isAncestor" => encode(sc::is_ancestor(
            path,
            require_string_key(payload, "ancestorRef")?,
            require_string_key(payload, "descendantRef")?,
        )),
        "git.status" => encode(sc::git_status(path)),
        "git.statusForPath" => encode(sc::git_status_for_path(
            path,
            require_string_key(payload, "filePath")?,
        )),
        "git.submoduleStatus" => encode(sc::git_submodule_status(
            path,
            require_string_key(payload, "submodulePath")?,
            require_area(payload)?,
        )),
        "git.explorerStatus" => encode(sc::git_explorer_status_snapshot(path)),
        "git.diff" => encode(sc::git_diff(
            path,
            require_string_key(payload, "filePath")?,
            require_area(payload)?,
        )),
        "git.diffAll" => encode(sc::git_diff_all(path, file_path)),
        "git.readingDiffPatch" => sc::git_reading_diff_patch(
            path,
            file_path,
            optional_string_key(payload, "oldPath"),
            optional_area(payload)?,
            optional_string_key(payload, "commitOid"),
            optional_string_key(payload, "parentOid"),
            optional_string_key(payload, "baseRef"),
        )
        .map(|bytes| json!({ "patchBase64": STANDARD.encode(bytes) }))
        .map_err(git_conflict),
        "git.diffBlobBytes" => sc::git_diff_blob_bytes(
            path,
            require_string_key(payload, "filePath")?,
            optional_string_key(payload, "oldPath"),
            optional_area(payload)?,
            optional_string_key(payload, "commitOid"),
            optional_string_key(payload, "parentOid"),
            payload
                .get("oldSide")
                .and_then(Value::as_bool)
                .unwrap_or(false),
        )
        .map(|bytes| json!({ "bytesBase64": bytes.map(|bytes| STANDARD.encode(bytes)) }))
        .map_err(git_conflict),
        "git.history" => encode(sc::git_history(
            path,
            optional_u32(payload, "limit"),
            optional_string_key(payload, "baseRef"),
        )),
        "git.commitCompare" => encode(sc::git_commit_compare(
            path,
            require_string_key(payload, "commitId")?,
        )),
        "git.commitDiff" => encode(sc::git_commit_diff(
            path,
            require_string_key(payload, "commitOid")?,
            optional_string_key(payload, "parentOid"),
            file_path,
            optional_string_key(payload, "oldPath"),
        )),
        "git.rangeContext" => encode(sc::git_range_context(
            path,
            require_string_key(payload, "baseRef")?,
            optional_u32(payload, "commitLimit"),
            optional_string_key(payload, "headRef"),
        )),
        "git.repositoryState" => encode(sc::git_repository_state(path)),
        "git.stage" => unit(sc::git_stage(path, file_path)),
        "git.stageArea" => unit(sc::git_stage_area(path, require_area(payload)?, file_path)),
        "git.unstage" => unit(sc::git_unstage(path, file_path)),
        "git.unstageArea" => unit(sc::git_unstage_area(
            path,
            require_area(payload)?,
            file_path,
        )),
        "git.discard" => unit(sc::git_discard(path, file_path)),
        "git.discardArea" => unit(sc::git_discard_area(
            path,
            require_area(payload)?,
            file_path,
        )),
        "git.commit" => sc::git_commit(path, require_string_key(payload, "message")?)
            .map(|oid| json!({ "oid": oid }))
            .map_err(git_conflict),
        "git.commitAmend" => sc::git_commit_amend(path, require_string_key(payload, "message")?)
            .map(|oid| json!({ "oid": oid }))
            .map_err(git_conflict),
        "git.fetch" => unit(sc::git_fetch(path)),
        "git.pull" => unit(sc::git_pull(path)),
        "git.push" => unit(sc::git_push(path)),
        "git.listStashes" => encode(sc::git_list_stashes(path)),
        "git.stash" => unit(sc::git_stash(path)),
        "git.stashPop" => unit(sc::git_stash_pop(
            path,
            optional_u32(payload, "stashIndex").ok_or_else(|| {
                HostError::format("Missing required field: stashIndex".to_string())
            })?,
        )),
        "git.listBranches" => encode(core_git::list_branches(&path)),
        "git.currentBranch" => encode(core_git::current_branch(&path)),
        "git.defaultBranch" => encode(core_git::default_branch(&path)),
        "git.createAndCheckoutBranch" => unit(core_git::create_and_checkout_branch_from(
            &path,
            &require_string_key(payload, "branch")?,
            optional_string_key(payload, "expectedHead").as_deref(),
            optional_string_key(payload, "expectedOid").as_deref(),
        )),
        "git.checkoutBranch" => unit(core_git::checkout_branch(
            &path,
            &require_string_key(payload, "branch")?,
        )),
        "git.branchExists" => encode(core_git::branch_exists(
            &path,
            &require_string_key(payload, "branch")?,
        )),
        "git.isValidBranchName" => encode(core_git::is_valid_branch_name(&require_string_key(
            payload, "name",
        )?)),
        "git.listRemotes" => encode(sc::list_remotes(&path)),
        "git.listWorktrees" => encode(core_git::list_worktrees(&path)),
        _ => Err(HostError::state(format!(
            "Unsupported workspace git operation: {request_type}"
        ))),
    }
}

fn encode<T: Serialize>(result: Result<T, GitError>) -> HostResult<Value> {
    let value = result.map_err(git_conflict)?;
    serde_json::to_value(value)
        .map_err(|error| HostError::state(format!("Git result encoding failed: {error}")))
}

fn unit(result: Result<(), GitError>) -> HostResult<Value> {
    result.map(|_| json!({})).map_err(git_conflict)
}

fn git_conflict(error: GitError) -> HostError {
    HostError::conflict(
        GIT_ERROR_CODE,
        error.context.clone(),
        json!({ "kind": error.kind, "context": error.context }),
    )
}

fn require_area(payload: &Value) -> HostResult<GitChangeArea> {
    optional_area(payload)?
        .ok_or_else(|| HostError::format("Missing required field: area".to_string()))
}

fn optional_area(payload: &Value) -> HostResult<Option<GitChangeArea>> {
    match optional_string_key(payload, "area").as_deref() {
        None => Ok(None),
        Some("untracked") => Ok(Some(GitChangeArea::Untracked)),
        Some("unstaged") => Ok(Some(GitChangeArea::Unstaged)),
        Some("staged") => Ok(Some(GitChangeArea::Staged)),
        Some(other) => Err(HostError::format(format!(
            "Unknown git change area: {other}"
        ))),
    }
}

fn optional_u32(payload: &Value, key: &str) -> Option<u32> {
    payload
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
}

/// The directory the verb runs in: the workspace root, or a directory inside
/// it when the client set a Source Control root. Separators are compared
/// component-wise so a Windows checkout accepts either slash.
fn git_path(workspace: &Workspace, payload: &Value) -> HostResult<String> {
    let Some(requested) = optional_string_key(payload, "path") else {
        return Ok(workspace.path.clone());
    };
    if path_is_within(&workspace.path, &requested) {
        return Ok(requested);
    }
    Err(HostError::state(format!(
        "Path {requested} is outside workspace {}",
        workspace.path
    )))
}

pub(super) fn path_is_within(root: &str, candidate: &str) -> bool {
    let root_components = normalized_components(root);
    let candidate_components = normalized_components(candidate);
    candidate_components.len() >= root_components.len()
        && root_components
            .iter()
            .zip(candidate_components.iter())
            .all(|(left, right)| left == right)
}

fn normalized_components(path: &str) -> Vec<String> {
    let unified = path.replace('\\', "/");
    let windows = unified.as_bytes().get(1).is_some_and(|byte| *byte == b':');
    Path::new(&unified)
        .components()
        .filter_map(|component| match component {
            Component::Normal(value) => Some(value.to_string_lossy().into_owned()),
            Component::Prefix(prefix) => Some(prefix.as_os_str().to_string_lossy().into_owned()),
            Component::RootDir => None,
            Component::CurDir | Component::ParentDir => None,
        })
        .map(|component| {
            if windows {
                component.to_ascii_lowercase()
            } else {
                component
            }
        })
        .collect()
}

#[cfg(test)]
#[path = "workspace_git_requests_tests.rs"]
mod tests;
