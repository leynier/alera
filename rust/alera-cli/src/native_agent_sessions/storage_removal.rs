use std::fs;
use std::io::{ErrorKind, Read};
use std::path::{Path, PathBuf};

use super::session_id_rules::is_storage_entry_name;
use super::CleanupFailure;

/// A directory every removal must stay inside, compared by canonical path.
///
/// Opening a root canonicalizes it, so a root that is itself a symlink (a CCS
/// instance's `projects` pointing into the shared store) is checked against
/// the store it resolves to. Each target's *parent* is canonicalized and must
/// stay inside; the target itself is never followed, so a symlinked entry is
/// unlinked rather than having its destination deleted.
pub(super) struct StorageRoot {
    canonical: PathBuf,
}

impl StorageRoot {
    pub fn open(path: &Path) -> Result<Option<Self>, CleanupFailure> {
        match dunce::canonicalize(path) {
            Ok(canonical) if canonical.is_dir() => Ok(Some(Self { canonical })),
            Ok(_) => Ok(None),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
            Err(error) => Err(CleanupFailure::filesystem(error, path)),
        }
    }

    pub fn path(&self) -> &Path {
        &self.canonical
    }

    pub fn entry(&self, name: &str) -> PathBuf {
        self.canonical.join(name)
    }

    /// Names of the entries directly inside `directory` that `keep` accepts.
    pub fn entry_names(
        &self,
        directory: &Path,
        keep: impl Fn(&str, &Path) -> bool,
    ) -> Result<Vec<String>, CleanupFailure> {
        let entries = match fs::read_dir(directory) {
            Ok(entries) => entries,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(CleanupFailure::filesystem(error, directory)),
        };
        let mut names = Vec::new();
        for entry in entries.flatten() {
            let Ok(name) = entry.file_name().into_string() else {
                continue;
            };
            if is_storage_entry_name(&name) && keep(&name, &entry.path()) {
                names.push(name);
            }
        }
        names.sort();
        Ok(names)
    }

    /// Subdirectories directly inside the root.
    pub fn child_directories(&self) -> Result<Vec<PathBuf>, CleanupFailure> {
        Ok(self
            .entry_names(&self.canonical, |_, path| path.is_dir())?
            .into_iter()
            .map(|name| self.canonical.join(name))
            .collect())
    }

    /// Removes `target`, reporting whether anything was there.
    pub fn remove(&self, target: &Path) -> Result<bool, CleanupFailure> {
        let refused = || {
            CleanupFailure::new(
                "refused_outside_storage",
                format!(
                    "refused to remove {} outside agent storage",
                    target.display()
                ),
            )
        };
        let name = target
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| is_storage_entry_name(name))
            .ok_or_else(refused)?;
        let parent = target.parent().ok_or_else(refused)?;
        let parent = match dunce::canonicalize(parent) {
            Ok(parent) => parent,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(false),
            Err(error) => return Err(CleanupFailure::filesystem(error, parent)),
        };
        if !parent.starts_with(&self.canonical) {
            return Err(refused());
        }
        let resolved = parent.join(name);
        let metadata = match fs::symlink_metadata(&resolved) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(false),
            Err(error) => return Err(CleanupFailure::filesystem(error, &resolved)),
        };
        let removal = if metadata.is_dir() {
            fs::remove_dir_all(&resolved)
        } else {
            fs::remove_file(&resolved)
        };
        match removal {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
            Err(error) => Err(CleanupFailure::filesystem(error, &resolved)),
        }
    }

    /// Removes `directory` only when nothing is left in it.
    pub fn remove_if_empty(&self, directory: &Path) {
        let is_empty = fs::read_dir(directory).is_ok_and(|mut entries| entries.next().is_none());
        if is_empty && directory.starts_with(&self.canonical) && directory != self.canonical {
            let _ = fs::remove_dir(directory);
        }
    }
}

/// The start of a small metadata file, bounded so a corrupt or huge file
/// cannot stall the cleanup.
pub(super) fn read_head(path: &Path, limit: u64) -> Option<String> {
    let file = fs::File::open(path).ok()?;
    let mut bytes = Vec::new();
    file.take(limit).read_to_end(&mut bytes).ok()?;
    Some(String::from_utf8_lossy(&bytes).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn removal_stays_inside_the_canonical_root() {
        let temp = tempfile::tempdir().unwrap();
        let root_path = temp.path().join("root");
        let outside = temp.path().join("outside");
        fs::create_dir_all(root_path.join("session")).unwrap();
        fs::create_dir_all(&outside).unwrap();
        fs::write(outside.join("keep.txt"), "x").unwrap();
        let root = StorageRoot::open(&root_path).unwrap().unwrap();

        assert!(root.remove(&root_path.join("session")).unwrap());
        assert!(!root.remove(&root_path.join("session")).unwrap());
        assert!(root.remove(&outside.join("keep.txt")).is_err());
        assert!(root.remove(&root_path.join("..")).is_err());
        assert!(outside.join("keep.txt").exists());
    }

    #[cfg(unix)]
    #[test]
    fn a_symlinked_entry_is_unlinked_without_touching_its_target() {
        let temp = tempfile::tempdir().unwrap();
        let root_path = temp.path().join("root");
        let outside = temp.path().join("outside");
        fs::create_dir_all(&root_path).unwrap();
        fs::create_dir_all(&outside).unwrap();
        fs::write(outside.join("keep.txt"), "x").unwrap();
        std::os::unix::fs::symlink(&outside, root_path.join("link")).unwrap();
        std::os::unix::fs::symlink(&outside, root_path.join("escape")).unwrap();
        let root = StorageRoot::open(&root_path).unwrap().unwrap();

        assert!(root
            .remove(&root_path.join("escape").join("keep.txt"))
            .is_err());
        assert!(root.remove(&root_path.join("link")).unwrap());
        assert!(outside.join("keep.txt").exists());
    }
}
