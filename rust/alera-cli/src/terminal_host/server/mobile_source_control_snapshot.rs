//! The source control snapshot a phone renders: the desktop status model plus
//! the actions the runtime allows on it, so the phone never re-derives rules.

use alera_core::git::{GitError, GitErrorKind};
use alera_core::source_control::{
    self, can_discard_from_parent, can_stage_from_parent, can_unstage_from_parent,
    source_control_actions, source_control_primary_action, GitChangeArea, GitChangeEntry,
    GitChangeStatus,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn git_status_snapshot(root: &str) -> HostResult<Value> {
    let status = match source_control::git_status(root.to_string()) {
        Ok(status) => status,
        Err(error) if error.kind == GitErrorKind::NotARepository => {
            return Ok(json!({
                "isRepository": false,
                "branch": Value::Null,
                "entries": [],
                "writable": false,
            }));
        }
        Err(error) => return Err(git_host_error(error)),
    };
    let repository =
        source_control::git_repository_state(root.to_string()).map_err(git_host_error)?;
    let stashes = source_control::git_list_stashes(root.to_string()).map_err(git_host_error)?;
    let actions = source_control_actions(&status.entries, &repository, stashes.len());
    let primary = source_control_primary_action(&status.entries, &repository);
    Ok(json!({
        "isRepository": true,
        "branch": repository.branch,
        "entries": status.entries.iter().map(change_json).collect::<Vec<_>>(),
        "writable": true,
        "repository": {
            "upstream": repository.upstream,
            "ahead": repository.ahead,
            "behind": repository.behind,
            "hasConflicts": repository.has_conflicts,
            "headMessage": repository.head_message,
            "detached": repository.branch == "HEAD",
        },
        "stashes": stashes
            .iter()
            .map(|stash| json!({ "index": stash.index, "message": stash.message }))
            .collect::<Vec<_>>(),
        "actions": {
            "commit": actions.commit,
            "commitPush": actions.commit_push,
            "commitSync": actions.commit_sync,
            "amend": actions.amend,
            "stageAll": actions.stage_all,
            "unstageAll": actions.unstage_all,
            "discardAll": actions.discard_all,
            "fetch": actions.fetch,
            "pull": actions.pull,
            "push": actions.push,
            "sync": actions.sync,
            "publishBranch": actions.publish_branch,
            "stash": actions.stash,
            "stashPop": actions.stash_pop,
        },
        "primaryAction": primary.key(),
    }))
}

fn change_json(entry: &GitChangeEntry) -> Value {
    json!({
        "path": entry.path,
        "oldPath": entry.old_path,
        "area": area_key(entry.area),
        "status": status_key(entry.status),
        "added": entry.added,
        "removed": entry.removed,
        "isBinary": entry.is_binary,
        "isSubmodule": entry.submodule.is_some(),
        "canStage": can_stage_from_parent(entry),
        "canUnstage": can_unstage_from_parent(entry),
        "canDiscard": can_discard_from_parent(entry),
    })
}

pub(super) fn area_key(area: GitChangeArea) -> &'static str {
    match area {
        GitChangeArea::Staged => "staged",
        GitChangeArea::Unstaged => "unstaged",
        GitChangeArea::Untracked => "untracked",
    }
}

pub(super) fn parse_area(value: &str) -> HostResult<GitChangeArea> {
    match value {
        "staged" => Ok(GitChangeArea::Staged),
        "unstaged" => Ok(GitChangeArea::Unstaged),
        "untracked" => Ok(GitChangeArea::Untracked),
        _ => Err(HostError::format(format!("Unknown change area: {value}"))),
    }
}

fn status_key(status: GitChangeStatus) -> &'static str {
    match status {
        GitChangeStatus::Modified => "modified",
        GitChangeStatus::Added => "added",
        GitChangeStatus::Deleted => "deleted",
        GitChangeStatus::Renamed => "renamed",
        GitChangeStatus::Copied => "copied",
        GitChangeStatus::Untracked => "untracked",
    }
}

/// Carries the kind as an additive `errorCode` and words the message the way
/// the desktop panel does, so an older phone that only shows `error` still
/// reads the same sentence.
pub(super) fn git_host_error(error: GitError) -> HostError {
    let code = format!("git{:?}", error.kind);
    let message = git_error_message(&error);
    HostError::conflict(code, message, json!({ "context": error.context }))
}

fn git_error_message(error: &GitError) -> String {
    let context = error.context.trim();
    match error.kind {
        GitErrorKind::NotARepository => "This workspace is not a Git repository.".to_string(),
        GitErrorKind::DetachedHead => "Cannot push from detached HEAD.".to_string(),
        GitErrorKind::BranchAlreadyExists => {
            format!("A branch named \"{context}\" already exists.")
        }
        GitErrorKind::BranchNotFound => format!("Branch \"{context}\" was not found."),
        GitErrorKind::InvalidBranchName => "Enter a valid branch name.".to_string(),
        GitErrorKind::RemoteNotFound => "Remote origin was not found.".to_string(),
        GitErrorKind::NothingToCommit => "Nothing to commit.".to_string(),
        GitErrorKind::Conflict if context.is_empty() => {
            "Resolve conflicts before continuing.".to_string()
        }
        _ if context.is_empty() => "Git operation failed.".to_string(),
        _ => context.to_string(),
    }
}

#[cfg(test)]
#[path = "mobile_source_control_snapshot_tests.rs"]
pub(super) mod tests;
