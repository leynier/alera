use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use notify::{RecursiveMode, Watcher};

use crate::frb_generated::StreamSink;

use super::{
    relative_string, resolve_existing, workspace_root, WorkspaceExplorerWatchBatch,
    WorkspaceExplorerWatcherHandle, WorkspaceFileError, WorkspaceFileErrorKind,
};

const WATCH_DEBOUNCE_MILLIS: u64 = 180;
const WATCH_IDLE_POLL_MILLIS: u64 = 100;

static NEXT_WATCHER_ID: AtomicU64 = AtomicU64::new(1);
static WATCHERS: OnceLock<Mutex<HashMap<String, WatcherSession>>> = OnceLock::new();

struct WatcherSession {
    root: PathBuf,
    watcher: notify::RecommendedWatcher,
    watched_paths: Arc<Mutex<HashMap<String, PathBuf>>>,
    sink: Arc<Mutex<Option<StreamSink<WorkspaceExplorerWatchBatch>>>>,
    shutdown_tx: mpsc::Sender<()>,
    thread: Option<thread::JoinHandle<()>>,
}

impl WatcherSession {
    fn stop(mut self) {
        let _ = self.shutdown_tx.send(());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

pub(super) fn start_workspace_explorer_watcher(
    workspace_path: String,
) -> Result<WorkspaceExplorerWatcherHandle, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let id = NEXT_WATCHER_ID.fetch_add(1, Ordering::Relaxed).to_string();
    let (event_tx, event_rx) = mpsc::channel::<notify::Result<notify::Event>>();
    let (shutdown_tx, shutdown_rx) = mpsc::channel::<()>();
    let watched_paths = Arc::new(Mutex::new(HashMap::<String, PathBuf>::new()));
    let sink = Arc::new(Mutex::new(None));
    let watcher = notify::recommended_watcher(move |result| {
        let _ = event_tx.send(result);
    })
    .map_err(notify_error)?;
    let thread_root = root.clone();
    let thread_watched_paths = watched_paths.clone();
    let thread_sink = sink.clone();
    let thread = thread::Builder::new()
        .name(format!("alera-explorer-watch-{id}"))
        .spawn(move || {
            event_loop(
                thread_root,
                thread_watched_paths,
                thread_sink,
                event_rx,
                shutdown_rx,
            );
        })
        .map_err(|error| WorkspaceFileError::from_io(error, "workspace explorer watcher"))?;

    let session = WatcherSession {
        root,
        watcher,
        watched_paths,
        sink,
        shutdown_tx,
        thread: Some(thread),
    };
    watchers()
        .lock()
        .map_err(|_| WorkspaceFileError::new(WorkspaceFileErrorKind::Io, "watcher lock poisoned"))?
        .insert(id.clone(), session);
    Ok(WorkspaceExplorerWatcherHandle { id })
}

pub(super) fn update_workspace_explorer_watcher(
    handle: WorkspaceExplorerWatcherHandle,
    watched_relative_paths: Vec<String>,
) -> Result<(), WorkspaceFileError> {
    let mut watchers = watchers().lock().map_err(|_| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::Io, "watcher lock poisoned")
    })?;
    let session = watchers.get_mut(&handle.id).ok_or_else(|| {
        WorkspaceFileError::new(
            WorkspaceFileErrorKind::NotFound,
            "workspace explorer watcher",
        )
    })?;
    let mut next_paths = HashMap::<String, PathBuf>::new();
    for relative_path in watched_relative_paths {
        let relative_path = normalize_relative_path(&relative_path);
        match resolve_existing(&session.root, &relative_path) {
            Ok(path) => {
                let metadata = std::fs::symlink_metadata(&path)
                    .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
                if metadata.is_dir() {
                    next_paths.insert(relative_path, path);
                }
            }
            Err(error) if error.kind == WorkspaceFileErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
    }

    let current_paths = session
        .watched_paths
        .lock()
        .map_err(|_| WorkspaceFileError::new(WorkspaceFileErrorKind::Io, "watcher lock poisoned"))?
        .clone();

    for (relative_path, absolute_path) in &current_paths {
        if next_paths.get(relative_path) != Some(absolute_path) {
            let _ = session.watcher.unwatch(absolute_path);
        }
    }
    for (relative_path, absolute_path) in &next_paths {
        if current_paths.get(relative_path) != Some(absolute_path) {
            session
                .watcher
                .watch(absolute_path, RecursiveMode::NonRecursive)
                .map_err(notify_error)?;
        }
    }
    *session.watched_paths.lock().map_err(|_| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::Io, "watcher lock poisoned")
    })? = next_paths;
    Ok(())
}

pub(super) fn watch_workspace_explorer_events(
    handle: WorkspaceExplorerWatcherHandle,
    sink: StreamSink<WorkspaceExplorerWatchBatch>,
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

pub(super) fn stop_workspace_explorer_watcher(handle: WorkspaceExplorerWatcherHandle) {
    let session = watchers()
        .lock()
        .ok()
        .and_then(|mut watchers| watchers.remove(&handle.id));
    if let Some(session) = session {
        session.stop();
    }
}

fn event_loop(
    root: PathBuf,
    watched_paths: Arc<Mutex<HashMap<String, PathBuf>>>,
    sink: Arc<Mutex<Option<StreamSink<WorkspaceExplorerWatchBatch>>>>,
    event_rx: mpsc::Receiver<notify::Result<notify::Event>>,
    shutdown_rx: mpsc::Receiver<()>,
) {
    loop {
        if shutdown_rx.try_recv().is_ok() {
            return;
        }
        let first_event = match event_rx.recv_timeout(Duration::from_millis(WATCH_IDLE_POLL_MILLIS))
        {
            Ok(result) => result,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => return,
        };
        let mut events = Vec::new();
        let mut coalesced_event_count = 0;
        if let Ok(event) = first_event {
            events.push(event);
        }

        loop {
            if shutdown_rx.try_recv().is_ok() {
                return;
            }
            match event_rx.recv_timeout(Duration::from_millis(WATCH_DEBOUNCE_MILLIS)) {
                Ok(result) => {
                    coalesced_event_count += 1;
                    if let Ok(event) = result {
                        events.push(event);
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => break,
                Err(mpsc::RecvTimeoutError::Disconnected) => return,
            }
        }

        if let Some(batch) = build_batch(&root, &watched_paths, events, coalesced_event_count) {
            emit_batch(&sink, batch);
        }
    }
}

fn build_batch(
    root: &Path,
    watched_paths: &Arc<Mutex<HashMap<String, PathBuf>>>,
    events: Vec<notify::Event>,
    coalesced_event_count: u32,
) -> Option<WorkspaceExplorerWatchBatch> {
    let watched_paths = watched_paths.lock().ok()?.clone();
    if watched_paths.is_empty() {
        return None;
    }
    let mut directory_relative_paths = HashSet::<String>::new();
    let mut changed_relative_paths = HashSet::<String>::new();
    for event in events {
        for event_path in event.paths {
            let event_path = normalize_event_path(root, event_path);
            if let Ok(relative_path) = relative_string(root, &event_path) {
                changed_relative_paths.insert(relative_path);
            }
            if let Some(relative_path) = affected_watched_directory(&watched_paths, &event_path) {
                directory_relative_paths.insert(relative_path);
            }
        }
    }
    if directory_relative_paths.is_empty() {
        return None;
    }
    let mut directory_relative_paths = directory_relative_paths.into_iter().collect::<Vec<_>>();
    let mut changed_relative_paths = changed_relative_paths.into_iter().collect::<Vec<_>>();
    directory_relative_paths.sort();
    changed_relative_paths.sort();
    Some(WorkspaceExplorerWatchBatch {
        directory_relative_paths,
        changed_relative_paths,
        coalesced_event_count,
    })
}

fn affected_watched_directory(
    watched_paths: &HashMap<String, PathBuf>,
    event_path: &Path,
) -> Option<String> {
    watched_paths
        .iter()
        .filter_map(|(relative_path, absolute_path)| {
            (event_path == absolute_path
                || event_path.parent() == Some(absolute_path.as_path())
                || event_path.starts_with(absolute_path))
            .then_some((relative_path, absolute_path))
        })
        .max_by_key(|(_, absolute_path)| absolute_path.components().count())
        .map(|(relative_path, _)| relative_path.clone())
}

fn emit_batch(
    sink: &Arc<Mutex<Option<StreamSink<WorkspaceExplorerWatchBatch>>>>,
    batch: WorkspaceExplorerWatchBatch,
) {
    // Closed Flutter sinks must not poison the watcher thread: drop the sink
    // and keep the OS watch alive until the client re-subscribes or stops.
    let Ok(mut sink) = sink.lock() else {
        return;
    };
    let Some(current_sink) = sink.as_ref() else {
        return;
    };
    if current_sink.add(batch).is_err() {
        *sink = None;
    }
}

fn watchers() -> &'static Mutex<HashMap<String, WatcherSession>> {
    WATCHERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn notify_error(error: notify::Error) -> WorkspaceFileError {
    WorkspaceFileError::new(WorkspaceFileErrorKind::Io, error.to_string())
}

fn normalize_event_path(root: &Path, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        path
    } else {
        root.join(path)
    }
}

fn normalize_relative_path(relative_path: &str) -> String {
    relative_path.trim_matches('/').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use notify::{Event, EventKind};

    #[test]
    fn explicitly_watched_ignored_named_directory_emits_refresh() {
        let workspace = tempfile::tempdir().expect("workspace");
        let build = workspace.path().join("build");
        let watched_paths = Arc::new(Mutex::new(HashMap::from([(
            "build".to_string(),
            build.clone(),
        )])));
        let event = Event::new(EventKind::Modify(notify::event::ModifyKind::Any))
            .add_path(build.join("artifact.txt"));

        let batch = build_batch(workspace.path(), &watched_paths, vec![event], 0)
            .expect("watched directory refresh");

        assert_eq!(batch.directory_relative_paths, vec!["build"]);
        assert_eq!(batch.changed_relative_paths, vec!["build/artifact.txt"]);
    }
}
