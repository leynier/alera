use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

use super::{
    is_protected_workspace_path, workspace_root, WorkspaceFileError, WorkspaceFileErrorKind,
};

/// A workspace-relative path that cannot escape the workspace by traversal or
/// symlink. Missing files are allowed so git can still diff a deletion.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContainedWorkspacePath {
    pub relative_path: String,
    pub absolute_path: PathBuf,
}

pub fn contained_workspace_relative_path(
    workspace_path: &str,
    relative_path: &str,
) -> Result<ContainedWorkspacePath, WorkspaceFileError> {
    if relative_path.is_empty() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }
    let root = workspace_root(workspace_path)?;
    let relative = Path::new(relative_path);
    // Absolute and rooted paths must not reach Path::join: they replace the
    // workspace root (`/etc/passwd` joined onto a root is `/etc/passwd`).
    if relative.is_absolute()
        || relative.has_root()
        || relative
            .components()
            .any(|component| !matches!(component, Component::Normal(_) | Component::CurDir))
        || is_protected_workspace_path(relative)
    {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }

    let mut current = root.clone();
    let mut parts = Vec::new();
    let mut missing = false;
    for component in relative.components() {
        let Component::Normal(name) = component else {
            continue;
        };
        parts.push(name.to_string_lossy().into_owned());
        current.push(name);
        if missing {
            continue;
        }
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::InvalidPath,
                    relative_path,
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => missing = true,
            Err(error) => {
                return Err(WorkspaceFileError::from_io(error, relative_path));
            }
        }
    }
    if parts.is_empty() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }
    if !current.starts_with(&root) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    if !missing {
        match fs::canonicalize(&current) {
            Ok(canonical) if canonical.starts_with(&root) => {}
            Ok(_) => {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::OutsideWorkspace,
                    relative_path,
                ));
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(WorkspaceFileError::from_io(error, relative_path));
            }
        }
    }
    Ok(ContainedWorkspacePath {
        relative_path: parts.join("/"),
        absolute_path: current,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn rejects_absolute_and_parent_paths() {
        let workspace = tempfile::tempdir().unwrap();
        let root = workspace.path().to_string_lossy();
        assert_eq!(
            contained_workspace_relative_path(&root, "/etc/passwd")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
        assert_eq!(
            contained_workspace_relative_path(&root, "../secret")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
    }

    #[test]
    fn canonicalize_keeps_existing_in_tree_files() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join("inside.txt"), "hello").unwrap();
        let contained =
            contained_workspace_relative_path(&workspace.path().to_string_lossy(), "inside.txt")
                .unwrap();
        assert_eq!(contained.relative_path, "inside.txt");
        assert!(contained.absolute_path.ends_with("inside.txt"));
    }

    #[test]
    fn allows_missing_in_tree_files() {
        let workspace = tempfile::tempdir().unwrap();
        let contained =
            contained_workspace_relative_path(&workspace.path().to_string_lossy(), "gone.txt")
                .unwrap();
        assert_eq!(contained.relative_path, "gone.txt");
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symlink_to_an_outside_file() {
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let secret = outside.path().join("secret.txt");
        fs::write(&secret, "secret").unwrap();
        std::os::unix::fs::symlink(&secret, workspace.path().join("link.txt")).unwrap();
        assert_eq!(
            contained_workspace_relative_path(&workspace.path().to_string_lossy(), "link.txt")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
    }
}
