use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::Duration;

use git2::{ErrorCode, Repository, Status, StatusOptions};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::path_identities::{PathIdentity, PathIdentityCache};
use super::ServerCommand;

#[path = "terminal_pulse_watch_reconciliation.rs"]
mod reconciliation;

const EVENT_COALESCE_WINDOW: Duration = Duration::from_millis(25);

pub(crate) struct WorkspacePulseWatcher {
    generation: u64,
    worker: Option<thread::JoinHandle<()>>,
    wake_tx: mpsc::SyncSender<()>,
    cancelled: Arc<AtomicBool>,
    event_sequence: Arc<AtomicU64>,
}

#[derive(Clone)]
struct WorkspacePulseWatcherIdentity {
    workspace_id: String,
    generation: u64,
}

struct WorkspacePulseWorker {
    identity: WorkspacePulseWatcherIdentity,
    wake_rx: mpsc::Receiver<()>,
    event_sequence: Arc<AtomicU64>,
    pending_event_sequence: Arc<AtomicU64>,
    reconcile_requested: Arc<AtomicBool>,
    cancelled: Arc<AtomicBool>,
    inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    watcher: RecommendedWatcher,
    repository: Repository,
    root: PathBuf,
    watched_directories: HashSet<PathBuf>,
    failure_reported: Arc<AtomicBool>,
}

impl WorkspacePulseWatcher {
    pub(super) fn start_blocking(
        workspace_id: String,
        root: PathBuf,
        generation: u64,
        inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    ) -> HostResult<Self> {
        let root = dunce::canonicalize(&root).map_err(|error| {
            HostError::state(format!(
                "Terminal Pulse workspace could not be resolved: {error}"
            ))
        })?;
        let repository = Repository::discover(&root).map_err(|error| {
            HostError::state(format!("Terminal Pulse requires a Git workspace: {error}"))
        })?;
        if repository.workdir().is_none() {
            return Err(HostError::state(
                "Terminal Pulse requires a Git workspace with a working tree.",
            ));
        }
        let mut path_identities = PathIdentityCache::scan(&root, &repository)?;
        let initial_watch_directories = path_identities.watch_directories().clone();
        let ancestor_ignore_files = ancestor_gitignore_files(&root, &repository)?;
        let git_metadata_directory = dunce::canonicalize(repository.path()).map_err(|error| {
            HostError::state(format!(
                "Terminal Pulse Git metadata could not be resolved: {error}"
            ))
        })?;
        let git_exclude_directory = dunce::canonicalize(repository.commondir().join("info"))
            .map_err(|error| {
                HostError::state(format!(
                    "Terminal Pulse Git exclude directory could not be resolved: {error}"
                ))
            })?;
        let git_exclude_file = git_exclude_directory.join("exclude");
        let worker_repository = Repository::discover(&root).map_err(git_query_error)?;
        let cancelled = Arc::new(AtomicBool::new(false));
        let event_sequence = Arc::new(AtomicU64::new(0));
        let pending_event_sequence = Arc::new(AtomicU64::new(0));
        let callback_cancelled = Arc::clone(&cancelled);
        let callback_event_sequence = Arc::clone(&event_sequence);
        let callback_pending_event_sequence = Arc::clone(&pending_event_sequence);
        let worker_event_sequence = Arc::clone(&event_sequence);
        let reconcile_requested = Arc::new(AtomicBool::new(false));
        let callback_reconcile_requested = Arc::clone(&reconcile_requested);
        let worker_cancelled = Arc::clone(&cancelled);
        let failure_reported = Arc::new(AtomicBool::new(false));
        let callback_failure_reported = Arc::clone(&failure_reported);
        let callback_inbox = inbox.clone();
        let identity = WorkspacePulseWatcherIdentity {
            workspace_id,
            generation,
        };
        let callback_identity = identity.clone();
        let callback_root = root.clone();
        let callback_git_metadata_directory = git_metadata_directory.clone();
        let callback_git_exclude_file = git_exclude_file.clone();
        let callback_ancestor_ignore_files = ancestor_ignore_files.clone();
        let (wake_tx, wake_rx) = mpsc::sync_channel::<()>(1);
        let callback_wake_tx = wake_tx.clone();
        let mut watcher = RecommendedWatcher::new(
            move |event: notify::Result<Event>| {
                if callback_cancelled.load(Ordering::Relaxed) {
                    return;
                }
                let mut event = match event {
                    Ok(event) => event,
                    Err(error) => {
                        callback_cancelled.store(true, Ordering::Relaxed);
                        report_watcher_failure(
                            &callback_identity,
                            &callback_failure_reported,
                            &callback_inbox,
                            error.to_string(),
                        );
                        let _ = callback_wake_tx.try_send(());
                        return;
                    }
                };
                if matches!(event.kind, EventKind::Access(_)) {
                    return;
                }
                let git_rules_changed = event.paths.iter().any(|path| {
                    path_is_git_index_event(&callback_git_metadata_directory, path)
                        || path == &callback_git_exclude_file
                        || callback_ancestor_ignore_files.contains(path)
                });
                if !event.need_rescan() {
                    event
                        .paths
                        .retain(|path| path_is_in_workspace(&callback_root, path));
                    if event.paths.is_empty() && !git_rules_changed {
                        return;
                    }
                } else {
                    callback_cancelled.store(true, Ordering::Relaxed);
                    report_watcher_failure(
                        &callback_identity,
                        &callback_failure_reported,
                        &callback_inbox,
                        "filesystem requested a rescan after events may have been lost",
                    );
                    let _ = callback_wake_tx.try_send(());
                    return;
                }
                let reconcile_watches =
                    git_rules_changed || event_requires_watch_reconcile(&event, &path_identities);
                let relevant = if event.paths.is_empty() {
                    false
                } else {
                    match event_is_git_relevant(
                        &repository,
                        &callback_root,
                        &event,
                        &mut HashSet::new(),
                        &mut path_identities,
                    ) {
                        Ok(relevant) => relevant,
                        Err(error) => {
                            callback_cancelled.store(true, Ordering::Relaxed);
                            report_watcher_failure(
                                &callback_identity,
                                &callback_failure_reported,
                                &callback_inbox,
                                error.wire_message(),
                            );
                            let _ = callback_wake_tx.try_send(());
                            return;
                        }
                    }
                };
                if reconcile_watches {
                    callback_reconcile_requested.store(true, Ordering::Release);
                    let _ = callback_wake_tx.try_send(());
                }
                if !relevant {
                    return;
                }
                let sequence = callback_event_sequence
                    .fetch_add(1, Ordering::SeqCst)
                    .wrapping_add(1);
                callback_pending_event_sequence.store(sequence, Ordering::Release);
                let _ = callback_wake_tx.try_send(());
            },
            watcher_config(),
        )
        .map_err(watcher_error)?;
        for directory in &initial_watch_directories {
            watcher
                .watch(directory, RecursiveMode::NonRecursive)
                .map_err(watcher_error)?;
        }
        watcher
            .watch(&git_metadata_directory, RecursiveMode::NonRecursive)
            .map_err(watcher_error)?;
        watcher
            .watch(&git_exclude_directory, RecursiveMode::NonRecursive)
            .map_err(watcher_error)?;
        for directory in ancestor_ignore_files
            .iter()
            .filter_map(|path| path.parent())
            .filter(|directory| !initial_watch_directories.contains(*directory))
        {
            watcher
                .watch(directory, RecursiveMode::NonRecursive)
                .map_err(watcher_error)?;
        }

        let worker = thread::Builder::new()
            .name(format!("terminal-pulse-{}", identity.workspace_id))
            .spawn(move || {
                WorkspacePulseWorker {
                    identity,
                    wake_rx,
                    event_sequence: worker_event_sequence,
                    pending_event_sequence,
                    reconcile_requested,
                    cancelled: worker_cancelled,
                    inbox,
                    watcher,
                    repository: worker_repository,
                    root,
                    watched_directories: initial_watch_directories,
                    failure_reported,
                }
                .run()
            })
            .map_err(|error| {
                HostError::state(format!("Terminal Pulse worker could not start: {error}"))
            })?;
        Ok(Self {
            generation,
            worker: Some(worker),
            wake_tx,
            cancelled,
            event_sequence,
        })
    }

    pub(super) fn current_event_sequence(&self) -> u64 {
        self.event_sequence.load(Ordering::SeqCst)
    }

    pub(super) fn generation(&self) -> u64 {
        self.generation
    }
}

impl Drop for WorkspacePulseWatcher {
    fn drop(&mut self) {
        self.cancelled.store(true, Ordering::Relaxed);
        let _ = self.wake_tx.try_send(());
        if let Some(worker) = self.worker.take() {
            let _ = thread::Builder::new()
                .name("terminal-pulse-reaper".to_string())
                .spawn(move || {
                    let _ = worker.join();
                });
        }
    }
}

fn watcher_config() -> Config {
    Config::default().with_follow_symlinks(false)
}

fn event_requires_watch_reconcile(event: &Event, identities: &PathIdentityCache) -> bool {
    event.paths.iter().any(|path| {
        path.file_name().is_some_and(|name| name == ".gitignore")
            || identities.identity_for_event(&event.kind, path) == PathIdentity::Directory
    })
}

fn path_is_git_index_event(git_metadata_directory: &Path, path: &Path) -> bool {
    path.parent() == Some(git_metadata_directory)
        && path
            .file_name()
            .is_some_and(|name| name == "index" || name == "index.lock")
}

fn ancestor_gitignore_files(root: &Path, repository: &Repository) -> HostResult<HashSet<PathBuf>> {
    let workdir = repository
        .workdir()
        .ok_or_else(|| HostError::state("Terminal Pulse requires a Git working tree."))?;
    let workdir = dunce::canonicalize(workdir).map_err(|error| {
        HostError::state(format!(
            "Terminal Pulse Git working tree could not be resolved: {error}"
        ))
    })?;
    let mut files = HashSet::new();
    let mut directory = root.parent();
    while let Some(current) = directory.filter(|current| current.starts_with(&workdir)) {
        files.insert(current.join(".gitignore"));
        if current == workdir {
            break;
        }
        directory = current.parent();
    }
    Ok(files)
}

#[cfg(test)]
pub(super) fn event_is_relevant(
    repository: &Repository,
    root: &Path,
    event: &Event,
) -> HostResult<bool> {
    if event.need_rescan() {
        return Err(HostError::state(
            "Terminal Pulse cannot safely classify a filesystem rescan.",
        ));
    }
    let mut path_identities = PathIdentityCache::scan(root, repository)?;
    event_is_git_relevant(
        repository,
        root,
        event,
        &mut HashSet::new(),
        &mut path_identities,
    )
}

#[cfg(test)]
pub(super) fn event_is_relevant_with_identities(
    repository: &Repository,
    root: &Path,
    event: &Event,
    path_identities: &mut PathIdentityCache,
) -> HostResult<bool> {
    event_is_git_relevant(
        repository,
        root,
        event,
        &mut HashSet::new(),
        path_identities,
    )
}

fn event_is_git_relevant(
    repository: &Repository,
    root: &Path,
    event: &Event,
    ignored_prefixes: &mut HashSet<PathBuf>,
    path_identities: &mut PathIdentityCache,
) -> HostResult<bool> {
    let Some(workdir) = repository.workdir() else {
        return Ok(false);
    };
    let identities = event
        .paths
        .iter()
        .map(|path| path_identities.identity_for_event(&event.kind, path))
        .collect::<Vec<_>>();
    path_identities.apply_event(event, &identities);
    for (path, identity) in event.paths.iter().zip(identities) {
        if !path_is_in_workspace(root, path) {
            continue;
        }
        let Ok(relative) = path.strip_prefix(workdir) else {
            continue;
        };
        let git_path = relative.to_string_lossy().replace('\\', "/");
        let directory_prefix = format!("{git_path}/");
        let directory_like = identity == PathIdentity::Directory;
        if directory_like {
            if path_is_ignored(repository, relative, true, ignored_prefixes)? {
                let index = repository.index().map_err(git_query_error)?;
                if index.get_path(relative, 0).is_some()
                    || index.iter().any(|entry| {
                        std::str::from_utf8(&entry.path)
                            .is_ok_and(|entry_path| entry_path.starts_with(&directory_prefix))
                    })
                {
                    return Ok(true);
                }
                continue;
            }
            let mut options = StatusOptions::new();
            options
                .include_untracked(true)
                .recurse_untracked_dirs(true)
                .include_ignored(false)
                .pathspec(git_path);
            if repository
                .statuses(Some(&mut options))
                .map_err(git_query_error)?
                .iter()
                .next()
                .is_some()
            {
                return Ok(true);
            }
            if matches!(
                event.kind,
                EventKind::Remove(_)
                    | EventKind::Modify(notify::event::ModifyKind::Name(
                        notify::event::RenameMode::From
                    ))
            ) {
                return Ok(true);
            }
            continue;
        }
        match repository.status_file(relative) {
            Ok(status) if status.contains(Status::IGNORED) => continue,
            Ok(_) => return Ok(true),
            Err(error) if error.code() == ErrorCode::Ambiguous => return Ok(true),
            Err(error) if error.code() == ErrorCode::NotFound => {
                if !path_is_ignored(repository, relative, directory_like, ignored_prefixes)? {
                    return Ok(true);
                }
            }
            Err(error) => return Err(git_query_error(error)),
        }
    }
    Ok(false)
}

fn path_is_ignored(
    repository: &Repository,
    relative: &Path,
    check_as_directory: bool,
    ignored_prefixes: &mut HashSet<PathBuf>,
) -> HostResult<bool> {
    if ignored_prefixes
        .iter()
        .any(|prefix| relative.starts_with(prefix))
    {
        return Ok(true);
    }
    if repository
        .status_should_ignore(relative)
        .map_err(git_query_error)?
    {
        ignored_prefixes.insert(relative.to_path_buf());
        return Ok(true);
    }
    if check_as_directory
        && repository
            .status_should_ignore(&relative.join(".alera-terminal-pulse-entry"))
            .map_err(git_query_error)?
    {
        ignored_prefixes.insert(relative.to_path_buf());
        return Ok(true);
    }
    Ok(false)
}

fn report_watcher_failure(
    identity: &WorkspacePulseWatcherIdentity,
    failure_reported: &AtomicBool,
    inbox: &tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    error: impl Into<String>,
) {
    if !failure_reported.swap(true, Ordering::Relaxed) {
        let _ = inbox.send(ServerCommand::TerminalPulseWatcherFailed {
            workspace_id: identity.workspace_id.clone(),
            watcher_generation: identity.generation,
            error: error.into(),
        });
    }
}

fn git_query_error(error: git2::Error) -> HostError {
    HostError::state(format!(
        "Terminal Pulse could not inspect Git status: {error}"
    ))
}

fn path_is_in_workspace(root: &Path, path: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(root) else {
        return false;
    };
    !relative.as_os_str().is_empty()
        && !relative
            .components()
            .any(|component| component.as_os_str() == ".git")
}

fn watcher_error(error: notify::Error) -> HostError {
    HostError::state(format!("Terminal Pulse watcher could not start: {error}"))
}

#[cfg(test)]
#[path = "terminal_pulse_watcher_unit_tests.rs"]
mod tests;
