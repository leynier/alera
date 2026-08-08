use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Component, Path, PathBuf};

use cap_std::{ambient_authority, fs::Dir};

mod prompts;
mod quick_open;

pub use prompts::{list_codex_saved_prompts, CodexSavedPrompt, CodexSavedPromptScope};
pub use quick_open::{
    search_workspace_quick_open_session, start_workspace_quick_open_session,
    stop_workspace_quick_open_session, WorkspaceQuickOpenMatch, WorkspaceQuickOpenSession,
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

pub fn read_workspace_file_range(
    workspace_path: &str,
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
    let root = workspace_root(workspace_path)?;
    if is_protected_workspace_path(Path::new(relative_path)) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }
    let path = resolve_existing(&root, relative_path)?;
    let canonical_relative = PathBuf::from(relative_string(&root, &path)?);
    if is_protected_workspace_path(&canonical_relative) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }
    let directory = Dir::open_ambient_dir(&root, ambient_authority())
        .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))?;
    let mut file = directory
        .open(&canonical_relative)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?
        .into_std();
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
        &canonical_relative,
        metadata.len(),
        relative_path,
    )?;
    file.seek(SeekFrom::Start(offset))
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    let mut bytes = vec![0_u8; usize::try_from(count).unwrap_or(0)];
    file.read_exact(&mut bytes)
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    let mime_type = mime_type_for_path(&canonical_relative, is_text).to_string();
    Ok(WorkspaceFileRange {
        next_offset: offset.saturating_add(count),
        bytes,
        offset,
        total_bytes: metadata.len(),
        mime_type,
        is_text,
    })
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

fn path_has_binary_preview_mime(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref(),
        Some("png" | "jpg" | "jpeg" | "gif" | "webp" | "pdf")
    )
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

pub(super) fn resolve_existing(
    root: &Path,
    relative_path: &str,
) -> Result<PathBuf, WorkspaceFileError> {
    let relative = Path::new(relative_path);
    if relative.as_os_str().is_empty()
        || relative.is_absolute()
        || relative
            .components()
            .any(|component| !matches!(component, Component::Normal(_) | Component::CurDir))
    {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::InvalidPath,
            relative_path,
        ));
    }
    let candidate = fs::canonicalize(root.join(relative))
        .map_err(|error| WorkspaceFileError::from_io(error, relative_path))?;
    if !candidate.starts_with(root) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    Ok(candidate)
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

fn mime_type_for_path(path: &Path, is_text: bool) -> &'static str {
    match path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("svg") => "image/svg+xml",
        Some("json") => "application/json",
        Some("pdf") => "application/pdf",
        _ if is_text => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
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
