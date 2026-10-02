use super::*;

#[test]
fn failed_watcher_generation_rejects_a_late_start_result() {
    let dir = super::super::tests::tempdir().unwrap();
    Repository::init(dir.path()).unwrap();
    let (inbox, _commands) = crate::terminal_host::ServerInbox::channel();
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
