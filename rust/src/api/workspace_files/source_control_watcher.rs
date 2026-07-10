use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use notify::{RecursiveMode, Watcher};

use crate::frb_generated::StreamSink;

use super::{
    workspace_root, SourceControlWatchSignal, SourceControlWatcherHandle, WorkspaceFileError,
    WorkspaceFileErrorKind,
};

const WATCH_DEBOUNCE_MILLIS: u64 = 180;
const WATCH_IDLE_POLL_MILLIS: u64 = 100;

static NEXT_WATCHER_ID: AtomicU64 = AtomicU64::new(1);
static WATCHERS: OnceLock<Mutex<HashMap<String, SourceControlWatcherSession>>> = OnceLock::new();

struct SourceControlWatcherSession {
    // Held only to keep the OS watch alive; dropping it stops file notifications.
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
    let root = workspace_root(&workspace_path)?;
    let id = NEXT_WATCHER_ID.fetch_add(1, Ordering::Relaxed).to_string();
    let (event_tx, event_rx) = mpsc::channel::<notify::Result<notify::Event>>();
    let (shutdown_tx, shutdown_rx) = mpsc::channel::<()>();
    let sink = Arc::new(Mutex::new(None));
    let mut watcher = notify::recommended_watcher(move |result| {
        let _ = event_tx.send(result);
    })
    .map_err(notify_error)?;
    // Recursive watch of the whole working tree, including `.git/`, so commits,
    // branch switches, staging and out-of-app file edits all surface here.
    watcher
        .watch(&root, RecursiveMode::Recursive)
        .map_err(notify_error)?;

    let thread_sink = sink.clone();
    let thread = thread::Builder::new()
        .name(format!("alera-source-control-watch-{id}"))
        .spawn(move || {
            event_loop(thread_sink, event_rx, shutdown_rx);
        })
        .map_err(|error| WorkspaceFileError::from_io(error, "source control watcher"))?;

    let session = SourceControlWatcherSession {
        watcher,
        sink,
        shutdown_tx,
        thread: Some(thread),
    };
    watchers()
        .lock()
        .map_err(|_| WorkspaceFileError::new(WorkspaceFileErrorKind::Io, "watcher lock poisoned"))?
        .insert(id.clone(), session);
    Ok(SourceControlWatcherHandle { id })
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
    let Some(session_sink) = session_sink else {
        return;
    };
    {
        if let Ok(mut current_sink) = session_sink.lock() {
            *current_sink = Some(sink);
        };
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
    event_rx: mpsc::Receiver<notify::Result<notify::Event>>,
    shutdown_rx: mpsc::Receiver<()>,
) {
    loop {
        match collect_signal(&event_rx, &shutdown_rx) {
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

/// Runs one debounce cycle: blocks (with idle polling) for a first event, then
/// coalesces any further events arriving within the debounce window into a
/// single signal. Kept independent of `notify` and `StreamSink` so the
/// coalescing logic is unit-testable.
fn collect_signal(
    event_rx: &mpsc::Receiver<notify::Result<notify::Event>>,
    shutdown_rx: &mpsc::Receiver<()>,
) -> CollectOutcome {
    if shutdown_rx.try_recv().is_ok() {
        return CollectOutcome::Shutdown;
    }
    let first_event = match event_rx.recv_timeout(Duration::from_millis(WATCH_IDLE_POLL_MILLIS)) {
        Ok(result) => result,
        Err(mpsc::RecvTimeoutError::Timeout) => return CollectOutcome::Idle,
        Err(mpsc::RecvTimeoutError::Disconnected) => return CollectOutcome::Shutdown,
    };
    let mut coalesced_event_count = u32::from(first_event.is_ok());

    loop {
        if shutdown_rx.try_recv().is_ok() {
            return CollectOutcome::Shutdown;
        }
        match event_rx.recv_timeout(Duration::from_millis(WATCH_DEBOUNCE_MILLIS)) {
            Ok(result) => {
                if result.is_ok() {
                    coalesced_event_count += 1;
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => break,
            Err(mpsc::RecvTimeoutError::Disconnected) => return CollectOutcome::Shutdown,
        }
    }

    if coalesced_event_count == 0 {
        return CollectOutcome::Idle;
    }
    CollectOutcome::Signal(SourceControlWatchSignal {
        coalesced_event_count,
    })
}

fn emit_signal(
    sink: &Arc<Mutex<Option<StreamSink<SourceControlWatchSignal>>>>,
    signal: SourceControlWatchSignal,
) {
    // Closed Flutter sinks must not poison the watcher thread: drop the sink
    // and keep the OS watch alive until the client re-subscribes or stops.
    let Ok(mut sink) = sink.lock() else {
        return;
    };
    let Some(current_sink) = sink.as_ref() else {
        return;
    };
    if current_sink.add(signal).is_err() {
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
mod tests {
    use super::*;
    use notify::{Event, EventKind};

    fn ok_event() -> notify::Result<Event> {
        Ok(Event::new(EventKind::Modify(
            notify::event::ModifyKind::Any,
        )))
    }

    #[test]
    fn coalesces_a_burst_into_one_signal() {
        let (event_tx, event_rx) = mpsc::channel::<notify::Result<Event>>();
        let (_shutdown_tx, shutdown_rx) = mpsc::channel::<()>();
        for _ in 0..4 {
            event_tx.send(ok_event()).unwrap();
        }

        match collect_signal(&event_rx, &shutdown_rx) {
            CollectOutcome::Signal(signal) => {
                assert_eq!(signal.coalesced_event_count, 4);
            }
            _ => panic!("expected a coalesced signal"),
        }
    }

    #[test]
    fn idles_when_no_events_arrive() {
        let (_event_tx, event_rx) = mpsc::channel::<notify::Result<Event>>();
        let (_shutdown_tx, shutdown_rx) = mpsc::channel::<()>();

        assert!(matches!(
            collect_signal(&event_rx, &shutdown_rx),
            CollectOutcome::Idle
        ));
    }

    #[test]
    fn shuts_down_when_event_channel_disconnects() {
        let (event_tx, event_rx) = mpsc::channel::<notify::Result<Event>>();
        let (_shutdown_tx, shutdown_rx) = mpsc::channel::<()>();
        drop(event_tx);

        assert!(matches!(
            collect_signal(&event_rx, &shutdown_rx),
            CollectOutcome::Shutdown
        ));
    }
}
