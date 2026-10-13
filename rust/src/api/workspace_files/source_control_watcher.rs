use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use notify::{RecursiveMode, Watcher};

use crate::frb_generated::StreamSink;

use super::{
    workspace_root, SourceControlWatchSignal, SourceControlWatcherHandle, WorkspaceFileError,
    WorkspaceFileErrorKind,
};

#[path = "source_control_watch_paths.rs"]
mod watch_paths;
use watch_paths::{all_changes, SourceControlWatchPaths};

const WATCH_DEBOUNCE_MILLIS: u64 = 180;
const WATCH_MAX_BATCH_MILLIS: u64 = 750;
const WATCH_IDLE_POLL_MILLIS: u64 = 100;

static NEXT_WATCHER_ID: AtomicU64 = AtomicU64::new(1);
static WATCHERS: OnceLock<Mutex<HashMap<String, SourceControlWatcherSession>>> = OnceLock::new();

type PendingChanges = Arc<Mutex<SourceControlWatchSignal>>;

struct SourceControlWatcherSession {
    #[allow(dead_code)]
    watcher: notify::RecommendedWatcher,
    sink: Arc<Mutex<Option<StreamSink<SourceControlWatchSignal>>>>,
    shutdown_tx: mpsc::Sender<()>,
    thread: Option<thread::JoinHandle<()>>,
}

impl SourceControlWatcherSession {
    fn stop(mut self) {
        let _ = self.shutdown_tx.send(());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

pub(super) fn start_source_control_watcher(
    workspace_path: String,
) -> Result<SourceControlWatcherHandle, WorkspaceFileError> {
    let paths = SourceControlWatchPaths::discover(workspace_root(&workspace_path)?)?;
    let roots = paths.roots();
    let id = NEXT_WATCHER_ID.fetch_add(1, Ordering::Relaxed).to_string();
    // Only one wake token is queued. Categories accumulate independently, so a
    // busy build cannot grow an event queue or lose a Git metadata change.
    let (wake_tx, wake_rx) = mpsc::sync_channel::<()>(1);
    let pending = Arc::new(Mutex::new(SourceControlWatchSignal::default()));
    let callback_pending = pending.clone();
    let (shutdown_tx, shutdown_rx) = mpsc::channel::<()>();
    let sink = Arc::new(Mutex::new(None));
    let mut watcher = notify::recommended_watcher(move |result: notify::Result<notify::Event>| {
        let signal = match result {
            Ok(event) => paths.classify(&event),
            Err(_) => Some(all_changes()),
        };
        if let Some(signal) = signal {
            queue_changes(&callback_pending, &wake_tx, signal);
        }
    })
    .map_err(notify_error)?;
    for root in roots {
        watcher
            .watch(&root, RecursiveMode::Recursive)
            .map_err(notify_error)?;
    }

    let thread_sink = sink.clone();
    let thread = thread::Builder::new()
        .name(format!("alera-source-control-watch-{id}"))
        .spawn(move || event_loop(thread_sink, pending, wake_rx, shutdown_rx))
        .map_err(|error| WorkspaceFileError::from_io(error, "source control watcher"))?;

    watchers()
        .lock()
        .map_err(|_| WorkspaceFileError::new(WorkspaceFileErrorKind::Io, "watcher lock poisoned"))?
        .insert(
            id.clone(),
            SourceControlWatcherSession {
                watcher,
                sink,
                shutdown_tx,
                thread: Some(thread),
            },
        );
    Ok(SourceControlWatcherHandle { id })
}

fn queue_changes(
    pending: &PendingChanges,
    wake: &mpsc::SyncSender<()>,
    signal: SourceControlWatchSignal,
) {
    let Ok(mut pending) = pending.lock() else {
        return;
    };
    pending.coalesced_event_count = pending
        .coalesced_event_count
        .saturating_add(signal.coalesced_event_count);
    pending.worktree_changed |= signal.worktree_changed;
    pending.repository_changed |= signal.repository_changed;
    pending.catalog_changed |= signal.catalog_changed;
    let _ = wake.try_send(());
}

pub(super) fn watch_source_control_events(
    handle: SourceControlWatcherHandle,
    sink: StreamSink<SourceControlWatchSignal>,
) {
    let session_sink = {
        let Ok(watchers) = watchers().lock() else {
            return;
        };
        watchers.get(&handle.id).map(|session| session.sink.clone())
    };
    if let Some(session_sink) = session_sink {
        if let Ok(mut current_sink) = session_sink.lock() {
            *current_sink = Some(sink);
        }
    }
}

pub(super) fn stop_source_control_watcher(handle: SourceControlWatcherHandle) {
    let session = watchers()
        .lock()
        .ok()
        .and_then(|mut watchers| watchers.remove(&handle.id));
    if let Some(session) = session {
        session.stop();
    }
}

fn event_loop(
    sink: Arc<Mutex<Option<StreamSink<SourceControlWatchSignal>>>>,
    pending: PendingChanges,
    wake_rx: mpsc::Receiver<()>,
    shutdown_rx: mpsc::Receiver<()>,
) {
    loop {
        match collect_signal(&pending, &wake_rx, &shutdown_rx) {
            CollectOutcome::Signal(signal) => emit_signal(&sink, signal),
            CollectOutcome::Idle => continue,
            CollectOutcome::Shutdown => return,
        }
    }
}

enum CollectOutcome {
    Signal(SourceControlWatchSignal),
    Idle,
    Shutdown,
}

fn collect_signal(
    pending: &PendingChanges,
    wake_rx: &mpsc::Receiver<()>,
    shutdown_rx: &mpsc::Receiver<()>,
) -> CollectOutcome {
    if shutdown_rx.try_recv().is_ok() {
        return CollectOutcome::Shutdown;
    }
    match wake_rx.recv_timeout(Duration::from_millis(WATCH_IDLE_POLL_MILLIS)) {
        Ok(()) => {}
        Err(mpsc::RecvTimeoutError::Timeout) => return CollectOutcome::Idle,
        Err(mpsc::RecvTimeoutError::Disconnected) => return CollectOutcome::Shutdown,
    }
    let deadline = Instant::now() + Duration::from_millis(WATCH_MAX_BATCH_MILLIS);
    loop {
        if shutdown_rx.try_recv().is_ok() {
            return CollectOutcome::Shutdown;
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        match wake_rx.recv_timeout(remaining.min(Duration::from_millis(WATCH_DEBOUNCE_MILLIS))) {
            Ok(()) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => break,
            Err(mpsc::RecvTimeoutError::Disconnected) => return CollectOutcome::Shutdown,
        }
    }
    let Ok(mut pending) = pending.lock() else {
        return CollectOutcome::Idle;
    };
    let signal = std::mem::take(&mut *pending);
    if signal.coalesced_event_count == 0 {
        CollectOutcome::Idle
    } else {
        CollectOutcome::Signal(signal)
    }
}

fn emit_signal(
    sink: &Arc<Mutex<Option<StreamSink<SourceControlWatchSignal>>>>,
    signal: SourceControlWatchSignal,
) {
    let Ok(mut sink) = sink.lock() else {
        return;
    };
    if sink
        .as_ref()
        .is_some_and(|current| current.add(signal).is_err())
    {
        *sink = None;
    }
}

fn watchers() -> &'static Mutex<HashMap<String, SourceControlWatcherSession>> {
    WATCHERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn notify_error(error: notify::Error) -> WorkspaceFileError {
    WorkspaceFileError::new(WorkspaceFileErrorKind::Io, error.to_string())
}

#[cfg(test)]
#[path = "source_control_watcher_tests.rs"]
mod tests;
