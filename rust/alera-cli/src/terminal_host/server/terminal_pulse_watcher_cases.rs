use git2::Repository;
use notify::{Event, EventKind};

use super::path_identities::PathIdentityCache;
use super::watcher::event_is_relevant;
use super::watcher::event_scope::{event_invalidates_workspace_root, retain_workspace_paths};
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

#[cfg(all(unix, not(target_os = "macos")))]
#[test]
fn path_identity_cache_keeps_distinct_native_unix_directories() {
    use std::ffi::OsString;
    use std::os::unix::ffi::OsStringExt;

    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let literal_backslash = dir.path().join("foo\\bar");
    let nested = dir.path().join("foo").join("bar");
    let non_utf8_one = dir.path().join(OsString::from_vec(vec![b'n', 0xff]));
    let non_utf8_two = dir.path().join(OsString::from_vec(vec![b'n', 0xfe]));
    for path in [&literal_backslash, &nested, &non_utf8_one, &non_utf8_two] {
        std::fs::create_dir_all(path).unwrap();
    }
    let mut identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();

    let backslash_removal = Event::new(EventKind::Remove(notify::event::RemoveKind::Folder))
        .add_path(literal_backslash.clone());
    identities.apply_event(&backslash_removal, &[]);
    assert!(!identities.contains_directory(&literal_backslash));
    assert!(identities.contains_directory(&nested));
    assert!(identities.contains_directory(&non_utf8_one));
    assert!(identities.contains_directory(&non_utf8_two));

    let non_utf8_removal = Event::new(EventKind::Remove(notify::event::RemoveKind::Folder))
        .add_path(non_utf8_one.clone());
    identities.apply_event(&non_utf8_removal, &[]);
    assert!(!identities.contains_directory(&non_utf8_one));
    assert!(identities.contains_directory(&non_utf8_two));
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
fn paired_rename_leaving_the_workspace_becomes_a_source_event() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let root = dir.path().join("workspace");
    let source = root.join("new-directory");
    let destination = dir.path().join("moved-out");
    std::fs::create_dir_all(&source).unwrap();
    std::fs::write(source.join("new.txt"), "untracked").unwrap();
    let mut identities = PathIdentityCache::scan(&root, &repository).unwrap();
    std::fs::rename(&source, &destination).unwrap();
    let mut event = Event::new(EventKind::Modify(notify::event::ModifyKind::Name(
        notify::event::RenameMode::Both,
    )))
    .add_path(source.clone())
    .add_path(destination);

    retain_workspace_paths(&root, &mut event);

    assert!(matches!(
        event.kind,
        EventKind::Modify(notify::event::ModifyKind::Name(
            notify::event::RenameMode::From
        ))
    ));
    assert_eq!(event.paths.as_slice(), std::slice::from_ref(&source));
    assert!(super::watcher::event_is_relevant_with_identities(
        &repository,
        &root,
        &event,
        &mut identities,
    )
    .unwrap());
    assert!(!identities.contains_directory(&source));
}

#[test]
fn paired_rename_into_an_ignored_directory_keeps_the_source_relevant() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    std::fs::write(dir.path().join(".gitignore"), "ignored/\n").unwrap();
    let source = dir.path().join("visible");
    let destination = dir.path().join("ignored");
    std::fs::create_dir(&source).unwrap();
    std::fs::write(source.join("new.txt"), "untracked").unwrap();
    let mut identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();
    std::fs::rename(&source, &destination).unwrap();
    let event = Event::new(EventKind::Modify(notify::event::ModifyKind::Name(
        notify::event::RenameMode::Both,
    )))
    .add_path(source.clone())
    .add_path(destination);

    assert!(super::watcher::event_is_relevant_with_identities(
        &repository,
        dir.path(),
        &event,
        &mut identities,
    )
    .unwrap());
    assert!(!identities.contains_directory(&source));
}

#[test]
fn workspace_root_removal_and_rename_invalidate_the_watcher() {
    let root = std::path::Path::new("workspace");
    for kind in [
        EventKind::Remove(notify::event::RemoveKind::Folder),
        EventKind::Modify(notify::event::ModifyKind::Name(
            notify::event::RenameMode::From,
        )),
        EventKind::Modify(notify::event::ModifyKind::Name(
            notify::event::RenameMode::Both,
        )),
    ] {
        assert!(event_invalidates_workspace_root(
            root,
            &Event::new(kind).add_path(root.to_path_buf()),
        ));
    }
    assert!(!event_invalidates_workspace_root(
        root,
        &Event::new(EventKind::Modify(notify::event::ModifyKind::Any)).add_path(root.to_path_buf()),
    ));
}

#[test]
fn source_events_reconcile_even_without_a_cached_directory_identity() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let identities = PathIdentityCache::scan(dir.path(), &repository).unwrap();
    let missing = dir.path().join("uncached/removed");

    for kind in [
        EventKind::Remove(notify::event::RemoveKind::Any),
        EventKind::Modify(notify::event::ModifyKind::Name(
            notify::event::RenameMode::From,
        )),
        EventKind::Modify(notify::event::ModifyKind::Name(
            notify::event::RenameMode::Any,
        )),
    ] {
        assert!(super::watcher::event_requires_watch_reconcile(
            &Event::new(kind).add_path(missing.clone()),
            &identities,
        ));
    }
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
fn ancestor_ignore_unignores_an_existing_subdirectory_workspace_file() {
    let dir = tempfile::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let gitignore = dir.path().join(".gitignore");
    std::fs::write(&gitignore, "workspace/visible.txt\n").unwrap();
    let workspace = dir.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    std::fs::write(workspace.join("visible.txt"), "existing").unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher =
        WorkspacePulseWatcher::start_blocking("workspace-1".to_string(), workspace, 1, inbox)
            .unwrap();

    std::fs::write(&gitignore, "").unwrap();

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
    let deadline = std::time::Instant::now()
        + std::time::Duration::from_secs(if cfg!(target_os = "macos") { 15 } else { 3 });
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
