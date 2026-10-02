use super::*;

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
    let dir = tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let (inbox, _commands) = crate::terminal_host::ServerInbox::channel();
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
