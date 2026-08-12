use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, RwLock};
use std::thread;
use std::time::Duration;

use git2::{Repository, StatusOptions};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::path_identities::{is_missing_ambiguous_rename, PathIdentity, PathIdentityCache};
use super::ServerCommand;

#[path = "terminal_pulse_event_scope.rs"]
pub(super) mod event_scope;
#[path = "terminal_pulse_git_ignore_sources.rs"]
mod git_ignore_sources;
#[path = "terminal_pulse_git_relevance.rs"]
mod git_relevance;
#[path = "terminal_pulse_watch_reconciliation.rs"]
mod reconciliation;

use event_scope::{
    event_can_remove_paths, event_invalidates_workspace_root, retain_workspace_paths,
};
pub(super) use git_ignore_sources::GitConfigEnvironment;
use git_ignore_sources::{
    prepare_repository, refresh_git_ignore_source_watches, reopen_repository, GitIgnoreSources,
};
use git_relevance::event_is_git_relevant;

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
    git_ignore_sources: Arc<RwLock<GitIgnoreSources>>,
    git_ignore_watch_directories: HashSet<PathBuf>,
    git_config_environment: GitConfigEnvironment,
    failure_reported: Arc<AtomicBool>,
}

impl WorkspacePulseWatcher {
    #[cfg(test)]
    pub(super) fn start_blocking(
        workspace_id: String,
        root: PathBuf,
        generation: u64,
        inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    ) -> HostResult<Self> {
        Self::start_blocking_with_environment(
            workspace_id,
            root,
            generation,
            inbox,
            GitConfigEnvironment::from_process(),
            Arc::new(AtomicBool::new(false)),
        )
    }

    pub(super) fn start_blocking_with_environment(
        workspace_id: String,
        root: PathBuf,
        generation: u64,
        inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>,
        git_config_environment: GitConfigEnvironment,
        cancelled: Arc<AtomicBool>,
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
        ensure_setup_active(&cancelled)?;
        let mut repository = prepare_repository(repository, &git_config_environment)?;
        let mut path_identities =
            PathIdentityCache::scan_with_cancellation(&root, &repository, &cancelled)?;
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
        let git_ignore_sources = Arc::new(RwLock::new(GitIgnoreSources::discover(
            &repository,
            &git_config_environment,
        )?));
        let worker_repository = prepare_repository(
            Repository::discover(&root).map_err(git_query_error)?,
            &git_config_environment,
        )?;
        ensure_setup_active(&cancelled)?;
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
        let callback_git_ignore_sources = Arc::clone(&git_ignore_sources);
        let callback_git_config_environment = git_config_environment.clone();
        let (wake_tx, wake_rx) = mpsc::sync_channel::<()>(1);
        let callback_wake_tx = wake_tx.clone();
        let mut git_rules_dirty = false;
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
                if event_invalidates_workspace_root(&callback_root, &event) {
                    callback_cancelled.store(true, Ordering::Relaxed);
                    report_watcher_failure(
                        &callback_identity,
                        &callback_failure_reported,
                        &callback_inbox,
                        "workspace root was removed or renamed",
                    );
                    let _ = callback_wake_tx.try_send(());
                    return;
                }
                let git_rules_changed = event.paths.iter().any(|path| {
                    path_is_git_index_event(&callback_git_metadata_directory, path)
                        || path == &callback_git_exclude_file
                        || callback_ancestor_ignore_files.contains(path)
                        || callback_git_ignore_sources
                            .read()
                            .is_ok_and(|sources| sources.contains(path))
                });
                if git_rules_changed {
                    git_rules_dirty = true;
                } else if std::mem::take(&mut git_rules_dirty) {
                    match reopen_repository(&repository, &callback_git_config_environment) {
                        Ok(refreshed) => repository = refreshed,
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
                }
                if !event.need_rescan() {
                    retain_workspace_paths(&callback_root, &mut event);
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
            ensure_setup_active(&cancelled)?;
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
        let mut git_ignore_watch_directories = HashSet::from([
            git_metadata_directory.clone(),
            git_exclude_directory.clone(),
        ]);
        git_ignore_watch_directories.extend(
            ancestor_ignore_files
                .iter()
                .filter_map(|path| path.parent().map(Path::to_path_buf)),
        );
        refresh_git_ignore_source_watches(
            &git_ignore_sources,
            &mut git_ignore_watch_directories,
            &initial_watch_directories,
            &mut watcher,
            &worker_repository,
            &git_config_environment,
        )?;
        ensure_setup_active(&cancelled)?;

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
                    git_ignore_sources,
                    git_ignore_watch_directories,
                    git_config_environment,
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

fn ensure_setup_active(cancelled: &AtomicBool) -> HostResult<()> {
    if cancelled.load(Ordering::Acquire) {
        return Err(HostError::state(
            "Terminal Pulse watcher setup was cancelled.",
        ));
    }
    Ok(())
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

pub(super) fn event_requires_watch_reconcile(
    event: &Event,
    identities: &PathIdentityCache,
) -> bool {
    event_can_remove_paths(event)
        || event.paths.iter().any(|path| {
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

fn watcher_error(error: notify::Error) -> HostError {
    HostError::state(format!("Terminal Pulse watcher could not start: {error}"))
}

#[cfg(test)]
#[path = "terminal_pulse_watcher_unit_tests.rs"]
mod tests;
