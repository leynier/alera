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
                self.repository = match reopen_repository(&self.repository) {
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
                ) {
                    self.fail(error);
                    return;
                }
                let additions = match reconcile_watch_directories(
                    &mut self.watcher,
                    &self.repository,
                    &self.root,
                    &mut self.watched_directories,
                ) {
                    Ok(additions) => additions,
                    Err(error) => {
                        self.fail(error);
                        return;
                    }
                };
                match directories_have_git_changes(&self.repository, &additions) {
                    Ok(true) => self.record_change(),
                    Ok(false) => {}
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

fn reconcile_watch_directories(
    watcher: &mut RecommendedWatcher,
    repository: &Repository,
    root: &Path,
    watched_directories: &mut HashSet<PathBuf>,
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
        let _ = watcher.unwatch(&directory);
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
