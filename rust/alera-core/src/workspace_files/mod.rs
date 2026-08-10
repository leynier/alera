use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Component, Path, PathBuf};

use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptions, OpenOptionsFollowExt};
use cap_std::{ambient_authority, fs::Dir};
use same_file::Handle;

mod mime;
mod prompts;
mod quick_open;

use mime::{mime_type_for_path, path_has_binary_preview_mime};

pub use prompts::{list_codex_saved_prompts, CodexSavedPrompt, CodexSavedPromptScope};
pub use quick_open::{
    search_workspace_quick_open_session, start_workspace_quick_open_session,
    start_workspace_quick_open_session_without_symlinks, stop_workspace_quick_open_session,
    WorkspaceQuickOpenMatch, WorkspaceQuickOpenSession,
};

pub const MAX_REMOTE_READ_BYTES: u64 = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceFileErrorKind {
    InvalidPath,
    OutsideWorkspace,
    NotFound,
    Unsupported,
    Io,
}

#[derive(Debug)]
pub struct WorkspaceFileError {
    pub kind: WorkspaceFileErrorKind,
    pub context: String,
}

impl std::fmt::Display for WorkspaceFileError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}", self.context)
    }
}

impl std::error::Error for WorkspaceFileError {}

impl WorkspaceFileError {
    pub(super) fn new(kind: WorkspaceFileErrorKind, context: impl Into<String>) -> Self {
        Self {
            kind,
            context: context.into(),
        }
    }

    pub(super) fn from_io(error: std::io::Error, context: impl Into<String>) -> Self {
        let kind = if error.kind() == std::io::ErrorKind::NotFound {
            WorkspaceFileErrorKind::NotFound
        } else {
            WorkspaceFileErrorKind::Io
        };
        Self::new(kind, format!("{}: {error}", context.into()))
    }
}

#[derive(Debug, Clone)]
pub struct WorkspaceFileRange {
    pub bytes: Vec<u8>,
    pub offset: u64,
    pub next_offset: u64,
    pub total_bytes: u64,
    pub mime_type: String,
    pub is_text: bool,
}

pub struct WorkspaceFileRoot {
    directory: Dir,
    canonical_path: PathBuf,
}

impl WorkspaceFileRoot {
    pub fn canonical_path(&self) -> &Path {
        &self.canonical_path
    }
}

pub fn open_workspace_file_root(
    workspace_path: &str,
) -> Result<WorkspaceFileRoot, WorkspaceFileError> {
    let directory = Dir::open_ambient_dir(workspace_path, ambient_authority())
        .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))?;
    let canonical_path = fs::canonicalize(workspace_path)
        .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))?;
    // Authorization uses this path, so prove it still names the held directory.
    let opened_handle = Handle::from_file(
        directory
            .try_clone()
            .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))?
            .into_std_file(),
    )
    .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))?;
    let canonical_handle = Handle::from_path(&canonical_path)
        .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))?;
    if opened_handle != canonical_handle {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            format!("Workspace root changed while it was being opened: {workspace_path}"),
        ));
    }
    Ok(WorkspaceFileRoot {
        directory,
        canonical_path,
    })
}

pub fn read_workspace_file_range(
    workspace_path: &str,
    relative_path: &str,
    offset: u64,
    length: u64,
) -> Result<WorkspaceFileRange, WorkspaceFileError> {
    let root = open_workspace_file_root(workspace_path)?;
    read_workspace_file_range_from_root(&root, relative_path, offset, length)
}

pub fn read_workspace_file_range_from_root(
    root: &WorkspaceFileRoot,
    relative_path: &str,
    offset: u64,
    length: u64,
) -> Result<WorkspaceFileRange, WorkspaceFileError> {
    if length == 0 || length > MAX_REMOTE_READ_BYTES {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            format!("Read length must be between 1 and {MAX_REMOTE_READ_BYTES} bytes"),
        ));
    }
    let (mut file, normalized_relative) =
        open_workspace_file_without_symlinks(root, relative_path)?;
    let metadata = file
        .metadata()
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if !metadata.is_file() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            format!("Workspace path is not a file: {relative_path}"),
        ));
    }
    if offset > metadata.len() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            format!("Read offset exceeds file length: {relative_path}"),
        ));
    }
    let count = length.min(metadata.len().saturating_sub(offset));
    let is_text = file_is_probably_utf8(
        &mut file,
        &normalized_relative,
        metadata.len(),
        relative_path,
    )?;
    file.seek(SeekFrom::Start(offset))
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    let mut bytes = vec![0_u8; usize::try_from(count).unwrap_or(0)];
    file.read_exact(&mut bytes)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    let mime_type = mime_type_for_path(&normalized_relative, is_text).to_string();
    Ok(WorkspaceFileRange {
        next_offset: offset.saturating_add(count),
        bytes,
        offset,
        total_bytes: metadata.len(),
        mime_type,
        is_text,
    })
}

fn open_workspace_file_without_symlinks(
    root: &WorkspaceFileRoot,
    relative_path: &str,
) -> Result<(fs::File, PathBuf), WorkspaceFileError> {
    let relative = Path::new(relative_path);
    if relative.as_os_str().is_empty()
        || relative.is_absolute()
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
    let components = relative
        .components()
        .filter_map(|component| match component {
            Component::Normal(value) => Some(value.to_os_string()),
            Component::CurDir => None,
            _ => None,
        })
        .collect::<Vec<_>>();
    let Some((file_name, directory_components)) = components.split_last() else {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    };
    let mut normalized_relative = PathBuf::new();
    for component in &components {
        normalized_relative.push(component);
    }
    let mut directory = root.directory.try_clone().map_err(|error| {
        WorkspaceFileError::from_io(error, root.canonical_path.display().to_string())
    })?;
    for component in directory_components {
        reject_workspace_symlink(&directory, component, relative_path)?;
        directory = directory
            .open_dir_nofollow(component)
            .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    }
    reject_workspace_symlink(&directory, file_name, relative_path)?;
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No);
    let file = directory
        .open_with(file_name, &options)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?
        .into_std();
    Ok((file, normalized_relative))
}

fn reject_workspace_symlink(
    directory: &Dir,
    component: &std::ffi::OsStr,
    context: &str,
) -> Result<(), WorkspaceFileError> {
    let metadata = directory
        .symlink_metadata(component)
        .map_err(|error| WorkspaceFileError::from_io(error, context))?;
    if metadata.file_type().is_symlink() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            context,
        ));
    }
    Ok(())
}

fn file_is_probably_utf8(
    file: &mut fs::File,
    path: &Path,
    total_bytes: u64,
    context: &str,
) -> Result<bool, WorkspaceFileError> {
    if path_has_binary_preview_mime(path) {
        return Ok(false);
    }
    let sample_bytes = total_bytes.min(MAX_REMOTE_READ_BYTES);
    let mut sample = vec![0_u8; usize::try_from(sample_bytes).unwrap_or(0)];
    file.read_exact(&mut sample)
        .map_err(|error| WorkspaceFileError::from_io(error, context))?;
    Ok(range_is_probably_utf8(&sample, sample_bytes < total_bytes))
}

fn range_is_probably_utf8(bytes: &[u8], allow_incomplete_suffix: bool) -> bool {
    if bytes.contains(&0) {
        return false;
    }
    match std::str::from_utf8(bytes) {
        Ok(_) => true,
        Err(error) => allow_incomplete_suffix && error.error_len().is_none(),
    }
}

pub(super) fn workspace_root(value: &str) -> Result<PathBuf, WorkspaceFileError> {
    let path = PathBuf::from(value);
    let root =
        fs::canonicalize(&path).map_err(|error| WorkspaceFileError::from_io(error, value))?;
    if !root.is_dir() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            format!("Workspace root is not a directory: {value}"),
        ));
    }
    Ok(root)
}

pub(super) fn relative_string(root: &Path, path: &Path) -> Result<String, WorkspaceFileError> {
    let relative = path.strip_prefix(root).map_err(|_| {
        WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            path.display().to_string(),
        )
    })?;
    let mut components = Vec::new();
    for component in relative.components() {
        match component {
            Component::Normal(value) => components.push(value.to_string_lossy().into_owned()),
            Component::CurDir => {}
            _ => {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::OutsideWorkspace,
                    path.display().to_string(),
                ));
            }
        }
    }
    Ok(components.join("/"))
}

pub fn is_protected_workspace_path(path: &Path) -> bool {
    path.components().any(|component| {
        matches!(component, Component::Normal(value) if value.to_str().is_some_and(|value| {
            matches!(value.to_ascii_lowercase().as_str(), ".git" | ".hg" | ".svn")
        }))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_read_rejects_traversal_and_symlink_escape() {
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join("inside.txt"), "hello").unwrap();
        fs::create_dir(workspace.path().join(".git")).unwrap();
        fs::write(workspace.path().join(".git/config"), "secret").unwrap();
        fs::write(outside.path().join("secret.txt"), "secret").unwrap();
        let root = workspace.path().to_string_lossy();
        assert!(read_workspace_file_range(&root, "../secret.txt", 0, 10).is_err());
        assert_eq!(
            read_workspace_file_range(&root, ".git/config", 0, 10)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
        assert!(is_protected_workspace_path(Path::new(".GIT/config")));
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(
                workspace.path().join(".git/config"),
                workspace.path().join("config-link"),
            )
            .unwrap();
            assert_eq!(
                read_workspace_file_range(&root, "config-link", 0, 10)
                    .unwrap_err()
                    .kind,
                WorkspaceFileErrorKind::InvalidPath
            );
            std::os::unix::fs::symlink(
                workspace.path().join(".git"),
                workspace.path().join("metadata-link"),
            )
            .unwrap();
            assert_eq!(
                read_workspace_file_range(&root, "metadata-link/config", 0, 10)
                    .unwrap_err()
                    .kind,
                WorkspaceFileErrorKind::InvalidPath
            );
            std::os::unix::fs::symlink(
                outside.path().join("secret.txt"),
                workspace.path().join("link.txt"),
            )
            .unwrap();
            assert!(read_workspace_file_range(&root, "link.txt", 0, 10).is_err());
        }
        let result = read_workspace_file_range(&root, "inside.txt", 1, 3).unwrap();
        assert_eq!(result.bytes, b"ell");
        assert_eq!(result.next_offset, 4);
    }

    #[cfg(unix)]
    #[test]
    fn opened_root_stays_pinned_when_workspace_path_is_replaced() {
        let parent = tempfile::tempdir().unwrap();
        let workspace = parent.path().join("workspace");
        let moved_workspace = parent.path().join("workspace-moved");
        let replacement = parent.path().join("replacement");
        fs::create_dir(&workspace).unwrap();
        fs::create_dir(&replacement).unwrap();
        fs::write(workspace.join("inside.txt"), "inside").unwrap();
        fs::write(replacement.join("config"), "secret").unwrap();
        let root = open_workspace_file_root(&workspace.to_string_lossy()).unwrap();

        fs::rename(&workspace, &moved_workspace).unwrap();
        std::os::unix::fs::symlink(&replacement, &workspace).unwrap();

        let inside = read_workspace_file_range_from_root(&root, "inside.txt", 0, 10).unwrap();
        assert_eq!(inside.bytes, b"inside");
        assert!(read_workspace_file_range_from_root(&root, "config", 0, 10).is_err());
    }

    #[test]
    fn ranged_text_detection_allows_split_utf8_code_points() {
        let workspace = tempfile::tempdir().unwrap();
        let path = workspace.path().join("utf8.txt");
        fs::write(&path, "aéz").unwrap();
        let root = workspace.path().to_string_lossy();

        let leading_half = read_workspace_file_range(&root, "utf8.txt", 0, 2).unwrap();
        let trailing_half = read_workspace_file_range(&root, "utf8.txt", 2, 2).unwrap();

        assert!(leading_half.is_text);
        assert!(trailing_half.is_text);
    }

    #[test]
    fn ranged_text_detection_rejects_invalid_interior_utf8() {
        assert!(!range_is_probably_utf8(&[b'a', 0xff, b'z'], false));
        assert!(!range_is_probably_utf8(&[b'a', 0, b'z'], false));
        assert!(!range_is_probably_utf8(&[b'a', 0xc3], false));
        assert!(!range_is_probably_utf8(&[0x80, b'a'], false));
        assert!(range_is_probably_utf8(&[b'a', 0xc3], true));
    }

    #[test]
    fn ranged_text_detection_rejects_incomplete_utf8_at_eof() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join("broken.bin"), [b'a', 0xc3]).unwrap();
        fs::write(workspace.path().join("invalid-prefix.bin"), [0x80, b'a']).unwrap();
        let root = workspace.path().to_string_lossy();

        let result = read_workspace_file_range(&root, "broken.bin", 0, 2).unwrap();
        assert!(!result.is_text);
        assert_eq!(result.mime_type, "application/octet-stream");

        let result = read_workspace_file_range(&root, "invalid-prefix.bin", 0, 2).unwrap();
        assert!(!result.is_text);
        assert_eq!(result.mime_type, "application/octet-stream");
    }

    #[cfg(unix)]
    #[test]
    fn relative_paths_preserve_literal_backslashes_in_file_names() {
        let workspace = tempfile::tempdir().unwrap();
        let root = fs::canonicalize(workspace.path()).unwrap();
        let literal = root.join("foo\\bar.txt");
        fs::write(&literal, b"literal").unwrap();
        let canonical = fs::canonicalize(&literal).unwrap();

        assert_eq!(relative_string(&root, &canonical).unwrap(), "foo\\bar.txt");
        let range =
            read_workspace_file_range(&root.to_string_lossy(), "foo\\bar.txt", 0, 7).unwrap();
        assert_eq!(range.bytes, b"literal");
    }

    #[test]
    fn ranged_reads_keep_mixed_file_classification_stable() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join("mixed.bin"), b"hello\0world").unwrap();
        let root = workspace.path().to_string_lossy();

        let ascii_range = read_workspace_file_range(&root, "mixed.bin", 0, 5).unwrap();
        let binary_range = read_workspace_file_range(&root, "mixed.bin", 5, 6).unwrap();

        assert!(!ascii_range.is_text);
        assert!(!binary_range.is_text);
        assert_eq!(ascii_range.mime_type, "application/octet-stream");
        assert_eq!(binary_range.mime_type, "application/octet-stream");
    }

    #[test]
    fn binary_preview_mime_is_not_exposed_as_text() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join("document.pdf"), b"plain ascii").unwrap();
        let root = workspace.path().to_string_lossy();

        let result = read_workspace_file_range(&root, "document.pdf", 0, 5).unwrap();

        assert!(!result.is_text);
        assert_eq!(result.mime_type, "application/pdf");
    }
}
