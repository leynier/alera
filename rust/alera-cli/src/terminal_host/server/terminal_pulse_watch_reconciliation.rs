use std::time::Instant;

use super::*;

impl WorkspacePulseWorker {
    pub(super) fn run(mut self) {
        while self.wake_rx.recv().is_ok() {
            let deadline = Instant::now() + EVENT_COALESCE_WINDOW;
            thread::sleep(deadline.saturating_duration_since(Instant::now()));
            while self.wake_rx.try_recv().is_ok() {}
            if self.cancelled.load(Ordering::Relaxed) {
                return;
            }
            if self.reconcile_requested.swap(false, Ordering::AcqRel) {
                self.repository =
                    match reopen_repository(&self.repository, &self.git_config_environment) {
                        Ok(repository) => repository,
                        Err(error) => {
                            self.fail(error);
                            return;
                        }
                    };
                if let Err(error) = refresh_git_ignore_source_watches(
                    &self.git_ignore_sources,
                    &mut self.git_ignore_watch_directories,
                    &self.watched_directories,
                    &mut self.watcher,
                    &self.repository,
                    &self.git_config_environment,
                ) {
                    self.fail(error);
                    return;
                }
                let additions = match reconcile_watch_directories(
                    &mut self.watcher,
                    &self.repository,
                    &self.root,
                    &mut self.watched_directories,
                    &self.git_ignore_watch_directories,
                ) {
                    Ok(additions) => additions,
                    Err(error) => {
                        self.fail(error);
                        return;
                    }
                };
                let status_snapshot =
                    match workspace_git_status_snapshot(&self.repository, &self.root) {
                        Ok(snapshot) => snapshot,
                        Err(error) => {
                            self.fail(error);
                            return;
                        }
                    };
                let newly_unignored = self
                    .ignored_git_status_paths
                    .iter()
                    .any(|path| status_snapshot.changed.contains(path));
                self.ignored_git_status_paths = status_snapshot.ignored;
                match directories_have_git_changes(&self.repository, &additions) {
                    Ok(has_changes) if newly_unignored || has_changes => self.record_change(),
                    Ok(_) => {}
                    Err(error) => {
                        self.fail(error);
                        return;
                    }
                }
            }
            let latest_event_sequence = self.pending_event_sequence.swap(0, Ordering::AcqRel);
            if latest_event_sequence != 0
                && self
                    .inbox
                    .send(ServerCommand::TerminalPulseFileChanged {
                        workspace_id: self.identity.workspace_id.clone(),
                        watcher_generation: self.identity.generation,
                        event_sequence: latest_event_sequence,
                    })
                    .is_err()
            {
                return;
            }
        }
    }

    fn record_change(&self) {
        let sequence = self
            .event_sequence
            .fetch_add(1, Ordering::SeqCst)
            .wrapping_add(1);
        self.pending_event_sequence
            .store(sequence, Ordering::Release);
    }

    fn fail(&self, error: HostError) {
        self.cancelled.store(true, Ordering::Relaxed);
        report_watcher_failure(
            &self.identity,
            &self.failure_reported,
            &self.inbox,
            error.wire_message(),
        );
    }
}

struct WorkspaceGitStatusSnapshot {
    ignored: HashSet<PathBuf>,
    changed: HashSet<PathBuf>,
}

pub(super) fn ignored_git_status_paths(
    repository: &Repository,
    root: &Path,
) -> HostResult<HashSet<PathBuf>> {
    Ok(workspace_git_status_snapshot(repository, root)?.ignored)
}

fn workspace_git_status_snapshot(
    repository: &Repository,
    root: &Path,
) -> HostResult<WorkspaceGitStatusSnapshot> {
    let Some(workdir) = repository.workdir() else {
        return Ok(WorkspaceGitStatusSnapshot {
            ignored: HashSet::new(),
            changed: HashSet::new(),
        });
    };
    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .include_ignored(true)
        .recurse_untracked_dirs(false)
        .recurse_ignored_dirs(false)
        .disable_pathspec_match(true);
    if root != workdir {
        let relative = root.strip_prefix(workdir).map_err(|_| {
            HostError::state("Terminal Pulse workspace is outside its Git working tree.")
        })?;
        options.pathspec(relative.to_string_lossy().replace('\\', "/"));
    }
    let statuses = repository
        .statuses(Some(&mut options))
        .map_err(git_query_error)?;
    let mut ignored = HashSet::new();
    let mut changed = HashSet::new();
    for entry in statuses.iter() {
        let Some(path) = repository_path_from_bytes(entry.path_bytes()) else {
            continue;
        };
        if entry.status().is_ignored() {
            ignored.insert(path);
        } else if entry.status() != git2::Status::CURRENT {
            changed.insert(path);
        }
    }
    Ok(WorkspaceGitStatusSnapshot { ignored, changed })
}

fn reconcile_watch_directories(
    watcher: &mut RecommendedWatcher,
    repository: &Repository,
    root: &Path,
    watched_directories: &mut HashSet<PathBuf>,
    git_ignore_watch_directories: &HashSet<PathBuf>,
) -> HostResult<Vec<PathBuf>> {
    let identities = PathIdentityCache::scan(root, repository)?;
    let desired = identities.watch_directories();
    let additions = desired
        .difference(watched_directories)
        .cloned()
        .collect::<Vec<_>>();
    let removals = watched_directories
        .difference(desired)
        .cloned()
        .collect::<Vec<_>>();
    for directory in &additions {
        watcher
            .watch(directory, RecursiveMode::NonRecursive)
            .map_err(watcher_error)?;
    }
    for directory in removals {
        if !git_ignore_watch_directories.contains(&directory) {
            let _ = watcher.unwatch(&directory);
        }
    }
    watched_directories.clone_from(desired);
    Ok(additions)
}

fn directories_have_git_changes(
    repository: &Repository,
    directories: &[PathBuf],
) -> HostResult<bool> {
    let Some(workdir) = repository.workdir() else {
        return Ok(false);
    };
    for directory in directories {
        let Ok(relative) = directory.strip_prefix(workdir) else {
            continue;
        };
        let mut options = StatusOptions::new();
        options
            .include_untracked(true)
            .recurse_untracked_dirs(true)
            .include_ignored(false)
            .pathspec(relative.to_string_lossy().replace('\\', "/"));
        if repository
            .statuses(Some(&mut options))
            .map_err(git_query_error)?
            .iter()
            .next()
            .is_some()
        {
            return Ok(true);
        }
    }
    Ok(false)
}
