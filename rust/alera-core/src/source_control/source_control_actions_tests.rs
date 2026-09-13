use super::*;
use crate::source_control::{GitChangeStatus, GitSubmoduleStatus};

fn entry(path: &str, area: GitChangeArea) -> GitChangeEntry {
    GitChangeEntry {
        path: path.to_string(),
        old_path: None,
        area,
        status: GitChangeStatus::Modified,
        added: None,
        removed: None,
        is_binary: false,
        is_large: false,
        submodule: None,
    }
}

fn submodule(
    area: GitChangeArea,
    commit_changed: bool,
    tracked_changes: bool,
    inspectable: bool,
) -> GitChangeEntry {
    GitChangeEntry {
        submodule: Some(GitSubmoduleStatus {
            commit_changed,
            tracked_changes,
            untracked_changes: false,
            inspectable,
        }),
        ..entry("vendor/lib", area)
    }
}

fn state(branch: &str, upstream: Option<&str>, ahead: u32, behind: u32) -> GitRepositoryState {
    GitRepositoryState {
        branch: branch.to_string(),
        upstream: upstream.map(ToString::to_string),
        ahead,
        behind,
        has_conflicts: false,
        head_message: Some("init".to_string()),
    }
}

#[test]
fn per_entry_rules_follow_the_desktop_panel() {
    let staged = entry("a", GitChangeArea::Staged);
    let unstaged = entry("b", GitChangeArea::Unstaged);
    let untracked = entry("c", GitChangeArea::Untracked);
    assert!(!can_stage_from_parent(&staged) && can_unstage_from_parent(&staged));
    assert!(!can_discard_from_parent(&staged));
    assert!(can_stage_from_parent(&unstaged) && can_discard_from_parent(&unstaged));
    assert!(can_stage_from_parent(&untracked) && can_discard_from_parent(&untracked));

    let worktree_only = submodule(GitChangeArea::Unstaged, false, true, true);
    assert!(!can_stage_from_parent(&worktree_only));
    assert!(!can_discard_from_parent(&worktree_only));

    let pointer_only = submodule(GitChangeArea::Unstaged, true, false, true);
    assert!(can_stage_from_parent(&pointer_only) && can_discard_from_parent(&pointer_only));

    let dirty_pointer = submodule(GitChangeArea::Unstaged, true, true, true);
    assert!(can_stage_from_parent(&dirty_pointer));
    assert!(!can_discard_from_parent(&dirty_pointer));

    let uninspectable = submodule(GitChangeArea::Unstaged, true, false, false);
    assert!(!can_discard_from_parent(&uninspectable));
}

#[test]
fn commit_actions_need_staged_changes_without_conflicts() {
    let entries = [entry("a", GitChangeArea::Staged)];
    let actions = source_control_actions(&entries, &state("main", Some("origin/main"), 0, 0), 0);
    assert!(actions.commit && actions.commit_push && actions.commit_sync && actions.amend);
    assert!(actions.unstage_all && actions.stash && !actions.stage_all);

    let mut conflicted = state("main", Some("origin/main"), 0, 0);
    conflicted.has_conflicts = true;
    let actions = source_control_actions(&entries, &conflicted, 0);
    assert!(!actions.commit && !actions.commit_push && !actions.amend);
    assert!(!actions.push && !actions.sync && actions.fetch && actions.pull);

    let actions = source_control_actions(&[], &state("main", Some("origin/main"), 0, 0), 0);
    assert!(!actions.commit && !actions.unstage_all && !actions.stash);
}

#[test]
fn amend_needs_a_head_commit_and_sync_needs_an_upstream() {
    let entries = [entry("a", GitChangeArea::Staged)];
    let mut unborn = state("main", None, 0, 0);
    unborn.head_message = None;
    let actions = source_control_actions(&entries, &unborn, 0);
    assert!(actions.commit && !actions.amend && !actions.commit_sync && !actions.sync);
    assert!(actions.publish_branch);

    let detached = source_control_actions(&entries, &state("HEAD", None, 0, 0), 0);
    assert!(!detached.publish_branch);
}

#[test]
fn stash_ignores_untracked_files_and_submodule_worktree_changes() {
    let base = state("main", Some("origin/main"), 0, 0);
    let untracked = [entry("c", GitChangeArea::Untracked)];
    let actions = source_control_actions(&untracked, &base, 2);
    assert!(!actions.stash && actions.stash_pop && actions.stage_all && actions.discard_all);

    let worktree_only = [submodule(GitChangeArea::Unstaged, false, true, true)];
    let actions = source_control_actions(&worktree_only, &base, 0);
    assert!(!actions.stash && !actions.stage_all && !actions.discard_all && !actions.stash_pop);
}

#[test]
fn primary_action_follows_the_desktop_order() {
    let unstaged = [entry("b", GitChangeArea::Unstaged)];
    let mut conflicted = state("main", None, 1, 1);
    conflicted.has_conflicts = true;
    let cases = [
        (conflicted, &unstaged[..], SourceControlPrimaryAction::Fetch),
        (
            state("main", None, 0, 0),
            &unstaged[..],
            SourceControlPrimaryAction::PublishBranch,
        ),
        (
            state("HEAD", None, 0, 0),
            &unstaged[..],
            SourceControlPrimaryAction::StageAll,
        ),
        (
            state("main", Some("origin/main"), 2, 1),
            &unstaged[..],
            SourceControlPrimaryAction::Sync,
        ),
        (
            state("main", Some("origin/main"), 0, 3),
            &unstaged[..],
            SourceControlPrimaryAction::Pull,
        ),
        (
            state("main", Some("origin/main"), 1, 0),
            &unstaged[..],
            SourceControlPrimaryAction::Push,
        ),
        (
            state("main", Some("origin/main"), 0, 0),
            &unstaged[..],
            SourceControlPrimaryAction::StageAll,
        ),
        (
            state("main", Some("origin/main"), 0, 0),
            &[][..],
            SourceControlPrimaryAction::Fetch,
        ),
    ];
    for (repository, entries, expected) in cases {
        assert_eq!(
            source_control_primary_action(entries, &repository),
            expected,
            "{}",
            expected.key()
        );
    }
}
