use std::time::Instant;

use super::*;

#[test]
fn watcher_does_not_follow_workspace_symlinks() {
    assert!(!watcher_config().follow_symlinks());
}

#[test]
fn dropping_a_watcher_does_not_wait_for_its_worker() {
    let (release_tx, release_rx) = mpsc::channel();
    let worker = thread::spawn(move || {
        let _ = release_rx.recv();
    });
    let (wake_tx, _wake_rx) = mpsc::sync_channel(1);
    let watcher = WorkspacePulseWatcher {
        generation: 1,
        worker: Some(worker),
        wake_tx,
        cancelled: Arc::new(AtomicBool::new(false)),
        event_sequence: Arc::new(AtomicU64::new(0)),
    };

    let started = Instant::now();
    drop(watcher);
    assert!(started.elapsed() < Duration::from_millis(100));
    release_tx.send(()).unwrap();
}

#[test]
fn relevant_bursts_coalesce_without_an_event_queue_overflow() {
    let dir = tempfile::tempdir().unwrap();
    let repository = Repository::init(dir.path()).unwrap();
    let watcher = RecommendedWatcher::new(
        |_event: notify::Result<Event>| {},
        Config::default().with_follow_symlinks(false),
    )
    .unwrap();
    let (wake_tx, wake_rx) = mpsc::sync_channel(1);
    let pending_event_sequence = Arc::new(AtomicU64::new(0));
    let cancelled = Arc::new(AtomicBool::new(false));
    let git_config_environment = GitConfigEnvironment::from_process();
    let git_ignore_sources = Arc::new(RwLock::new(
        GitIgnoreSources::discover(&repository, &git_config_environment).unwrap(),
    ));
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let worker = thread::spawn({
        let pending_event_sequence = Arc::clone(&pending_event_sequence);
        let cancelled = Arc::clone(&cancelled);
        let root = dir.path().to_path_buf();
        move || {
            WorkspacePulseWorker {
                identity: WorkspacePulseWatcherIdentity {
                    workspace_id: "workspace-1".to_string(),
                    generation: 7,
                },
                wake_rx,
                event_sequence: Arc::new(AtomicU64::new(10_000)),
                pending_event_sequence,
                reconcile_requested: Arc::new(AtomicBool::new(false)),
                cancelled,
                inbox,
                watcher,
                repository,
                root: root.clone(),
                watched_directories: HashSet::from([root]),
                git_ignore_sources,
                git_ignore_watch_directories: HashSet::new(),
                persistent_git_ignore_watch_directories: HashSet::new(),
                git_config_environment,
                ignored_git_status_paths: HashSet::new(),
                failure_reported: Arc::new(AtomicBool::new(false)),
            }
            .run()
        }
    });

    for sequence in 1..=10_000 {
        pending_event_sequence.store(sequence, Ordering::Release);
        let _ = wake_tx.try_send(());
    }
    drop(wake_tx);
    worker.join().unwrap();

    match commands.try_recv().unwrap() {
        ServerCommand::TerminalPulseFileChanged {
            workspace_id,
            watcher_generation,
            event_sequence,
        } => {
            assert_eq!(workspace_id, "workspace-1");
            assert_eq!(watcher_generation, 7);
            assert_eq!(event_sequence, 10_000);
        }
        _ => panic!("expected a Terminal Pulse change command"),
    }
    assert!(commands.try_recv().is_err());
}
