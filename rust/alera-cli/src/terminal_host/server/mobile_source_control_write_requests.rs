//! Source control writes a paired phone can run on a workspace. Every verb
//! answers with a fresh status snapshot so the phone updates in one round trip.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use alera_core::git::{self as core_git, GitError, GitErrorKind};
use alera_core::runtime::{RuntimeStore, LOCAL_HOST_ID};
use alera_core::source_control::{self, GitChangeArea};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_source_control_snapshot::{git_host_error, git_status_snapshot, parse_area};
use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::{optional_string_key, require_string_key};

/// Every write verb, for the gateway allowlist test.
#[cfg(test)]
pub(super) const MOBILE_GIT_WRITE_REQUESTS: &[&str] = &[
    "mobile.git.stage",
    "mobile.git.unstage",
    "mobile.git.discard",
    "mobile.git.commit",
    "mobile.git.fetch",
    "mobile.git.pull",
    "mobile.git.push",
    "mobile.git.sync",
    "mobile.git.stash",
    "mobile.git.stashPop",
    "mobile.git.checkout",
    "mobile.git.createBranch",
];

#[derive(Debug, PartialEq)]
enum GitWrite {
    Stage(Selection),
    Unstage(Selection),
    Discard(Selection),
    Commit {
        message: String,
        amend: bool,
        then: Option<AfterCommit>,
    },
    Fetch,
    Pull,
    Push,
    Sync,
    Stash,
    StashPop(u32),
    Checkout(String),
    CreateBranch(String),
}

#[derive(Debug, PartialEq)]
struct Selection {
    path: Option<String>,
    area: Option<GitChangeArea>,
}

#[derive(Debug, PartialEq)]
enum AfterCommit {
    Push,
    Sync,
}

pub(super) async fn handle_mobile_git_request(
    runtime_store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    match request_type {
        "mobile.git.status" => {
            super::mobile_source_control_requests::mobile_git_status(runtime_store, payload).await
        }
        "mobile.git.diff" => {
            super::mobile_source_control_requests::mobile_git_diff(runtime_store, payload).await
        }
        "mobile.git.branches" => mobile_git_branches(runtime_store, payload).await,
        _ => mobile_git_write(runtime_store, request_type, payload).await,
    }
}

async fn mobile_git_write(
    runtime_store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    let operation = parse_write(request_type, payload)?;
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "Source control changes are only available for workspaces on this runtime.",
        ));
    }
    let guard = WorkspaceWriteGuard::acquire(&workspace.id)?;
    let root = workspace.path.clone();
    spawn_blocking_workspace("Source control", move || {
        let _guard = guard;
        let commit_oid = run_write(&root, operation).map_err(git_host_error)?;
        let mut snapshot = git_status_snapshot(&root)?;
        if let Some(oid) = commit_oid {
            snapshot["commitOid"] = json!(oid);
        }
        Ok(snapshot)
    })
    .await
}

async fn mobile_git_branches(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let root = workspace.path.clone();
    spawn_blocking_workspace("Git branches", move || {
        let branches = core_git::list_branches(&root).map_err(git_host_error)?;
        let local = branches
            .iter()
            .filter(|branch| core_git::branch_exists(&root, branch).unwrap_or(false))
            .cloned()
            .collect::<Vec<_>>();
        let current = source_control::git_repository_state(root.clone())
            .map_err(git_host_error)?
            .branch;
        Ok(json!({
            "branches": branches,
            "localBranches": local,
            "current": current,
        }))
    })
    .await
}

fn parse_write(request_type: &str, payload: &Value) -> HostResult<GitWrite> {
    let selection = || -> HostResult<Selection> {
        Ok(Selection {
            path: optional_string_key(payload, "path"),
            area: optional_string_key(payload, "area")
                .map(|area| parse_area(&area))
                .transpose()?,
        })
    };
    Ok(match request_type {
        "mobile.git.stage" => GitWrite::Stage(selection()?),
        "mobile.git.unstage" => GitWrite::Unstage(selection()?),
        "mobile.git.discard" => GitWrite::Discard(selection()?),
        "mobile.git.commit" => GitWrite::Commit {
            message: require_string_key(payload, "message")?,
            amend: payload
                .get("amend")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            then: match optional_string_key(payload, "then").as_deref() {
                None => None,
                Some("push") => Some(AfterCommit::Push),
                Some("sync") => Some(AfterCommit::Sync),
                Some(other) => {
                    return Err(HostError::format(format!(
                        "Unknown follow-up after commit: {other}"
                    )))
                }
            },
        },
        "mobile.git.fetch" => GitWrite::Fetch,
        "mobile.git.pull" => GitWrite::Pull,
        "mobile.git.push" => GitWrite::Push,
        "mobile.git.sync" => GitWrite::Sync,
        "mobile.git.stash" => GitWrite::Stash,
        "mobile.git.stashPop" => GitWrite::StashPop(
            payload
                .get("stashIndex")
                .and_then(Value::as_u64)
                .and_then(|index| u32::try_from(index).ok())
                .ok_or_else(|| HostError::format("stashIndex is required."))?,
        ),
        "mobile.git.checkout" => GitWrite::Checkout(require_string_key(payload, "branch")?),
        "mobile.git.createBranch" => {
            GitWrite::CreateBranch(require_string_key(payload, "branch")?.trim().to_string())
        }
        _ => {
            return Err(HostError::state(
                "Unsupported mobile source control operation.",
            ))
        }
    })
}

/// Runs one write and returns the new commit id when it made one. Composite
/// verbs are sequential like desktop's: a failed push keeps the commit.
fn run_write(root: &str, operation: GitWrite) -> Result<Option<String>, GitError> {
    let root_string = || root.to_string();
    match operation {
        GitWrite::Stage(selection) => match selection.area {
            Some(area) => source_control::git_stage_area(root_string(), area, selection.path),
            None => source_control::git_stage(root_string(), selection.path),
        }
        .map(|_| None),
        GitWrite::Unstage(selection) => match selection.area {
            Some(area) => source_control::git_unstage_area(root_string(), area, selection.path),
            None => source_control::git_unstage(root_string(), selection.path),
        }
        .map(|_| None),
        GitWrite::Discard(selection) => match selection.area {
            Some(area) => source_control::git_discard_area(root_string(), area, selection.path),
            None => source_control::git_discard(root_string(), selection.path),
        }
        .map(|_| None),
        GitWrite::Commit {
            message,
            amend,
            then,
        } => {
            let oid = if amend {
                source_control::git_commit_amend(root_string(), message)?
            } else {
                source_control::git_commit(root_string(), message)?
            };
            match then {
                Some(AfterCommit::Push) => source_control::git_push(root_string())?,
                Some(AfterCommit::Sync) => sync(root)?,
                None => {}
            }
            Ok(Some(oid))
        }
        GitWrite::Fetch => source_control::git_fetch(root_string()).map(|_| None),
        GitWrite::Pull => source_control::git_pull(root_string()).map(|_| None),
        GitWrite::Push => source_control::git_push(root_string()).map(|_| None),
        GitWrite::Sync => sync(root).map(|_| None),
        GitWrite::Stash => source_control::git_stash(root_string()).map(|_| None),
        GitWrite::StashPop(index) => {
            source_control::git_stash_pop(root_string(), index).map(|_| None)
        }
        GitWrite::Checkout(branch) => core_git::checkout_branch(root, &branch).map(|_| None),
        GitWrite::CreateBranch(branch) => {
            core_git::create_and_checkout_branch(root, &branch).map(|_| None)
        }
    }
}

fn sync(root: &str) -> Result<(), GitError> {
    let state = source_control::git_repository_state(root.to_string())?;
    if state.upstream.as_deref().is_none_or(str::is_empty) {
        return Err(GitError::new(
            GitErrorKind::NoUpstream,
            "Publish this branch before syncing.",
        ));
    }
    source_control::git_pull(root.to_string())?;
    source_control::git_push(root.to_string())
}

/// One write per workspace at a time. Two phones, or a retry racing its first
/// attempt, would otherwise interleave index writes and fail on `index.lock`
/// with an error that says nothing about the other request.
struct WorkspaceWriteGuard {
    workspace_id: String,
}

impl WorkspaceWriteGuard {
    fn acquire(workspace_id: &str) -> HostResult<Self> {
        let mut active = active_writes().lock().unwrap_or_else(|e| e.into_inner());
        if !active.insert(workspace_id.to_string()) {
            return Err(HostError::conflict(
                "sourceControlBusy",
                "Another source control action is still running in this workspace.",
                json!({}),
            ));
        }
        Ok(Self {
            workspace_id: workspace_id.to_string(),
        })
    }
}

impl Drop for WorkspaceWriteGuard {
    fn drop(&mut self) {
        active_writes()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&self.workspace_id);
    }
}

fn active_writes() -> &'static Mutex<HashSet<String>> {
    static ACTIVE: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    ACTIVE.get_or_init(|| Mutex::new(HashSet::new()))
}

#[cfg(test)]
#[path = "mobile_source_control_write_requests_tests.rs"]
mod tests;
