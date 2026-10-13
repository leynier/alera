use super::*;
use notify::{
    event::{AccessKind, AccessMode, ModifyKind},
    Event, EventKind,
};
use std::path::Path;

fn event(path: &Path) -> Event {
    Event::new(EventKind::Modify(ModifyKind::Any)).add_path(path.to_path_buf())
}

fn fixture() -> (tempfile::TempDir, git2::Repository) {
    let dir = tempfile::tempdir().unwrap();
    let repo = git2::Repository::init(dir.path().canonicalize().unwrap()).unwrap();
    std::fs::write(dir.path().join("tracked.txt"), "initial\n").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("tracked.txt")).unwrap();
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let signature = git2::Signature::now("Test", "test@example.com").unwrap();
    repo.commit(Some("HEAD"), &signature, &signature, "initial", &tree, &[])
        .unwrap();
    drop(tree);
    (dir, repo)
}

#[test]
fn ignores_reads_and_classifies_file_changes() {
    let (dir, _) = fixture();
    let paths = SourceControlWatchPaths::discover(dir.path().canonicalize().unwrap()).unwrap();
    let root = dir.path().canonicalize().unwrap();
    let file = root.join("tracked.txt");
    let read =
        Event::new(EventKind::Access(AccessKind::Open(AccessMode::Any))).add_path(file.clone());
    assert!(paths.classify(&read).is_none());
    let signal = paths.classify(&event(&file)).unwrap();
    assert!(signal.worktree_changed);
    assert!(!signal.repository_changed);
    assert!(!signal.catalog_changed);
    assert!(paths
        .classify(&event(
            &dir.path().canonicalize().unwrap().join(".dart_tool/cache")
        ))
        .is_none());
    assert!(paths
        .classify(&event(
            &dir.path()
                .canonicalize()
                .unwrap()
                .join("node_modules/package/file")
        ))
        .is_none());
    assert!(paths
        .classify(&event(
            &dir.path()
                .canonicalize()
                .unwrap()
                .join(".git/objects/aa/bb")
        ))
        .is_none());
}

#[test]
fn observes_own_linked_worktree_metadata_and_shared_refs() {
    let (dir, repo) = fixture();
    let checkout = dir.path().join("selected");
    repo.worktree("selected", &checkout, None).unwrap();
    let linked = git2::Repository::open(&checkout).unwrap();
    let paths = SourceControlWatchPaths::discover(checkout.canonicalize().unwrap()).unwrap();
    assert!(paths
        .roots()
        .iter()
        .any(|root| linked.path().starts_with(root)));
    assert!(paths
        .roots()
        .iter()
        .any(|root| linked.commondir().starts_with(root)));
    for name in ["HEAD", "index"] {
        let signal = paths.classify(&event(&linked.path().join(name))).unwrap();
        assert!(signal.repository_changed);
        assert!(!signal.catalog_changed);
    }
    let signal = paths
        .classify(&event(&linked.commondir().join("refs/heads/main")))
        .unwrap();
    assert!(signal.catalog_changed);
    assert!(paths
        .classify(&event(&linked.commondir().join("worktrees/other/index")))
        .is_none());
    assert!(paths
        .classify(&event(&linked.commondir().join("index")))
        .is_none());
}

#[test]
fn main_checkout_ignores_sibling_worktree_index_changes() {
    let (dir, repo) = fixture();
    let paths = SourceControlWatchPaths::discover(dir.path().canonicalize().unwrap()).unwrap();
    assert!(paths
        .classify(&event(&repo.path().join("worktrees/other/index")))
        .is_none());
    assert!(
        paths
            .classify(&event(&repo.path().join("index")))
            .unwrap()
            .repository_changed
    );
}

#[test]
fn bounded_inbox_coalesces_categories_without_losing_changes() {
    let pending = Arc::new(Mutex::new(SourceControlWatchSignal::default()));
    let (wake_tx, wake_rx) = mpsc::sync_channel(1);
    let (_shutdown_tx, shutdown_rx) = mpsc::channel();
    for _ in 0..1000 {
        queue_changes(
            &pending,
            &wake_tx,
            SourceControlWatchSignal {
                coalesced_event_count: 1,
                worktree_changed: true,
                ..Default::default()
            },
        );
    }
    queue_changes(
        &pending,
        &wake_tx,
        SourceControlWatchSignal {
            coalesced_event_count: 1,
            catalog_changed: true,
            ..Default::default()
        },
    );
    match collect_signal(&pending, &wake_rx, &shutdown_rx) {
        CollectOutcome::Signal(signal) => {
            assert_eq!(signal.coalesced_event_count, 1001);
            assert!(signal.worktree_changed && signal.catalog_changed);
        }
        _ => panic!("expected one merged signal"),
    }
    assert!(matches!(
        collect_signal(&pending, &wake_rx, &shutdown_rx),
        CollectOutcome::Idle
    ));
}

#[test]
fn sustained_events_flush_without_waiting_for_the_writer_to_stop() {
    let pending = Arc::new(Mutex::new(SourceControlWatchSignal::default()));
    let (wake_tx, wake_rx) = mpsc::sync_channel(1);
    let (_shutdown_tx, shutdown_rx) = mpsc::channel();
    let producer_pending = pending.clone();
    let producer = thread::spawn(move || {
        for _ in 0..20 {
            queue_changes(&producer_pending, &wake_tx, all_changes());
            thread::sleep(Duration::from_millis(60));
        }
    });
    assert!(matches!(
        collect_signal(&pending, &wake_rx, &shutdown_rx),
        CollectOutcome::Signal(_)
    ));
    assert!(!producer.is_finished());
    producer.join().unwrap();
}

#[test]
fn native_read_does_not_notify_but_real_write_does() {
    let (dir, _) = fixture();
    let paths = SourceControlWatchPaths::discover(dir.path().canonicalize().unwrap()).unwrap();
    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |result: notify::Result<Event>| {
        if let Ok(event) = result {
            if let Some(signal) = paths.classify(&event) {
                let _ = tx.send(signal);
            }
        }
    })
    .unwrap();
    watcher
        .watch(
            &dir.path().canonicalize().unwrap(),
            RecursiveMode::Recursive,
        )
        .unwrap();
    std::fs::read(dir.path().join("tracked.txt")).unwrap();
    assert!(rx.recv_timeout(Duration::from_millis(300)).is_err());
    std::fs::write(dir.path().join("tracked.txt"), "changed\n").unwrap();
    assert!(
        rx.recv_timeout(Duration::from_secs(2))
            .unwrap()
            .worktree_changed
    );
}

#[test]
fn idle_and_shutdown_do_not_emit_changes() {
    let pending = Arc::new(Mutex::new(SourceControlWatchSignal::default()));
    let (wake_tx, wake_rx) = mpsc::sync_channel(1);
    let (shutdown_tx, shutdown_rx) = mpsc::channel();
    assert!(matches!(
        collect_signal(&pending, &wake_rx, &shutdown_rx),
        CollectOutcome::Idle
    ));
    shutdown_tx.send(()).unwrap();
    assert!(matches!(
        collect_signal(&pending, &wake_rx, &shutdown_rx),
        CollectOutcome::Shutdown
    ));
    drop(wake_tx);
}
