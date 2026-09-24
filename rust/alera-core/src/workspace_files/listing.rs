use std::fs;
use std::path::{Component, Path, PathBuf};

use ignore::WalkBuilder;

use super::{
    is_protected_workspace_path, relative_string, workspace_root, WorkspaceFileError,
    WorkspaceFileErrorKind,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceExplorerEntryKind {
    File,
    Directory,
    Symlink,
    Other,
}

impl WorkspaceExplorerEntryKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::File => "file",
            Self::Directory => "directory",
            Self::Symlink => "symlink",
            Self::Other => "other",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceExplorerEntry {
    pub relative_path: String,
    pub name: String,
    pub kind: WorkspaceExplorerEntryKind,
    pub size: u64,
    pub is_hidden: bool,
    pub has_children_hint: bool,
}

pub fn list_workspace_children(
    workspace_path: &str,
    relative_path: &str,
    hide_ignored: bool,
) -> Result<Vec<WorkspaceExplorerEntry>, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    let directory = resolve_directory(&root, relative_path)?;
    let paths = if hide_ignored {
        ignored_aware_children(&directory)?
    } else {
        read_dir_children(&directory)?
    };

    let mut entries = Vec::with_capacity(paths.len());
    for path in paths {
        if let Some(entry) = entry_for_path(&root, &path)? {
            entries.push(entry);
        }
    }
    entries.sort_by(|left, right| {
        let left_dir = matches!(left.kind, WorkspaceExplorerEntryKind::Directory);
        let right_dir = matches!(right.kind, WorkspaceExplorerEntryKind::Directory);
        right_dir
            .cmp(&left_dir)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
            .then_with(|| left.name.cmp(&right.name))
    });
    Ok(entries)
}

fn resolve_directory(root: &Path, relative_path: &str) -> Result<PathBuf, WorkspaceFileError> {
    if relative_path.is_empty() {
        return Ok(root.to_path_buf());
    }
    let relative = Path::new(relative_path);
    if relative.is_absolute()
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
    let joined = root.join(relative);
    let canonical = fs::canonicalize(&joined)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if !canonical.starts_with(root) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    let metadata = fs::symlink_metadata(&canonical)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    Ok(canonical)
}

fn ignored_aware_children(directory: &Path) -> Result<Vec<PathBuf>, WorkspaceFileError> {
    let mut paths = Vec::new();
    let walker = WalkBuilder::new(directory)
        .max_depth(Some(1))
        .hidden(false)
        .parents(true)
        .require_git(false)
        .follow_links(false)
        .build();
    for result in walker {
        let entry = result.map_err(|error| {
            WorkspaceFileError::new(WorkspaceFileErrorKind::Io, error.to_string())
        })?;
        if entry.path() == directory {
            continue;
        }
        if is_protected_workspace_path(entry.path())
            || entry
                .path()
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| {
                    matches!(name.to_ascii_lowercase().as_str(), ".git" | ".hg" | ".svn")
                })
        {
            continue;
        }
        paths.push(entry.path().to_path_buf());
    }
    Ok(paths)
}

fn read_dir_children(directory: &Path) -> Result<Vec<PathBuf>, WorkspaceFileError> {
    let mut paths = Vec::new();
    for result in fs::read_dir(directory)
        .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?
    {
        let entry = result
            .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?;
        let path = entry.path();
        if path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| {
                matches!(name.to_ascii_lowercase().as_str(), ".git" | ".hg" | ".svn")
            })
        {
            continue;
        }
        paths.push(path);
    }
    Ok(paths)
}

fn entry_for_path(
    root: &Path,
    path: &Path,
) -> Result<Option<WorkspaceExplorerEntry>, WorkspaceFileError> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(_) => return Ok(None),
    };
    let relative_path = relative_string(root, path)?;
    if is_protected_workspace_path(Path::new(&relative_path)) {
        return Ok(None);
    }
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| relative_path.clone());
    let file_type = metadata.file_type();
    let kind = if file_type.is_symlink() {
        WorkspaceExplorerEntryKind::Symlink
    } else if file_type.is_dir() {
        WorkspaceExplorerEntryKind::Directory
    } else if file_type.is_file() {
        WorkspaceExplorerEntryKind::File
    } else {
        WorkspaceExplorerEntryKind::Other
    };
    let has_children_hint = kind == WorkspaceExplorerEntryKind::Directory
        && read_dir_children(path).is_ok_and(|children| !children.is_empty());
    Ok(Some(WorkspaceExplorerEntry {
        is_hidden: name.starts_with('.'),
        size: if file_type.is_file() {
            metadata.len()
        } else {
            0
        },
        relative_path,
        name,
        kind,
        has_children_hint,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn lists_directories_before_files_and_skips_git() {
        let workspace = tempfile::tempdir().unwrap();
        fs::create_dir(workspace.path().join("src")).unwrap();
        fs::create_dir(workspace.path().join(".git")).unwrap();
        fs::write(workspace.path().join("readme.md"), "hi").unwrap();
        fs::write(workspace.path().join("src/main.rs"), "fn main() {}").unwrap();

        let entries =
            list_workspace_children(&workspace.path().to_string_lossy(), "", true).unwrap();
        let names = entries
            .iter()
            .map(|entry| entry.name.as_str())
            .collect::<Vec<_>>();
        assert_eq!(names, ["src", "readme.md"]);
        assert_eq!(entries[0].kind, WorkspaceExplorerEntryKind::Directory);
        assert!(entries[0].has_children_hint);
        assert_eq!(entries[1].kind, WorkspaceExplorerEntryKind::File);
    }

    #[test]
    fn rejects_parent_traversal() {
        let workspace = tempfile::tempdir().unwrap();
        let error =
            list_workspace_children(&workspace.path().to_string_lossy(), "..", true).unwrap_err();
        assert_eq!(error.kind, WorkspaceFileErrorKind::InvalidPath);
    }

    #[test]
    fn hides_gitignored_children() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join(".gitignore"), "secret.txt\n").unwrap();
        fs::write(workspace.path().join("visible.txt"), "ok").unwrap();
        fs::write(workspace.path().join("secret.txt"), "no").unwrap();
        git2::Repository::init(workspace.path()).unwrap();

        let hidden = list_workspace_children(&workspace.path().to_string_lossy(), "", true)
            .unwrap()
            .into_iter()
            .map(|entry| entry.name)
            .collect::<Vec<_>>();
        assert!(hidden.contains(&"visible.txt".to_string()));
        assert!(!hidden.contains(&"secret.txt".to_string()));

        let shown = list_workspace_children(&workspace.path().to_string_lossy(), "", false)
            .unwrap()
            .into_iter()
            .map(|entry| entry.name)
            .collect::<Vec<_>>();
        assert!(shown.contains(&"secret.txt".to_string()));
    }
}
