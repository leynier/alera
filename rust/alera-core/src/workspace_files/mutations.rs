//! Workspace file mutations shared by the desktop bridge and the runtime host,
//! so a save, rename or delete follows the same containment and protection
//! rules whether the checkout is local or on a satellite host.

use std::fs;
use std::path::{Component, Path, PathBuf};

use super::listing::{entry_for_path, WorkspaceExplorerEntry};
use super::{
    content_token, is_protected_workspace_path, modified_millis, relative_string, workspace_root,
    WorkspaceFileError, WorkspaceFileErrorKind,
};

const COPY_SUFFIX: &str = " copy";

/// What a write leaves on disk, enough for a client to refresh its buffer
/// identity without a second read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WrittenWorkspaceFile {
    pub relative_path: String,
    pub content_token: String,
    pub modified_millis: i64,
    pub size: u64,
}

/// Overwrites an existing regular file. With `expected_content_token` and
/// `overwrite_if_changed == false`, a file whose token no longer matches is
/// left untouched and reported as [`WorkspaceFileErrorKind::Conflict`].
pub fn write_workspace_file(
    workspace_path: &str,
    relative_path: &str,
    content: &[u8],
    expected_content_token: Option<&str>,
    overwrite_if_changed: bool,
) -> Result<WrittenWorkspaceFile, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    reject_protected(relative_path)?;
    let path = resolve_existing(&root, relative_path)?;
    let canonical_relative_path = relative_string(&root, &path)?;
    reject_protected(&canonical_relative_path)?;
    let metadata =
        fs::metadata(&path).map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if !metadata.is_file() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    if !overwrite_if_changed {
        if let Some(expected) = expected_content_token {
            if expected != content_token(&metadata) {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::Conflict,
                    relative_path,
                ));
            }
        }
    }
    fs::write(&path, content).map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    let metadata =
        fs::metadata(&path).map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    Ok(WrittenWorkspaceFile {
        relative_path: canonical_relative_path,
        content_token: content_token(&metadata),
        modified_millis: modified_millis(&metadata),
        size: metadata.len(),
    })
}

pub fn create_workspace_file(
    workspace_path: &str,
    parent_relative_path: &str,
    name: &str,
) -> Result<WorkspaceExplorerEntry, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    let parent = resolve_existing(&root, parent_relative_path)?;
    let relative_path = join_relative(parent_relative_path, &sanitize_name(name)?);
    reject_protected(&relative_path)?;
    let path = resolve_new_child(&root, &parent, name)?;
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    created_entry(&root, &path, relative_path)
}

pub fn create_workspace_directory(
    workspace_path: &str,
    parent_relative_path: &str,
    name: &str,
) -> Result<WorkspaceExplorerEntry, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    let parent = resolve_existing(&root, parent_relative_path)?;
    let relative_path = join_relative(parent_relative_path, &sanitize_name(name)?);
    reject_protected(&relative_path)?;
    let path = resolve_new_child(&root, &parent, name)?;
    fs::create_dir(&path).map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    created_entry(&root, &path, relative_path)
}

pub fn rename_workspace_entry(
    workspace_path: &str,
    relative_path: &str,
    new_name: &str,
) -> Result<WorkspaceExplorerEntry, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    reject_protected(relative_path)?;
    let path = resolve_existing(&root, relative_path)?;
    let parent = path.parent().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path)
    })?;
    let new_name = sanitize_name(new_name)?;
    let destination = parent.join(&new_name);
    if destination.exists() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::AlreadyExists,
            new_name,
        ));
    }
    ensure_inside_existing_parent(&root, &destination)?;
    fs::rename(&path, &destination)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    created_entry(&root, &destination, relative_path.to_string())
}

pub fn copy_workspace_entry(
    workspace_path: &str,
    relative_path: &str,
    target_parent_relative_path: &str,
) -> Result<WorkspaceExplorerEntry, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    reject_protected(relative_path)?;
    let source = resolve_existing_no_follow(&root, relative_path)?;
    reject_symlink(&source, relative_path)?;
    let target_parent = resolve_existing(&root, target_parent_relative_path)?;
    let name = source.file_name().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path)
    })?;
    let destination = unique_copy_destination(&target_parent.join(name));
    ensure_not_descendant(&source, &destination)?;
    copy_recursively(&source, &destination)?;
    created_entry(&root, &destination, relative_path.to_string())
}

pub fn move_workspace_entry(
    workspace_path: &str,
    relative_path: &str,
    target_parent_relative_path: &str,
) -> Result<WorkspaceExplorerEntry, WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    reject_protected(relative_path)?;
    let source = resolve_existing_no_follow(&root, relative_path)?;
    reject_symlink(&source, relative_path)?;
    let target_parent = resolve_existing(&root, target_parent_relative_path)?;
    let name = source.file_name().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path)
    })?;
    let destination = target_parent.join(name);
    if destination.exists() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::AlreadyExists,
            destination.to_string_lossy(),
        ));
    }
    ensure_not_descendant(&source, &destination)?;
    fs::rename(&source, &destination)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    created_entry(&root, &destination, relative_path.to_string())
}

/// Deletes a file or directory. `use_trash` moves it to the platform trash
/// when one is available and falls back to a permanent delete otherwise.
pub fn delete_workspace_entry(
    workspace_path: &str,
    relative_path: &str,
    use_trash: bool,
) -> Result<(), WorkspaceFileError> {
    let root = workspace_root(workspace_path)?;
    reject_protected(relative_path)?;
    let path = resolve_existing_no_follow(&root, relative_path)?;
    if use_trash && trash::delete(&path).is_ok() {
        return Ok(());
    }
    let metadata = fs::symlink_metadata(&path)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if metadata.is_dir() && !metadata.file_type().is_symlink() {
        fs::remove_dir_all(&path).map_err(|error| WorkspaceFileError::from_io(error, relative_path))
    } else {
        fs::remove_file(&path).map_err(|error| WorkspaceFileError::from_io(error, relative_path))
    }
}

fn created_entry(
    root: &Path,
    path: &Path,
    relative_path: String,
) -> Result<WorkspaceExplorerEntry, WorkspaceFileError> {
    entry_for_path(root, path)?
        .ok_or_else(|| WorkspaceFileError::new(WorkspaceFileErrorKind::NotFound, relative_path))
}

fn resolve_existing(root: &Path, relative_path: &str) -> Result<PathBuf, WorkspaceFileError> {
    let path = root.join(relative_components(relative_path)?);
    let canonical = fs::canonicalize(&path)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if !canonical.starts_with(root) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    Ok(canonical)
}

fn resolve_existing_no_follow(
    root: &Path,
    relative_path: &str,
) -> Result<PathBuf, WorkspaceFileError> {
    let path = root.join(relative_components(relative_path)?);
    let parent = path.parent().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path)
    })?;
    let canonical_parent = fs::canonicalize(parent)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if !canonical_parent.starts_with(root) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    fs::symlink_metadata(&path)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    Ok(path)
}

fn reject_symlink(path: &Path, relative_path: &str) -> Result<(), WorkspaceFileError> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if metadata.file_type().is_symlink() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    Ok(())
}

fn resolve_new_child(
    root: &Path,
    parent: &Path,
    name: &str,
) -> Result<PathBuf, WorkspaceFileError> {
    let destination = parent.join(sanitize_name(name)?);
    ensure_inside_existing_parent(root, &destination)?;
    Ok(destination)
}

fn ensure_inside_existing_parent(
    root: &Path,
    destination: &Path,
) -> Result<(), WorkspaceFileError> {
    let parent = destination.parent().ok_or_else(|| {
        WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            destination.to_string_lossy(),
        )
    })?;
    let canonical_parent = fs::canonicalize(parent)
        .map_err(|error| WorkspaceFileError::from_io(error, parent.to_string_lossy()))?;
    if !canonical_parent.starts_with(root) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            destination.to_string_lossy(),
        ));
    }
    Ok(())
}

fn relative_components(relative_path: &str) -> Result<PathBuf, WorkspaceFileError> {
    if relative_path.trim().is_empty() {
        return Ok(PathBuf::new());
    }
    let path = Path::new(relative_path);
    if path.is_absolute() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => out.push(part),
            Component::CurDir => {}
            _ => {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::InvalidPath,
                    relative_path,
                ));
            }
        }
    }
    Ok(out)
}

fn sanitize_name(name: &str) -> Result<String, WorkspaceFileError> {
    let trimmed = name.trim();
    if trimmed.is_empty()
        || trimmed.contains('/')
        || trimmed.contains('\\')
        || trimmed == "."
        || trimmed == ".."
    {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            name,
        ));
    }
    Ok(trimmed.to_string())
}

fn reject_protected(relative_path: &str) -> Result<(), WorkspaceFileError> {
    if is_protected_workspace_path(Path::new(relative_path)) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::ProtectedPath,
            relative_path,
        ));
    }
    Ok(())
}

fn join_relative(parent: &str, name: &str) -> String {
    let parent = parent.trim_matches('/');
    if parent.is_empty() {
        name.to_string()
    } else {
        format!("{parent}/{name}")
    }
}

fn unique_copy_destination(initial: &Path) -> PathBuf {
    if !initial.exists() {
        return initial.to_path_buf();
    }
    let parent = initial.parent().unwrap_or_else(|| Path::new(""));
    let stem = initial
        .file_stem()
        .map(|stem| stem.to_string_lossy().to_string())
        .unwrap_or_else(|| "item".to_string());
    let extension = initial
        .extension()
        .map(|extension| format!(".{}", extension.to_string_lossy()))
        .unwrap_or_default();
    let mut index = 1;
    loop {
        let suffix = if index == 1 {
            COPY_SUFFIX.to_string()
        } else {
            format!("{COPY_SUFFIX} {index}")
        };
        let candidate = parent.join(format!("{stem}{suffix}{extension}"));
        if !candidate.exists() {
            return candidate;
        }
        index += 1;
    }
}

fn ensure_not_descendant(source: &Path, destination: &Path) -> Result<(), WorkspaceFileError> {
    let canonical_source = fs::canonicalize(source)
        .map_err(|error| WorkspaceFileError::from_io(error, source.to_string_lossy()))?;
    let canonical_parent = destination
        .parent()
        .and_then(|parent| fs::canonicalize(parent).ok())
        .unwrap_or_else(|| destination.to_path_buf());
    if canonical_parent.starts_with(&canonical_source) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            destination.to_string_lossy(),
        ));
    }
    Ok(())
}

fn copy_recursively(source: &Path, destination: &Path) -> Result<(), WorkspaceFileError> {
    let metadata = fs::symlink_metadata(source)
        .map_err(|error| WorkspaceFileError::from_io(error, source.to_string_lossy()))?;
    if metadata.file_type().is_symlink() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            source.to_string_lossy(),
        ));
    }
    if metadata.is_dir() {
        fs::create_dir(destination)
            .map_err(|error| WorkspaceFileError::from_io(error, destination.to_string_lossy()))?;
        for result in fs::read_dir(source)
            .map_err(|error| WorkspaceFileError::from_io(error, source.to_string_lossy()))?
        {
            let entry = result
                .map_err(|error| WorkspaceFileError::from_io(error, source.to_string_lossy()))?;
            copy_recursively(&entry.path(), &destination.join(entry.file_name()))?;
        }
    } else if metadata.is_file() {
        fs::copy(source, destination)
            .map_err(|error| WorkspaceFileError::from_io(error, source.to_string_lossy()))?;
    } else {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            source.to_string_lossy(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn workspace() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("src/nested")).unwrap();
        fs::create_dir_all(dir.path().join(".git")).unwrap();
        fs::write(dir.path().join("src/main.rs"), "fn main() {}\n").unwrap();
        fs::write(dir.path().join(".git/HEAD"), "ref: refs/heads/main\n").unwrap();
        dir
    }

    #[test]
    fn write_reports_conflicts_and_refreshes_the_token() {
        let dir = workspace();
        let root = dir.path().to_str().unwrap();
        let stale = "0:0";
        let error =
            write_workspace_file(root, "src/main.rs", b"changed", Some(stale), false).unwrap_err();
        assert_eq!(error.kind, WorkspaceFileErrorKind::Conflict);
        assert_eq!(
            fs::read_to_string(dir.path().join("src/main.rs")).unwrap(),
            "fn main() {}\n"
        );
        let written =
            write_workspace_file(root, "src/main.rs", b"changed", Some(stale), true).unwrap();
        assert_eq!(written.relative_path, "src/main.rs");
        assert_eq!(written.size, 7);
        assert_eq!(
            written.content_token,
            content_token(&fs::metadata(dir.path().join("src/main.rs")).unwrap())
        );
        let again = write_workspace_file(
            root,
            "src/main.rs",
            b"again",
            Some(&written.content_token),
            false,
        )
        .unwrap();
        assert_eq!(again.size, 5);
        assert_eq!(
            write_workspace_file(root, ".git/HEAD", b"x", None, true)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::ProtectedPath
        );
        assert_eq!(
            write_workspace_file(root, "src", b"x", None, true)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::Unsupported
        );
        assert_eq!(
            write_workspace_file(root, "../escape", b"x", None, true)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
    }

    #[test]
    fn create_rename_copy_move_and_delete_stay_inside_the_workspace() {
        let dir = workspace();
        let root = dir.path().to_str().unwrap();
        let created = create_workspace_file(root, "src", "lib.rs").unwrap();
        assert_eq!(created.relative_path, "src/lib.rs");
        assert_eq!(
            create_workspace_file(root, "src", "lib.rs")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::AlreadyExists
        );
        assert_eq!(
            create_workspace_file(root, "", ".git").unwrap_err().kind,
            WorkspaceFileErrorKind::ProtectedPath
        );
        assert_eq!(
            create_workspace_directory(root, "src", "../x")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
        let folder = create_workspace_directory(root, "", "docs").unwrap();
        assert_eq!(
            folder.kind,
            super::super::WorkspaceExplorerEntryKind::Directory
        );
        let renamed = rename_workspace_entry(root, "src/lib.rs", "util.rs").unwrap();
        assert_eq!(renamed.relative_path, "src/util.rs");
        assert_eq!(
            rename_workspace_entry(root, "src/util.rs", "main.rs")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::AlreadyExists
        );
        let copied = copy_workspace_entry(root, "src/util.rs", "src").unwrap();
        assert_eq!(copied.relative_path, "src/util copy.rs");
        let moved = move_workspace_entry(root, "src/util copy.rs", "docs").unwrap();
        assert_eq!(moved.relative_path, "docs/util copy.rs");
        assert_eq!(
            move_workspace_entry(root, "src", "src/nested")
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
        delete_workspace_entry(root, "docs", false).unwrap();
        assert!(!dir.path().join("docs").exists());
        assert_eq!(
            delete_workspace_entry(root, ".git", false)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::ProtectedPath
        );
        assert!(dir.path().join(".git/HEAD").exists());
    }
}
