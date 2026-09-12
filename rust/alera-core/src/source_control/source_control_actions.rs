//! Which source control actions a workspace allows, computed once on the host
//! so a remote client renders the same rules as the desktop panel
//! (`WorkspaceSourceControlState`, `GitChangeEntry` and the panel toolbar).

use super::{GitChangeArea, GitChangeEntry, GitRepositoryState};

/// The action a one-tap control should run, ignoring Commit: whether Commit
/// wins depends on the message the client is typing, which the host never sees.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourceControlPrimaryAction {
    Fetch,
    PublishBranch,
    Sync,
    Pull,
    Push,
    StageAll,
}

impl SourceControlPrimaryAction {
    pub fn key(self) -> &'static str {
        match self {
            Self::Fetch => "fetch",
            Self::PublishBranch => "publishBranch",
            Self::Sync => "sync",
            Self::Pull => "pull",
            Self::Push => "push",
            Self::StageAll => "stageAll",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourceControlActions {
    pub commit: bool,
    pub commit_push: bool,
    pub commit_sync: bool,
    pub amend: bool,
    pub stage_all: bool,
    pub unstage_all: bool,
    pub discard_all: bool,
    pub fetch: bool,
    pub pull: bool,
    pub push: bool,
    pub sync: bool,
    pub publish_branch: bool,
    pub stash: bool,
    pub stash_pop: bool,
}

pub fn is_submodule_worktree_only(entry: &GitChangeEntry) -> bool {
    entry.area == GitChangeArea::Unstaged
        && entry
            .submodule
            .as_ref()
            .is_some_and(|status| !status.commit_changed)
}

pub fn can_stage_from_parent(entry: &GitChangeEntry) -> bool {
    entry.area != GitChangeArea::Staged && !is_submodule_worktree_only(entry)
}

pub fn can_unstage_from_parent(entry: &GitChangeEntry) -> bool {
    entry.area == GitChangeArea::Staged
}

pub fn can_discard_from_parent(entry: &GitChangeEntry) -> bool {
    entry.area != GitChangeArea::Staged
        && !is_submodule_worktree_only(entry)
        && entry.submodule.as_ref().is_none_or(|status| {
            status.inspectable && !status.tracked_changes && !status.untracked_changes
        })
}

pub fn source_control_actions(
    entries: &[GitChangeEntry],
    state: &GitRepositoryState,
    stash_count: usize,
) -> SourceControlActions {
    let has_staged = entries
        .iter()
        .any(|entry| entry.area == GitChangeArea::Staged);
    let has_conflicts = state.has_conflicts;
    let has_upstream = has_upstream(state);
    let can_commit = has_staged && !has_conflicts;
    SourceControlActions {
        commit: can_commit,
        commit_push: can_commit,
        commit_sync: can_commit && has_upstream,
        amend: can_commit && state.head_message.is_some(),
        stage_all: entries.iter().any(can_stage_from_parent),
        unstage_all: has_staged,
        discard_all: entries.iter().any(can_discard_from_parent),
        fetch: true,
        pull: true,
        push: !has_conflicts,
        sync: !has_conflicts && has_upstream,
        publish_branch: !has_upstream && state.branch != "HEAD",
        stash: entries.iter().any(|entry| {
            entry.area == GitChangeArea::Staged
                || (entry.area == GitChangeArea::Unstaged && !is_submodule_worktree_only(entry))
        }),
        stash_pop: stash_count > 0,
    }
}

pub fn source_control_primary_action(
    entries: &[GitChangeEntry],
    state: &GitRepositoryState,
) -> SourceControlPrimaryAction {
    let has_upstream = has_upstream(state);
    if state.has_conflicts {
        SourceControlPrimaryAction::Fetch
    } else if !has_upstream && state.branch != "HEAD" {
        SourceControlPrimaryAction::PublishBranch
    } else if has_upstream && state.ahead > 0 && state.behind > 0 {
        SourceControlPrimaryAction::Sync
    } else if has_upstream && state.behind > 0 {
        SourceControlPrimaryAction::Pull
    } else if has_upstream && state.ahead > 0 {
        SourceControlPrimaryAction::Push
    } else if entries.iter().any(can_stage_from_parent) {
        SourceControlPrimaryAction::StageAll
    } else {
        SourceControlPrimaryAction::Fetch
    }
}

fn has_upstream(state: &GitRepositoryState) -> bool {
    state
        .upstream
        .as_deref()
        .is_some_and(|upstream| !upstream.is_empty())
}

#[cfg(test)]
#[path = "source_control_actions_tests.rs"]
mod tests;
