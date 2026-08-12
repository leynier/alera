use std::fs;
use std::path::Path;

use git2::Repository;
use notify::event::{CreateKind, ModifyKind, RenameMode};
use notify::{Event, EventKind};

use super::*;

#[test]
fn tracked_and_untracked_events_are_relevant_but_ignored_files_are_not() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join("tracked.txt"), "one").unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(Path::new("tracked.txt")).unwrap();
    index.write().unwrap();
    fs::write(dir.path().join(".gitignore"), "ignored.txt\n").unwrap();
    fs::write(dir.path().join("new.txt"), "new").unwrap();
    fs::write(dir.path().join("ignored.txt"), "ignored").unwrap();

    let event =
        |path: &str| Event::new(EventKind::Modify(ModifyKind::Any)).add_path(dir.path().join(path));
    assert!(event_is_relevant(&repository, dir.path(), &event("tracked.txt")).unwrap());
    assert!(event_is_relevant(&repository, dir.path(), &event("new.txt")).unwrap());
    assert!(!event_is_relevant(&repository, dir.path(), &event("ignored.txt")).unwrap());
    assert!(!event_is_relevant(
        &repository,
        dir.path(),
        &Event::new(EventKind::Create(CreateKind::Any)).add_path(dir.path().join(".git/index")),
    )
    .unwrap());
}

#[test]
fn tracked_files_remain_relevant_inside_an_ignored_directory() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "generated/\n").unwrap();
    let generated = dir.path().join("generated");
    fs::create_dir(&generated).unwrap();
    let tracked = generated.join("tracked.txt");
    fs::write(&tracked, "tracked").unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(Path::new("generated/tracked.txt")).unwrap();
    index.write().unwrap();

    let event = Event::new(EventKind::Modify(ModifyKind::Any)).add_path(tracked);
    assert!(event_is_relevant(&repository, dir.path(), &event).unwrap());
}

#[cfg(unix)]
#[test]
fn non_utf8_tracked_descendants_keep_ignored_directory_removals_relevant() {
    use std::os::unix::ffi::OsStringExt;

    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "generated/\n").unwrap();
    let generated = dir.path().join("generated");
    fs::create_dir(&generated).unwrap();
    let tracked = generated.join(std::ffi::OsString::from_vec(vec![b'f', 0xff]));
    fs::write(&tracked, "tracked").unwrap();
    let relative = tracked.strip_prefix(dir.path()).unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(relative).unwrap();
    index.write().unwrap();
    fs::remove_dir_all(&generated).unwrap();

    let event =
        Event::new(EventKind::Remove(notify::event::RemoveKind::Folder)).add_path(generated);

    assert!(event_is_relevant(&repository, dir.path(), &event).unwrap());
}

#[cfg(unix)]
#[test]
fn native_unix_directory_names_keep_populated_create_events_relevant() {
    use std::os::unix::ffi::OsStringExt;

    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let names = [
        std::ffi::OsString::from_vec(vec![b'd', 0xff]),
        std::ffi::OsString::from("literal\\slash"),
    ];

    for name in names {
        let directory = dir.path().join(name);
        fs::create_dir(&directory).unwrap();
        fs::write(directory.join("new.txt"), "untracked").unwrap();
        let event = Event::new(EventKind::Create(CreateKind::Folder)).add_path(directory);

        assert!(event_is_relevant(&repository, dir.path(), &event).unwrap());
    }
}

#[test]
fn empty_directories_are_not_git_relevant() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let empty = dir.path().join("empty");
    fs::create_dir(&empty).unwrap();

    assert!(!event_is_relevant(
        &repository,
        dir.path(),
        &Event::new(EventKind::Create(CreateKind::Folder)).add_path(empty),
    )
    .unwrap());
}

#[test]
fn files_inside_new_directories_remain_git_relevant() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let nested = dir.path().join("new-directory");
    fs::create_dir(&nested).unwrap();
    let file = nested.join("new.txt");
    fs::write(&file, "new").unwrap();

    assert!(event_is_relevant(
        &repository,
        dir.path(),
        &Event::new(EventKind::Create(CreateKind::File)).add_path(file),
    )
    .unwrap());
}

#[test]
fn removed_untracked_directories_are_relevant_unless_ignored() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "ignored-directory/\n").unwrap();

    let removed = |path: &str| {
        Event::new(EventKind::Remove(notify::event::RemoveKind::Folder))
            .add_path(dir.path().join(path))
    };
    assert!(event_is_relevant(&repository, dir.path(), &removed("deleted-directory"),).unwrap());
    assert!(!event_is_relevant(&repository, dir.path(), &removed("ignored-directory"),).unwrap());
}

#[test]
fn git_subdirectory_workspace_uses_paths_relative_to_the_repository() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let workspace = dir.path().join("nested");
    fs::create_dir_all(&workspace).unwrap();
    fs::write(workspace.join("tracked.txt"), "one").unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(Path::new("nested/tracked.txt")).unwrap();
    index.write().unwrap();
    fs::write(workspace.join("new.txt"), "new").unwrap();
    fs::write(dir.path().join("sibling.txt"), "outside").unwrap();

    let event =
        |path: &Path| Event::new(EventKind::Modify(ModifyKind::Any)).add_path(path.to_path_buf());
    assert!(event_is_relevant(
        &repository,
        &workspace,
        &event(&workspace.join("tracked.txt")),
    )
    .unwrap());
    assert!(
        event_is_relevant(&repository, &workspace, &event(&workspace.join("new.txt")),).unwrap()
    );
    assert!(!event_is_relevant(
        &repository,
        &workspace,
        &event(&dir.path().join("sibling.txt")),
    )
    .unwrap());
}

#[test]
fn deleted_untracked_events_remain_relevant_unless_git_ignores_the_path() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "ignored.txt\n").unwrap();
    let deleted = dir.path().join("deleted.txt");
    let ignored = dir.path().join("ignored.txt");
    fs::write(&deleted, "new").unwrap();
    fs::write(&ignored, "ignored").unwrap();
    fs::remove_file(&deleted).unwrap();
    fs::remove_file(&ignored).unwrap();

    let remove_event = |path: &Path| {
        Event::new(EventKind::Remove(notify::event::RemoveKind::File)).add_path(path.to_path_buf())
    };
    assert!(event_is_relevant(&repository, dir.path(), &remove_event(&deleted),).unwrap());
    assert!(!event_is_relevant(&repository, dir.path(), &remove_event(&ignored),).unwrap());
}

#[test]
fn deleted_file_is_not_hidden_by_a_directory_only_ignore_rule() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "artifact/\n").unwrap();
    let deleted = dir.path().join("artifact");
    fs::write(&deleted, "new").unwrap();
    fs::remove_file(&deleted).unwrap();

    for kind in [
        EventKind::Remove(notify::event::RemoveKind::File),
        EventKind::Remove(notify::event::RemoveKind::Any),
    ] {
        let event = Event::new(kind).add_path(deleted.clone());
        assert!(event_is_relevant(&repository, dir.path(), &event).unwrap());
    }
}

#[test]
fn deleted_directory_respects_a_directory_only_ignore_rule() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "artifact/\n").unwrap();

    let event = Event::new(EventKind::Remove(notify::event::RemoveKind::Folder))
        .add_path(dir.path().join("artifact"));
    assert!(!event_is_relevant(&repository, dir.path(), &event).unwrap());
}

#[test]
fn ambiguous_removal_preserves_cached_file_and_directory_identity() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "artifact/\n").unwrap();

    let artifact = dir.path().join("artifact");
    fs::write(&artifact, "new").unwrap();
    let mut file_identities =
        path_identities::PathIdentityCache::scan(dir.path(), &repository).unwrap();
    fs::remove_file(&artifact).unwrap();
    let file_event =
        Event::new(EventKind::Remove(notify::event::RemoveKind::Any)).add_path(artifact.clone());
    assert!(watcher::event_is_relevant_with_identities(
        &repository,
        dir.path(),
        &file_event,
        &mut file_identities,
    )
    .unwrap());

    fs::create_dir(&artifact).unwrap();
    let mut directory_identities =
        path_identities::PathIdentityCache::scan(dir.path(), &repository).unwrap();
    fs::remove_dir(&artifact).unwrap();
    let directory_event =
        Event::new(EventKind::Remove(notify::event::RemoveKind::Any)).add_path(artifact);
    assert!(!watcher::event_is_relevant_with_identities(
        &repository,
        dir.path(),
        &directory_event,
        &mut directory_identities,
    )
    .unwrap());
}

#[test]
fn rename_from_preserves_cached_file_and_directory_identity() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "artifact/\n").unwrap();
    let artifact = dir.path().join("artifact");
    let moved = dir.path().join("moved");

    fs::write(&artifact, "new").unwrap();
    let mut file_identities =
        path_identities::PathIdentityCache::scan(dir.path(), &repository).unwrap();
    fs::rename(&artifact, &moved).unwrap();
    let file_event = Event::new(EventKind::Modify(ModifyKind::Name(RenameMode::From)))
        .add_path(artifact.clone());
    assert!(watcher::event_is_relevant_with_identities(
        &repository,
        dir.path(),
        &file_event,
        &mut file_identities,
    )
    .unwrap());
    fs::remove_file(&moved).unwrap();

    fs::create_dir(&artifact).unwrap();
    let mut directory_identities =
        path_identities::PathIdentityCache::scan(dir.path(), &repository).unwrap();
    fs::rename(&artifact, &moved).unwrap();
    let directory_event =
        Event::new(EventKind::Modify(ModifyKind::Name(RenameMode::From))).add_path(artifact);
    assert!(!watcher::event_is_relevant_with_identities(
        &repository,
        dir.path(),
        &directory_event,
        &mut directory_identities,
    )
    .unwrap());
}

#[test]
fn ignored_churn_stays_irrelevant_without_a_workspace_status_scan() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "generated/\n").unwrap();
    let generated = dir.path().join("generated");
    fs::create_dir(&generated).unwrap();

    for index in 0..4_097 {
        let path = generated.join(format!("output-{index}.txt"));
        fs::write(&path, "ignored").unwrap();
        let event = Event::new(EventKind::Create(CreateKind::File)).add_path(path);
        assert!(!event_is_relevant(&repository, dir.path(), &event).unwrap());
    }
}

#[test]
fn stale_due_tokens_cannot_collide_after_reconfigure_or_rearm() {
    let mut manager = TerminalPulseManager::default();
    manager.arm(
        "session-1".to_string(),
        "workspace-1".to_string(),
        7,
        TerminalPulseConfiguration::default(),
    );
    let old_due = manager.schedule("workspace-1", 1).remove(0);
    let old_write = manager
        .due_write("session-1", 7, old_due.generation)
        .unwrap();

    let replacement = TerminalPulseConfiguration {
        command: "R".to_string(),
        ..TerminalPulseConfiguration::default()
    };
    manager.arm(
        "session-1".to_string(),
        "workspace-1".to_string(),
        7,
        replacement.clone(),
    );
    assert!(!old_write.active.load(Ordering::Acquire));
    let replacement_due = manager.schedule("workspace-1", 2).remove(0);
    assert_ne!(old_due.generation, replacement_due.generation);
    assert_eq!(manager.due_bytes("session-1", 7, old_due.generation), None);
    assert_eq!(
        manager.due_bytes("session-1", 7, replacement_due.generation),
        Some(b"R\r".to_vec())
    );

    let replacement_write = manager
        .due_write("session-1", 7, replacement_due.generation)
        .unwrap();
    assert!(manager.disarm("session-1").is_some());
    assert!(!replacement_write.active.load(Ordering::Acquire));
    manager.arm(
        "session-1".to_string(),
        "workspace-1".to_string(),
        7,
        replacement,
    );
    let rearmed_due = manager.schedule("workspace-1", 3).remove(0);
    assert_ne!(replacement_due.generation, rearmed_due.generation);
}

#[test]
fn watcher_failure_disarms_every_rule_in_the_workspace() {
    let mut manager = TerminalPulseManager::default();
    for session_id in ["session-1", "session-2"] {
        manager.arm(
            session_id.to_string(),
            "workspace-1".to_string(),
            7,
            TerminalPulseConfiguration::default(),
        );
    }
    manager.arm(
        "session-3".to_string(),
        "workspace-2".to_string(),
        8,
        TerminalPulseConfiguration::default(),
    );
    let stale_due = manager.schedule("workspace-1", 1).remove(0);

    let mut failed = manager.fail_workspace("workspace-1");
    failed.sort_by(|left, right| left.session_id.cmp(&right.session_id));
    assert_eq!(
        failed
            .iter()
            .map(|change| change.session_id.as_str())
            .collect::<Vec<_>>(),
        ["session-1", "session-2"],
    );
    assert!(manager.schedule("workspace-1", 2).is_empty());
    assert_eq!(
        manager.due_bytes(
            &stale_due.session_id,
            stale_due.session_instance_id,
            stale_due.generation,
        ),
        None,
    );
    assert!(manager.is_armed("session-3", 8));
}

#[test]
fn retrying_a_due_pulse_invalidates_the_rejected_timer() {
    let mut manager = TerminalPulseManager::default();
    manager.arm(
        "session-1".to_string(),
        "workspace-1".to_string(),
        7,
        TerminalPulseConfiguration::default(),
    );
    let due = manager.schedule("workspace-1", 1).remove(0);

    let retry_generation = manager
        .retry_due(&due.session_id, due.session_instance_id, due.generation)
        .unwrap();
    assert_ne!(retry_generation, due.generation);
    assert_eq!(
        manager.due_bytes(&due.session_id, due.session_instance_id, due.generation,),
        None,
    );
    assert_eq!(
        manager.due_bytes(&due.session_id, due.session_instance_id, retry_generation),
        Some(b"r\r".to_vec()),
    );
    manager.complete_due(&due.session_id, due.session_instance_id, retry_generation);
    assert_eq!(
        manager.due_bytes(&due.session_id, due.session_instance_id, retry_generation),
        None,
    );
}

#[test]
fn configuration_rejects_empty_input_and_out_of_range_delays() {
    let mut configuration = TerminalPulseConfiguration::default();
    configuration.command.clear();
    assert!(configuration.validate().is_err());
    configuration.command = "r".to_string();
    configuration.delay_ms = MIN_DELAY_MS - 1;
    assert!(configuration.validate().is_err());
}

#[test]
fn watcher_start_is_reserved_once_and_rejects_previous_generations() {
    let dir = tempfile::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let (inbox, _commands) = tokio::sync::mpsc::unbounded_channel();
    let mut manager = TerminalPulseManager::default();

    let previous = manager.reserve_watcher_start("workspace-1").unwrap();
    assert_eq!(manager.reserve_watcher_start("workspace-1"), None);
    let watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        previous,
        inbox.clone(),
    )
    .unwrap();
    assert!(manager
        .finish_watcher_start("workspace-1", previous, watcher)
        .is_some());
    manager.watchers.remove("workspace-1");
    let current = manager.reserve_watcher_start("workspace-1").unwrap();
    let watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        dir.path().to_path_buf(),
        current,
        inbox,
    )
    .unwrap();
    assert!(manager
        .finish_watcher_start("workspace-1", current, watcher)
        .is_some());

    assert_ne!(previous, current);
    assert!(!manager.accepts_watcher_command("workspace-1", previous));
    assert!(manager.accepts_watcher_command("workspace-1", current));
}
