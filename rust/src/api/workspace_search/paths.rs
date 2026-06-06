use std::fs;
use std::path::{Component, Path, PathBuf};
use std::time::UNIX_EPOCH;

use super::{WorkspaceSearchError, WorkspaceSearchErrorKind, PROTECTED_NAMES};

pub(super) fn safe_regular_file_metadata(
    root: &Path,
    path: &Path,
    relative_path: &str,
) -> Result<fs::Metadata, WorkspaceSearchError> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| WorkspaceSearchError::from_io(error, relative_path))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    let canonical = fs::canonicalize(path)
        .map_err(|error| WorkspaceSearchError::from_io(error, relative_path))?;
    if !canonical.starts_with(root) {
        return Err(WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    Ok(metadata)
}

pub(super) fn resolve_replace_file(
    root: &Path,
    relative_path: &str,
) -> Result<(PathBuf, fs::Metadata), WorkspaceSearchError> {
    let path = root.join(relative_path);
    if is_protected(&path) {
        return Err(WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    let metadata = safe_regular_file_metadata(root, &path, relative_path)?;
    Ok((path, metadata))
}

pub(super) fn should_walk_entry(root: &Path, path: &Path) -> bool {
    path == root || !is_protected(path)
}

pub(super) fn workspace_root(path: &str) -> Result<PathBuf, WorkspaceSearchError> {
    let root = PathBuf::from(path);
    let canonical =
        fs::canonicalize(&root).map_err(|error| WorkspaceSearchError::from_io(error, path))?;
    if !canonical.is_dir() {
        return Err(WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::InvalidPath,
            path,
        ));
    }
    Ok(canonical)
}

pub(super) fn relative_string(root: &Path, path: &Path) -> Option<String> {
    path.strip_prefix(root)
        .ok()
        .map(|path| path.to_string_lossy().replace('\\', "/"))
}

pub(super) fn is_protected(path: &Path) -> bool {
    path.components().any(|component| match component {
        Component::Normal(name) => PROTECTED_NAMES.contains(&name.to_string_lossy().as_ref()),
        _ => false,
    })
}

pub(super) fn content_token(metadata: &fs::Metadata) -> String {
    let modified = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis())
        .unwrap_or(0);
    format!("{}:{modified}", metadata.len())
}
