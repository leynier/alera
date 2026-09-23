use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Component, Path, PathBuf};

use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptions, OpenOptionsFollowExt};
use cap_std::{ambient_authority, fs::Dir};
use same_file::Handle;

mod containment;
mod editor_text;
mod listing;
mod mime;
mod mutations;
mod prompts;
mod quick_open;

use mime::{mime_type_for_path, path_has_binary_preview_mime};

pub use containment::{contained_workspace_relative_path, ContainedWorkspacePath};
pub use editor_text::{encode_workspace_editor_text_for_save, expand_workspace_editor_tabs};
pub use listing::{list_workspace_children, WorkspaceExplorerEntry, WorkspaceExplorerEntryKind};
pub use mutations::{
    copy_workspace_entry, create_workspace_directory, create_workspace_file,
    delete_workspace_entry, move_workspace_entry, rename_workspace_entry, write_workspace_file,
    WrittenWorkspaceFile,
};
pub use prompts::{list_codex_saved_prompts, CodexSavedPrompt, CodexSavedPromptScope};
pub use quick_open::{
    collect_workspace_quick_open_paths, import_workspace_quick_open_paths,
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
    AlreadyExists,
    ProtectedPath,
    Unsupported,
    Conflict,
    Io,
}

impl WorkspaceFileErrorKind {
    /// Wire name shared with the runtime host protocol and its Dart client.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::InvalidPath => "invalidPath",
            Self::OutsideWorkspace => "outsideWorkspace",
            Self::NotFound => "notFound",
            Self::AlreadyExists => "alreadyExists",
            Self::ProtectedPath => "protectedPath",
            Self::Unsupported => "unsupported",
            Self::Conflict => "conflict",
            Self::Io => "io",
        }
    }
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
        let kind = match error.kind() {
            std::io::ErrorKind::NotFound => WorkspaceFileErrorKind::NotFound,
            std::io::ErrorKind::AlreadyExists => WorkspaceFileErrorKind::AlreadyExists,
            _ => WorkspaceFileErrorKind::Io,
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
    /// Same `"<size>:<modifiedMillis>"` token the desktop editor compares on
    /// save, so a remote write can detect a file changed underneath it.
    pub content_token: String,
    pub modified_millis: i64,
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
        content_token: content_token(&metadata),
        modified_millis: modified_millis(&metadata),
    })
}

pub fn open_workspace_file_nofollow(
    workspace_path: &str,
    relative_path: &str,
) -> Result<(fs::File, PathBuf), WorkspaceFileError> {
    let root = open_workspace_file_root(workspace_path)?;
    open_workspace_file_without_symlinks(&root, relative_path)
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

pub fn modified_millis(metadata: &fs::Metadata) -> i64 {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

/// Buffer identity for optimistic writes: size and mtime, cheap to compute
/// and identical on every platform and on both sides of a host link.
pub fn content_token(metadata: &fs::Metadata) -> String {
    format!("{}:{}", metadata.len(), modified_millis(metadata))
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
#[path = "workspace_file_root_tests.rs"]
mod tests;
