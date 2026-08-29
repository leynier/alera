use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(target_os = "macos")]
use std::sync::{mpsc, Arc, RwLock};
#[cfg(target_os = "macos")]
use std::thread;
#[cfg(target_os = "macos")]
use std::time::Duration;

use git2::Repository;
use notify::{Config, Event};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::event_scope::event_can_remove_paths;
#[cfg(target_os = "macos")]
use super::git_ignore_sources::GitIgnoreSources;
use super::{PathIdentity, PathIdentityCache, ServerCommand, WorkspacePulseWatcherIdentity};

pub(super) fn ensure_setup_active(cancelled: &AtomicBool) -> HostResult<()> {
    if cancelled.load(Ordering::Acquire) {
        return Err(HostError::state(
            "Terminal Pulse watcher setup was cancelled.",
        ));
    }
    Ok(())
}

#[cfg(target_os = "macos")]
pub(super) fn spawn_git_source_poller(
    sources: Arc<RwLock<GitIgnoreSources>>,
    reconcile_requested: Arc<AtomicBool>,
    wake_tx: mpsc::SyncSender<()>,
    cancelled: Arc<AtomicBool>,
) -> HostResult<thread::JoinHandle<()>> {
    let mut fingerprint = sources
        .read()
        .map_err(|_| HostError::state("Terminal Pulse Git ignore source lock failed."))?
        .content_fingerprint();
    thread::Builder::new()
        .name("terminal-pulse-git-sources".to_string())
        .spawn(move || {
            while !cancelled.load(Ordering::Acquire) {
                thread::sleep(Duration::from_millis(250));
                let next = sources
                    .read()
                    .ok()
                    .map(|sources| sources.content_fingerprint());
                let Some(next) = next else {
                    continue;
                };
                if next != fingerprint {
                    fingerprint = next;
                    reconcile_requested.store(true, Ordering::Release);
                    let _ = wake_tx.try_send(());
                }
            }
        })
        .map_err(|error| {
            HostError::state(format!(
                "Terminal Pulse Git ignore source poller could not start: {error}"
            ))
        })
}

pub(super) fn watcher_config() -> Config {
    Config::default().with_follow_symlinks(false)
}

pub(super) fn rewrite_event_root_alias(
    requested_root: &Path,
    canonical_root: &Path,
    event: &mut Event,
) {
    if requested_root == canonical_root {
        return;
    }
    for path in &mut event.paths {
        if let Ok(relative) = path.strip_prefix(requested_root) {
            *path = canonical_root.join(relative);
        }
    }
}

pub(crate) fn event_requires_watch_reconcile(
    event: &Event,
    identities: &PathIdentityCache,
) -> bool {
    event_can_remove_paths(event)
        || event.paths.iter().any(|path| {
            path.file_name().is_some_and(|name| name == ".gitignore")
                || identities.identity_for_event(&event.kind, path) == PathIdentity::Directory
        })
}

pub(super) fn path_is_git_index_event(git_metadata_directory: &Path, path: &Path) -> bool {
    path.parent() == Some(git_metadata_directory)
        && path
            .file_name()
            .is_some_and(|name| name == "index" || name == "index.lock")
}

pub(super) fn ancestor_gitignore_files(
    root: &Path,
    repository: &Repository,
) -> HostResult<HashSet<PathBuf>> {
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

pub(super) fn report_watcher_failure(
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

pub(super) fn git_query_error(error: git2::Error) -> HostError {
    HostError::state(format!(
        "Terminal Pulse could not inspect Git status: {error}"
    ))
}

pub(super) fn watcher_error(error: notify::Error) -> HostError {
    HostError::state(format!("Terminal Pulse watcher could not start: {error}"))
}
