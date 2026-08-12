use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use git2::{Config, ErrorCode, Repository};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::watcher_error;

#[derive(Default)]
pub(super) struct GitIgnoreSources {
    files: HashSet<PathBuf>,
    directories: HashSet<PathBuf>,
}

impl GitIgnoreSources {
    pub(super) fn discover(repository: &Repository) -> HostResult<Self> {
        let mut files = HashSet::new();
        files.insert(repository.path().join("config"));
        files.insert(repository.commondir().join("config"));
        files.insert(repository.commondir().join("config.worktree"));
        for candidate in [
            Config::find_system(),
            Config::find_global(),
            Config::find_xdg(),
        ]
        .into_iter()
        .flatten()
        {
            files.insert(candidate);
        }
        if let Some(home) = dirs::home_dir() {
            files.insert(home.join(".gitconfig"));
            let xdg = std::env::var_os("XDG_CONFIG_HOME")
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(".config"));
            files.insert(xdg.join("git/config"));
            files.insert(xdg.join("git/ignore"));
        }
        let config = repository.config().map_err(git_source_error)?;
        match config.get_path("core.excludesFile") {
            Ok(path) => {
                files.insert(resolve_config_path(repository, path));
            }
            Err(error) if error.code() == ErrorCode::NotFound => {}
            Err(error) => return Err(git_source_error(error)),
        }
        let directories = files
            .iter()
            .filter_map(|path| path.parent())
            .filter(|path| path.is_dir())
            .map(Path::to_path_buf)
            .collect();
        Ok(Self { files, directories })
    }

    pub(super) fn contains(&self, path: &Path) -> bool {
        self.files.contains(path)
            || path
                .file_name()
                .and_then(|name| name.to_str())
                .and_then(|name| name.strip_suffix(".lock"))
                .is_some_and(|name| self.files.contains(&path.with_file_name(name)))
    }
}

pub(super) fn reopen_repository(repository: &Repository) -> HostResult<Repository> {
    let repository_root = repository.workdir().unwrap_or_else(|| repository.path());
    Repository::open(repository_root).map_err(git_source_error)
}

pub(super) fn refresh_git_ignore_source_watches(
    sources: &Arc<RwLock<GitIgnoreSources>>,
    watched: &mut HashSet<PathBuf>,
    workspace_watches: &HashSet<PathBuf>,
    watcher: &mut RecommendedWatcher,
    repository: &Repository,
) -> HostResult<()> {
    let next = GitIgnoreSources::discover(repository)?;
    let additions = next
        .directories
        .difference(watched)
        .cloned()
        .collect::<Vec<_>>();
    for directory in additions {
        if !workspace_watches.contains(&directory) {
            watcher
                .watch(&directory, RecursiveMode::NonRecursive)
                .map_err(watcher_error)?;
        }
        watched.insert(directory);
    }
    *sources
        .write()
        .map_err(|_| HostError::state("Terminal Pulse Git ignore source lock failed."))? = next;
    Ok(())
}

fn resolve_config_path(repository: &Repository, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        return path;
    }
    repository
        .workdir()
        .map_or(path.clone(), |workdir| workdir.join(path))
}

fn git_source_error(error: git2::Error) -> HostError {
    HostError::state(format!(
        "Terminal Pulse could not inspect Git ignore sources: {error}"
    ))
}

#[cfg(test)]
#[path = "terminal_pulse_git_ignore_source_cases.rs"]
mod cases;
