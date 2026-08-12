use git2::Repository;
use notify::{Event, EventKind};

use super::path_identities::PathIdentityCache;
use super::watcher::event_is_relevant;
use super::{TerminalPulseManager, WorkspacePulseWatcher};

#[cfg(unix)]
#[test]
fn canonical_workspace_root_keeps_symlinked_events_git_relative() {
    use std::os::unix::fs::symlink;

    let dir = tempfile::tempdir().unwrap();
    let target = dir.path().join("target");
    std::fs::create_dir(&target).unwrap();
    let repository = Repository::init(&target).unwrap();
    let link = dir.path().join("workspace-link");
    symlink(&target, &link).unwrap();
    let canonical_root = dunce::canonicalize(&link).unwrap();
    let file = canonical_root.join("new.txt");
    std::fs::write(&file, "new").unwrap();
    let event = Event::new(EventKind::Modify(notify::event::ModifyKind::Any)).add_path(file);

    assert!(event_is_relevant(&repository, &canonical_root, &event).unwrap());
}

#[test]
fn pathless_rescan_fails_closed_instead_of_using_existing_dirt() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join("new.txt"), "new").unwrap();
    let event = Event::new(EventKind::Other).set_flag(notify::event::Flag::Rescan);

    assert!(event_is_relevant(&repository, dir.path(), &event).is_err());
}

#[test]
fn git_index_errors_fail_closed() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(repository.path().join("index"), b"not a git index").unwrap();
    let event = Event::new(EventKind::Modify(notify::event::ModifyKind::Any))
        .add_path(dir.path().join("new.txt"));

    assert!(event_is_relevant(&repository, dir.path(), &event).is_err());
}

#[test]
fn initial_identity_scan_prunes_git_ignored_descendants() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join(".gitignore"), "generated/\n").unwrap();
    let generated = dir.path().join("generated");
    let nested = generated.join("deep");
    std::fs::create_dir_all(&nested).unwrap();

    let identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();

    assert!(identities.contains_directory(&generated));
    assert!(!identities.contains_directory(&nested));
    assert!(identities.watch_directories().contains(dir.path()));
    assert!(!identities.watch_directories().contains(&generated));
    assert!(!identities.watch_directories().contains(&nested));
}

#[test]
fn initial_watch_set_keeps_tracked_and_negated_paths_below_ignore_rules() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(
        dir.path().join(".gitignore"),
        "ignored/\ngenerated/*\n!generated/keep.txt\n",
    )
    .unwrap();
    let ignored = dir.path().join("ignored");
    let generated = dir.path().join("generated");
    std::fs::create_dir_all(&ignored).unwrap();
    std::fs::create_dir_all(&generated).unwrap();
    std::fs::write(ignored.join("tracked.txt"), "tracked").unwrap();
    let mut index = repository.index().unwrap();
    index
        .add_path(std::path::Path::new("ignored/tracked.txt"))
        .unwrap();
    index.write().unwrap();

    let identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();

    assert!(identities.watch_directories().contains(&ignored));
    assert!(identities.watch_directories().contains(&generated));
}

#[test]
fn newly_created_directories_are_added_to_the_watch_set() {
    let dir = tempfile::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        1,
        inbox,
    )
    .unwrap();

    let nested = dir.path().join("new/deep");
    std::fs::create_dir_all(&nested).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(150));
    std::fs::write(nested.join("new.txt"), "untracked").unwrap();

    assert_file_changed(&mut commands);
}

#[test]
fn files_written_before_directory_reconciliation_are_reported() {
    let dir = tempfile::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        1,
        inbox,
    )
    .unwrap();

    let nested = dir.path().join("new/deep");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::write(nested.join("new.txt"), "untracked").unwrap();

    assert_file_changed(&mut commands);
}

#[test]
fn git_index_changes_add_force_tracked_directories_to_the_watch_set() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join(".gitignore"), "ignored/\n").unwrap();
    let ignored = dir.path().join("ignored");
    std::fs::create_dir(&ignored).unwrap();
    let tracked = ignored.join("tracked.txt");
    std::fs::write(&tracked, "initial").unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        1,
        inbox,
    )
    .unwrap();

    let mut index = repository.index().unwrap();
    index
        .add_path(std::path::Path::new("ignored/tracked.txt"))
        .unwrap();
    index.write().unwrap();
    std::thread::sleep(std::time::Duration::from_millis(150));
    std::fs::write(&tracked, "changed").unwrap();

    assert_file_changed(&mut commands);
}

#[test]
fn repository_exclude_changes_add_newly_unignored_directories_to_the_watch_set() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(repository.commondir().join("info/exclude"), "ignored/\n").unwrap();
    let ignored = dir.path().join("ignored");
    std::fs::create_dir(&ignored).unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        1,
        inbox,
    )
    .unwrap();

    std::fs::write(repository.commondir().join("info/exclude"), "").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(150));
    std::fs::write(ignored.join("new.txt"), "untracked").unwrap();

    assert_file_changed(&mut commands);
}

#[test]
fn ancestor_ignore_changes_reconcile_subdirectory_workspaces() {
    let dir = tempfile::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join(".gitignore"), "workspace/ignored/\n").unwrap();
    let workspace = dir.path().join("workspace");
    let ignored = workspace.join("ignored");
    std::fs::create_dir_all(&ignored).unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher =
        WorkspacePulseWatcher::start_blocking("workspace-1".to_string(), workspace, 1, inbox)
            .unwrap();

    std::fs::write(dir.path().join(".gitignore"), "").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(150));
    std::fs::write(ignored.join("new.txt"), "untracked").unwrap();

    assert_file_changed(&mut commands);
}

#[test]
fn ambiguous_removal_below_ignored_directory_remains_relevant() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join(".gitignore"), "generated/\n").unwrap();
    let nested = dir.path().join("generated/deep");
    std::fs::create_dir_all(&nested).unwrap();
    let mut index = repository.index().unwrap();
    for name in ["one.txt", "two.txt"] {
        std::fs::write(nested.join(name), "tracked").unwrap();
        index
            .add_path(std::path::Path::new(&format!("generated/deep/{name}")))
            .unwrap();
    }
    index.write().unwrap();
    std::fs::remove_dir_all(&nested).unwrap();
    let event = Event::new(EventKind::Remove(notify::event::RemoveKind::Any)).add_path(nested);

    assert!(event_is_relevant(&repository, dir.path(), &event).unwrap());
}

#[test]
fn ambiguous_untracked_directory_removal_and_move_out_are_relevant() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join(".gitignore"), "ignored/\n").unwrap();

    for (name, kind) in [
        ("removed", EventKind::Remove(notify::event::RemoveKind::Any)),
        (
            "moved",
            EventKind::Modify(notify::event::ModifyKind::Name(
                notify::event::RenameMode::From,
            )),
        ),
        (
            "moved-macos",
            EventKind::Modify(notify::event::ModifyKind::Name(
                notify::event::RenameMode::Any,
            )),
        ),
    ] {
        let directory = dir.path().join(name);
        std::fs::create_dir(&directory).unwrap();
        std::fs::write(directory.join("new.txt"), "untracked").unwrap();
        let identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();
        std::fs::remove_dir_all(&directory).unwrap();
        let mut identities = identities;
        let event = Event::new(kind).add_path(directory.clone());
        assert!(super::watcher::event_is_relevant_with_identities(
            &repository,
            dir.path(),
            &event,
            &mut identities,
        )
        .unwrap());
        assert!(!identities.contains_directory(&directory));
    }

    let ignored = dir.path().join("ignored");
    std::fs::create_dir(&ignored).unwrap();
    std::fs::write(ignored.join("new.txt"), "ignored").unwrap();
    let mut identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();
    std::fs::remove_dir_all(&ignored).unwrap();
    let event = Event::new(EventKind::Remove(notify::event::RemoveKind::Any)).add_path(ignored);
    assert!(!super::watcher::event_is_relevant_with_identities(
        &repository,
        dir.path(),
        &event,
        &mut identities,
    )
    .unwrap());
}

#[test]
fn failed_watcher_generation_rejects_a_late_start_result() {
    let dir = tempfile::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let (inbox, _commands) = tokio::sync::mpsc::unbounded_channel();
    let mut manager = TerminalPulseManager::default();
    let generation = manager.reserve_watcher_start("workspace-1").unwrap();

    assert!(manager
        .fail_watcher_start("workspace-1", generation)
        .is_some());
    let watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        generation,
        inbox,
    )
    .unwrap();

    assert!(manager
        .finish_watcher_start("workspace-1", generation, watcher)
        .is_none());
}

fn assert_file_changed(
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<super::super::ServerCommand>,
) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    loop {
        if let Ok(command) = commands.try_recv() {
            assert!(matches!(
                command,
                super::super::ServerCommand::TerminalPulseFileChanged {
                    workspace_id,
                    watcher_generation: 1,
                    ..
                } if workspace_id == "workspace-1"
            ));
            return;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "watcher should report the qualifying file change"
        );
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}
