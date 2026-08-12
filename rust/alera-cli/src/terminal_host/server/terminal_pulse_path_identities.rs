use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use git2::Repository;
use notify::event::{ModifyKind, RenameMode};
use notify::{Event, EventKind};

use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum PathIdentity {
    File,
    Directory,
}

pub(super) struct PathIdentityCache {
    root: PathBuf,
    directories: HashSet<String>,
    watch_directories: HashSet<PathBuf>,
}

impl PathIdentityCache {
    pub(super) fn scan(root: &Path, repository: &Repository) -> HostResult<Self> {
        Self::scan_with_cancellation(root, repository, &AtomicBool::new(false))
    }

    pub(super) fn scan_with_cancellation(
        root: &Path,
        repository: &Repository,
        cancelled: &AtomicBool,
    ) -> HostResult<Self> {
        ensure_scan_active(cancelled)?;
        let tracked_directories = tracked_parent_directories(root, repository)?;
        let mut cache = Self {
            root: root.to_path_buf(),
            directories: HashSet::new(),
            watch_directories: HashSet::from([root.to_path_buf()]),
        };
        let mut pending = vec![root.to_path_buf()];
        while let Some(directory) = pending.pop() {
            ensure_scan_active(cancelled)?;
            let entries = std::fs::read_dir(&directory).map_err(identity_scan_error)?;
            for entry in entries {
                ensure_scan_active(cancelled)?;
                let entry = entry.map_err(identity_scan_error)?;
                if entry.file_name() == ".git" {
                    continue;
                }
                let file_type = entry.file_type().map_err(identity_scan_error)?;
                if file_type.is_dir() && !file_type.is_symlink() {
                    let path = entry.path();
                    cache.insert_directory(&path);
                    if tracked_directories.contains(&path)
                        || !directory_is_ignored(repository, &path)?
                    {
                        cache.watch_directories.insert(path.clone());
                        pending.push(path);
                    }
                }
            }
        }
        Ok(cache)
    }

    pub(super) fn watch_directories(&self) -> &HashSet<PathBuf> {
        &self.watch_directories
    }

    pub(super) fn identity_for_event(&self, kind: &EventKind, path: &Path) -> PathIdentity {
        match kind {
            EventKind::Create(notify::event::CreateKind::Folder)
            | EventKind::Remove(notify::event::RemoveKind::Folder) => PathIdentity::Directory,
            EventKind::Create(notify::event::CreateKind::File)
            | EventKind::Remove(notify::event::RemoveKind::File) => PathIdentity::File,
            _ => std::fs::symlink_metadata(path)
                .ok()
                .filter(|metadata| !metadata.file_type().is_symlink())
                .map_or_else(
                    || {
                        if self.is_directory(path) {
                            PathIdentity::Directory
                        } else {
                            PathIdentity::File
                        }
                    },
                    |metadata| {
                        if metadata.is_dir() {
                            PathIdentity::Directory
                        } else {
                            PathIdentity::File
                        }
                    },
                ),
        }
    }

    pub(super) fn apply_event(&mut self, event: &Event, identities: &[PathIdentity]) {
        match event.kind {
            EventKind::Remove(_) => {
                for path in &event.paths {
                    self.remove_path(path);
                }
            }
            EventKind::Modify(ModifyKind::Name(RenameMode::Both)) if event.paths.len() >= 2 => {
                self.rename_path(&event.paths[0], &event.paths[1], identities[0]);
            }
            EventKind::Modify(ModifyKind::Name(RenameMode::From)) => {
                for path in &event.paths {
                    self.remove_path(path);
                }
            }
            EventKind::Modify(ModifyKind::Name(RenameMode::Any)) => {
                for (path, identity) in event.paths.iter().zip(identities) {
                    // macOS reports each rename side as Any, so a missing path
                    // is the source side and must leave the identity cache.
                    if is_missing_ambiguous_rename(&event.kind, path) {
                        self.remove_path(path);
                    } else if *identity == PathIdentity::Directory {
                        self.insert_directory(path);
                    } else {
                        self.remove_path(path);
                    }
                }
            }
            _ => {
                for (path, identity) in event.paths.iter().zip(identities) {
                    if *identity == PathIdentity::Directory {
                        self.insert_directory(path);
                    } else {
                        self.remove_path(path);
                    }
                }
            }
        }
    }

    fn rename_path(&mut self, from: &Path, to: &Path, identity: PathIdentity) {
        if identity != PathIdentity::Directory {
            self.remove_path(from);
            self.remove_path(to);
            return;
        }
        let Some(from_key) = self.key(from) else {
            return;
        };
        let Some(to_key) = self.key(to) else {
            return;
        };
        let descendants = self
            .directories
            .iter()
            .filter_map(|key| {
                path_key_suffix(key, &from_key).map(|suffix| format!("{to_key}{suffix}"))
            })
            .collect::<Vec<_>>();
        self.remove_path(from);
        self.remove_path(to);
        self.directories.extend(descendants);
        self.directories.insert(to_key);
    }

    fn insert_directory(&mut self, path: &Path) {
        if let Some(key) = self.key(path) {
            self.directories.insert(key);
        }
    }

    fn remove_path(&mut self, path: &Path) {
        let Some(key) = self.key(path) else {
            return;
        };
        self.directories
            .retain(|candidate| path_key_suffix(candidate, &key).is_none());
    }

    fn is_directory(&self, path: &Path) -> bool {
        self.key(path)
            .is_some_and(|key| self.directories.contains(&key))
    }

    fn key(&self, path: &Path) -> Option<String> {
        let relative = path.strip_prefix(&self.root).ok()?;
        let key = relative.to_string_lossy().replace('\\', "/");
        #[cfg(windows)]
        let key = key.to_lowercase();
        Some(key)
    }

    #[cfg(test)]
    pub(super) fn contains_directory(&self, path: &Path) -> bool {
        self.is_directory(path)
    }
}

fn ensure_scan_active(cancelled: &AtomicBool) -> HostResult<()> {
    if cancelled.load(Ordering::Acquire) {
        return Err(HostError::state(
            "Terminal Pulse watcher setup was cancelled.",
        ));
    }
    Ok(())
}

pub(super) fn is_missing_ambiguous_rename(kind: &EventKind, path: &Path) -> bool {
    matches!(kind, EventKind::Modify(ModifyKind::Name(RenameMode::Any)))
        && matches!(
            std::fs::symlink_metadata(path),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound
        )
}

fn directory_is_ignored(repository: &Repository, path: &Path) -> HostResult<bool> {
    let Some(workdir) = repository.workdir() else {
        return Ok(false);
    };
    let Ok(relative) = path.strip_prefix(workdir) else {
        return Ok(false);
    };
    repository.status_should_ignore(relative).map_err(|error| {
        HostError::state(format!(
            "Terminal Pulse could not inspect Git ignore rules: {error}"
        ))
    })
}

fn tracked_parent_directories(
    root: &Path,
    repository: &Repository,
) -> HostResult<HashSet<PathBuf>> {
    let Some(workdir) = repository.workdir() else {
        return Ok(HashSet::new());
    };
    let index = repository.index().map_err(|error| {
        HostError::state(format!(
            "Terminal Pulse could not inspect tracked paths: {error}"
        ))
    })?;
    let mut directories = HashSet::new();
    for entry in index.iter() {
        let Some(relative) = index_entry_path(&entry.path) else {
            continue;
        };
        let absolute = workdir.join(relative);
        let mut parent = absolute.parent();
        while let Some(directory) = parent.filter(|directory| directory.starts_with(root)) {
            directories.insert(directory.to_path_buf());
            if directory == root {
                break;
            }
            parent = directory.parent();
        }
    }
    Ok(directories)
}

#[cfg(unix)]
fn index_entry_path(bytes: &[u8]) -> Option<PathBuf> {
    use std::os::unix::ffi::OsStringExt;

    Some(PathBuf::from(std::ffi::OsString::from_vec(bytes.to_vec())))
}

#[cfg(not(unix))]
fn index_entry_path(bytes: &[u8]) -> Option<PathBuf> {
    std::str::from_utf8(bytes).ok().map(PathBuf::from)
}

fn path_key_suffix<'a>(candidate: &'a str, prefix: &str) -> Option<&'a str> {
    if candidate == prefix {
        return Some("");
    }
    candidate
        .strip_prefix(prefix)
        .filter(|suffix| suffix.starts_with('/'))
}

fn identity_scan_error(error: std::io::Error) -> HostError {
    HostError::state(format!(
        "Terminal Pulse could not inspect workspace directories: {error}"
    ))
}
