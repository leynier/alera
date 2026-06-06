use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::time::UNIX_EPOCH;

use git2::{Repository, Status, StatusOptions};
use ignore::WalkBuilder;

mod editor_text;
mod explorer_tree;
mod watcher;

use crate::frb_generated::StreamSink;
use editor_text::{editor_text_file_from_raw, encode_workspace_editor_text_for_save};

const MAX_TEXT_FILE_BYTES: u64 = 10 * 1024 * 1024;
const COPY_SUFFIX: &str = " copy";
const PROTECTED_NAMES: [&str; 3] = [".git", ".hg", ".svn"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceFileKind {
    File,
    Directory,
    Symlink,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceFileGitStatus {
    Untracked,
    Added,
    Modified,
}

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

#[derive(Debug)]
pub struct WorkspaceFileError {
    pub kind: WorkspaceFileErrorKind,
    pub context: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceFileEntry {
    pub relative_path: String,
    pub name: String,
    pub kind: WorkspaceFileKind,
    pub size: u64,
    pub modified_millis: i64,
    pub content_token: String,
    pub is_ignored: bool,
    pub is_hidden: bool,
    pub is_symlink: bool,
    pub is_protected: bool,
    pub has_children_hint: bool,
    pub git_status: Option<WorkspaceFileGitStatus>,
}

pub struct WorkspaceTextFile {
    pub content: String,
    pub content_token: String,
    pub modified_millis: i64,
    pub size: u64,
}

pub struct WorkspaceEditorTextFile {
    pub raw_content: String,
    pub display_content: String,
    pub content_token: String,
    pub modified_millis: i64,
    pub size: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceExplorerTreeNodeKind {
    Root,
    Folder,
    File,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExplorerDirectoryChildren {
    pub relative_path: String,
    pub children: Vec<WorkspaceFileEntry>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExplorerTreeNode {
    pub id: String,
    pub name: String,
    pub kind: WorkspaceExplorerTreeNodeKind,
    pub parent_id: String,
    pub virtual_path: String,
    pub source_path: String,
    pub entry_id: Option<String>,
    pub child_ids: Vec<String>,
    pub is_expanded: bool,
    pub is_virtual: bool,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExplorerEntryBinding {
    pub node_id: String,
    pub relative_path: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExplorerTreeProjection {
    pub directories: Vec<WorkspaceExplorerDirectoryChildren>,
    pub nodes: Vec<WorkspaceExplorerTreeNode>,
    pub entry_bindings: Vec<WorkspaceExplorerEntryBinding>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExplorerWatcherHandle {
    pub id: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExplorerWatchBatch {
    pub directory_relative_paths: Vec<String>,
    pub changed_relative_paths: Vec<String>,
    pub coalesced_event_count: u32,
}

impl WorkspaceFileError {
    fn new(kind: WorkspaceFileErrorKind, context: impl Into<String>) -> Self {
        Self {
            kind,
            context: context.into(),
        }
    }

    fn from_io(error: io::Error, context: impl Into<String>) -> Self {
        let context = context.into();
        let kind = match error.kind() {
            io::ErrorKind::NotFound => WorkspaceFileErrorKind::NotFound,
            io::ErrorKind::AlreadyExists => WorkspaceFileErrorKind::AlreadyExists,
            io::ErrorKind::PermissionDenied => WorkspaceFileErrorKind::Io,
            _ => WorkspaceFileErrorKind::Io,
        };
        Self::new(kind, format!("{context}: {error}"))
    }
}

pub fn list_workspace_children(
    workspace_path: String,
    relative_path: String,
    hide_ignored: bool,
) -> Result<Vec<WorkspaceFileEntry>, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let directory = resolve_existing(&root, &relative_path)?;
    let metadata = fs::symlink_metadata(&directory)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if !metadata.is_dir() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }

    let paths = if hide_ignored {
        ignored_aware_children(&directory)?
    } else {
        read_dir_children(&directory)?
    };

    let git_statuses = GitStatusSnapshot::for_workspace(&root);
    let mut entries = Vec::with_capacity(paths.len());
    for path in paths {
        if let Some(entry) = entry_for_path(&root, &path, hide_ignored, git_statuses.as_ref())? {
            entries.push(entry);
        }
    }
    entries.sort_by(|left, right| {
        let left_dir = matches!(left.kind, WorkspaceFileKind::Directory);
        let right_dir = matches!(right.kind, WorkspaceFileKind::Directory);
        right_dir
            .cmp(&left_dir)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
            .then_with(|| left.name.cmp(&right.name))
    });
    Ok(entries)
}

pub fn project_workspace_explorer_tree(
    workspace_name: String,
    workspace_path: String,
    directories: Vec<WorkspaceExplorerDirectoryChildren>,
    replacement: Option<WorkspaceExplorerDirectoryChildren>,
) -> WorkspaceExplorerTreeProjection {
    explorer_tree::project_tree(workspace_name, workspace_path, directories, replacement)
}

pub fn start_workspace_explorer_watcher(
    workspace_path: String,
) -> Result<WorkspaceExplorerWatcherHandle, WorkspaceFileError> {
    watcher::start_workspace_explorer_watcher(workspace_path)
}

pub fn update_workspace_explorer_watcher(
    handle: WorkspaceExplorerWatcherHandle,
    watched_relative_paths: Vec<String>,
) -> Result<(), WorkspaceFileError> {
    watcher::update_workspace_explorer_watcher(handle, watched_relative_paths)
}

pub fn watch_workspace_explorer_events(
    handle: WorkspaceExplorerWatcherHandle,
    sink: StreamSink<WorkspaceExplorerWatchBatch>,
) {
    watcher::watch_workspace_explorer_events(handle, sink);
}

pub fn stop_workspace_explorer_watcher(handle: WorkspaceExplorerWatcherHandle) {
    watcher::stop_workspace_explorer_watcher(handle);
}

pub fn read_workspace_text_file(
    workspace_path: String,
    relative_path: String,
) -> Result<WorkspaceTextFile, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let path = resolve_existing(&root, &relative_path)?;
    let metadata =
        fs::metadata(&path).map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if !metadata.is_file() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    if metadata.len() > MAX_TEXT_FILE_BYTES {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            format!("{} exceeds {} bytes", relative_path, MAX_TEXT_FILE_BYTES),
        ));
    }
    let bytes =
        fs::read(&path).map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if bytes.contains(&0) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    let content = String::from_utf8(bytes).map_err(|_| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::Unsupported, relative_path.clone())
    })?;
    let modified_millis = modified_millis(&metadata);
    Ok(WorkspaceTextFile {
        content,
        content_token: content_token(&metadata),
        modified_millis,
        size: metadata.len(),
    })
}

pub fn read_workspace_editor_text_file(
    workspace_path: String,
    relative_path: String,
    tab_size: i32,
) -> Result<WorkspaceEditorTextFile, WorkspaceFileError> {
    let file = read_workspace_text_file(workspace_path, relative_path)?;
    Ok(editor_text_file_from_raw(file, tab_size))
}

pub fn write_workspace_text_file(
    workspace_path: String,
    relative_path: String,
    content: String,
    expected_content_token: Option<String>,
    overwrite_if_changed: bool,
) -> Result<WorkspaceTextFile, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    reject_protected(&relative_path)?;
    let path = resolve_existing(&root, &relative_path)?;
    let canonical_relative_path = relative_string(&root, &path)?;
    reject_protected(&canonical_relative_path)?;
    let metadata =
        fs::metadata(&path).map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if !metadata.is_file() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    if !overwrite_if_changed {
        if let Some(expected) = expected_content_token {
            let current = content_token(&metadata);
            if expected != current {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::Conflict,
                    relative_path,
                ));
            }
        }
    }
    fs::write(&path, content.as_bytes())
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    read_workspace_text_file(workspace_path, canonical_relative_path)
}

// FRB exposes this as named arguments on the Dart side, so keep the boundary flat.
#[allow(clippy::too_many_arguments)]
pub fn write_workspace_editor_text_file(
    workspace_path: String,
    relative_path: String,
    current_display_content: String,
    original_raw_content: Option<String>,
    original_display_content: Option<String>,
    expected_content_token: Option<String>,
    overwrite_if_changed: bool,
    tab_size: i32,
) -> Result<WorkspaceEditorTextFile, WorkspaceFileError> {
    let content = encode_workspace_editor_text_for_save(
        &current_display_content,
        original_raw_content.as_deref(),
        original_display_content.as_deref(),
    );
    let file = write_workspace_text_file(
        workspace_path,
        relative_path,
        content,
        expected_content_token,
        overwrite_if_changed,
    )?;
    Ok(editor_text_file_from_raw(file, tab_size))
}

pub fn create_workspace_file(
    workspace_path: String,
    parent_relative_path: String,
    name: String,
) -> Result<WorkspaceFileEntry, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let parent = resolve_existing(&root, &parent_relative_path)?;
    let relative_path = join_relative(&parent_relative_path, &sanitize_name(&name)?)?;
    reject_protected(&relative_path)?;
    let path = resolve_new_child(&root, &parent, &name)?;
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    entry_for_path(&root, &path, false, None)?.ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::NotFound, relative_path.clone())
    })
}

pub fn create_workspace_directory(
    workspace_path: String,
    parent_relative_path: String,
    name: String,
) -> Result<WorkspaceFileEntry, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let parent = resolve_existing(&root, &parent_relative_path)?;
    let relative_path = join_relative(&parent_relative_path, &sanitize_name(&name)?)?;
    reject_protected(&relative_path)?;
    let path = resolve_new_child(&root, &parent, &name)?;
    fs::create_dir(&path).map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    entry_for_path(&root, &path, false, None)?.ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::NotFound, relative_path.clone())
    })
}

pub fn rename_workspace_entry(
    workspace_path: String,
    relative_path: String,
    new_name: String,
) -> Result<WorkspaceFileEntry, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    reject_protected(&relative_path)?;
    let path = resolve_existing(&root, &relative_path)?;
    let parent = path.parent().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path.clone())
    })?;
    let new_name = sanitize_name(&new_name)?;
    let destination = parent.join(&new_name);
    if destination.exists() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::AlreadyExists,
            new_name,
        ));
    }
    ensure_inside_existing_parent(&root, &destination)?;
    fs::rename(&path, &destination)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    entry_for_path(&root, &destination, false, None)?.ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::NotFound, relative_path.clone())
    })
}

pub fn copy_workspace_entry(
    workspace_path: String,
    relative_path: String,
    target_parent_relative_path: String,
) -> Result<WorkspaceFileEntry, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    reject_protected(&relative_path)?;
    let source = resolve_existing_no_follow(&root, &relative_path)?;
    let source_metadata = fs::symlink_metadata(&source)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if source_metadata.file_type().is_symlink() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    let target_parent = resolve_existing(&root, &target_parent_relative_path)?;
    let name = source.file_name().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path.clone())
    })?;
    let destination = unique_copy_destination(&target_parent.join(name));
    ensure_not_descendant(&source, &destination)?;
    copy_recursively(&source, &destination)?;
    entry_for_path(&root, &destination, false, None)?.ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::NotFound, relative_path.clone())
    })
}

pub fn move_workspace_entry(
    workspace_path: String,
    relative_path: String,
    target_parent_relative_path: String,
) -> Result<WorkspaceFileEntry, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    reject_protected(&relative_path)?;
    let source = resolve_existing_no_follow(&root, &relative_path)?;
    let source_metadata = fs::symlink_metadata(&source)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if source_metadata.file_type().is_symlink() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }
    let target_parent = resolve_existing(&root, &target_parent_relative_path)?;
    let name = source.file_name().ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::InvalidPath, relative_path.clone())
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
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    entry_for_path(&root, &destination, false, None)?.ok_or_else(|| {
        WorkspaceFileError::new(WorkspaceFileErrorKind::NotFound, relative_path.clone())
    })
}

pub fn delete_workspace_entry(
    workspace_path: String,
    relative_path: String,
    use_trash: bool,
) -> Result<(), WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    reject_protected(&relative_path)?;
    let path = resolve_existing_no_follow(&root, &relative_path)?;
    if use_trash && trash::delete(&path).is_ok() {
        return Ok(());
    }
    let metadata = fs::symlink_metadata(&path)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if metadata.is_dir() && !metadata.file_type().is_symlink() {
        fs::remove_dir_all(&path)
            .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))
    } else {
        fs::remove_file(&path).map_err(|error| WorkspaceFileError::from_io(error, &relative_path))
    }
}

fn workspace_root(workspace_path: &str) -> Result<PathBuf, WorkspaceFileError> {
    fs::canonicalize(workspace_path)
        .map_err(|error| WorkspaceFileError::from_io(error, workspace_path))
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

fn resolve_new_child(
    root: &Path,
    parent: &Path,
    name: &str,
) -> Result<PathBuf, WorkspaceFileError> {
    let name = sanitize_name(name)?;
    let destination = parent.join(name);
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
    if is_protected_relative_path(relative_path) {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::ProtectedPath,
            relative_path,
        ));
    }
    Ok(())
}

fn is_protected_relative_path(relative_path: &str) -> bool {
    relative_path
        .split('/')
        .any(|component| PROTECTED_NAMES.contains(&component))
}

fn is_protected_child_path(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| PROTECTED_NAMES.contains(&name))
}

fn entry_for_path(
    root: &Path,
    path: &Path,
    hide_ignored: bool,
    git_statuses: Option<&GitStatusSnapshot>,
) -> Result<Option<WorkspaceFileEntry>, WorkspaceFileError> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| WorkspaceFileError::from_io(error, path.to_string_lossy()))?;
    let Some(name) = path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
    else {
        return Ok(None);
    };
    let relative_path = relative_string(root, path)?;
    if is_protected_relative_path(&relative_path) {
        return Ok(None);
    }
    let file_type = metadata.file_type();
    let is_symlink = file_type.is_symlink();
    let kind = if is_symlink {
        WorkspaceFileKind::Symlink
    } else if metadata.is_dir() {
        WorkspaceFileKind::Directory
    } else if metadata.is_file() {
        WorkspaceFileKind::File
    } else {
        WorkspaceFileKind::Other
    };
    let has_children_hint = matches!(kind, WorkspaceFileKind::Directory)
        && has_visible_child(path, hide_ignored).unwrap_or(false);
    Ok(Some(WorkspaceFileEntry {
        relative_path: relative_path.clone(),
        name: name.clone(),
        kind,
        size: metadata.len(),
        modified_millis: modified_millis(&metadata),
        content_token: content_token(&metadata),
        is_ignored: false,
        is_hidden: name.starts_with('.'),
        is_symlink,
        is_protected: false,
        has_children_hint,
        git_status: git_statuses.and_then(|snapshot| snapshot.status_for(&relative_path, kind)),
    }))
}

struct GitStatusSnapshot {
    statuses: HashMap<String, WorkspaceFileGitStatus>,
}

impl GitStatusSnapshot {
    fn for_workspace(root: &Path) -> Option<Self> {
        let repo = Repository::discover(root).ok()?;
        let workdir = repo.workdir()?;
        let mut options = StatusOptions::new();
        options
            .include_untracked(true)
            .recurse_untracked_dirs(true)
            .renames_head_to_index(true)
            .renames_index_to_workdir(true);
        let entries = repo.statuses(Some(&mut options)).ok()?;
        let mut statuses = HashMap::new();
        for entry in entries.iter() {
            let Ok(repo_relative_path) = entry.path() else {
                continue;
            };
            let path = workdir.join(repo_relative_path);
            let Ok(workspace_relative_path) = relative_string(root, &path) else {
                continue;
            };
            if workspace_relative_path.is_empty()
                || is_protected_relative_path(&workspace_relative_path)
            {
                continue;
            }
            let status = status_from_git2(entry.status());
            merge_status(&mut statuses, workspace_relative_path, status);
        }
        Some(Self { statuses })
    }

    fn status_for(
        &self,
        relative_path: &str,
        kind: WorkspaceFileKind,
    ) -> Option<WorkspaceFileGitStatus> {
        if let Some(status) = self.statuses.get(relative_path) {
            return Some(*status);
        }
        if !matches!(kind, WorkspaceFileKind::Directory) {
            return None;
        }
        let prefix = format!("{relative_path}/");
        self.statuses
            .iter()
            .filter_map(|(path, status)| path.starts_with(&prefix).then_some(*status))
            .max_by_key(|status| git_status_priority(*status))
    }
}

fn status_from_git2(status: Status) -> WorkspaceFileGitStatus {
    if status.contains(Status::WT_NEW) {
        WorkspaceFileGitStatus::Untracked
    } else if status.contains(Status::INDEX_NEW) {
        WorkspaceFileGitStatus::Added
    } else {
        WorkspaceFileGitStatus::Modified
    }
}

fn merge_status(
    statuses: &mut HashMap<String, WorkspaceFileGitStatus>,
    relative_path: String,
    status: WorkspaceFileGitStatus,
) {
    match statuses.get(&relative_path).copied() {
        Some(existing) if git_status_priority(existing) >= git_status_priority(status) => {}
        _ => {
            statuses.insert(relative_path, status);
        }
    }
}

fn git_status_priority(status: WorkspaceFileGitStatus) -> u8 {
    match status {
        WorkspaceFileGitStatus::Untracked => 1,
        WorkspaceFileGitStatus::Added => 2,
        WorkspaceFileGitStatus::Modified => 3,
    }
}

fn ignored_aware_children(directory: &Path) -> Result<Vec<PathBuf>, WorkspaceFileError> {
    let mut paths = Vec::new();
    let walker = WalkBuilder::new(directory)
        .max_depth(Some(1))
        .hidden(false)
        .parents(true)
        .require_git(false)
        .build();
    for result in walker {
        let entry = result.map_err(|error| {
            WorkspaceFileError::new(WorkspaceFileErrorKind::Io, error.to_string())
        })?;
        if entry.path() == directory {
            continue;
        }
        if is_protected_child_path(entry.path()) {
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
        if is_protected_child_path(&entry.path()) {
            continue;
        }
        paths.push(entry.path());
    }
    Ok(paths)
}

fn has_visible_child(directory: &Path, hide_ignored: bool) -> Result<bool, WorkspaceFileError> {
    if hide_ignored {
        Ok(!ignored_aware_children(directory)?.is_empty())
    } else {
        for result in fs::read_dir(directory)
            .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?
        {
            let entry = result
                .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?;
            if !is_protected_child_path(&entry.path()) {
                return Ok(true);
            }
        }
        Ok(false)
    }
}

fn relative_string(root: &Path, path: &Path) -> Result<String, WorkspaceFileError> {
    let relative = path.strip_prefix(root).map_err(|_| {
        WorkspaceFileError::new(
            WorkspaceFileErrorKind::OutsideWorkspace,
            path.to_string_lossy(),
        )
    })?;
    Ok(relative
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_string_lossy().to_string()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/"))
}

fn join_relative(parent: &str, name: &str) -> Result<String, WorkspaceFileError> {
    let parent = parent.trim_matches('/');
    if parent.is_empty() {
        Ok(name.to_string())
    } else {
        Ok(format!("{parent}/{name}"))
    }
}

fn modified_millis(metadata: &fs::Metadata) -> i64 {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn content_token(metadata: &fs::Metadata) -> String {
    format!("{}:{}", metadata.len(), modified_millis(metadata))
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

    fn workspace_path(dir: &tempfile::TempDir) -> String {
        dir.path().to_string_lossy().to_string()
    }

    fn error_kind<T>(result: Result<T, WorkspaceFileError>) -> WorkspaceFileErrorKind {
        match result {
            Ok(_) => panic!("expected workspace file error"),
            Err(error) => error.kind,
        }
    }

    fn create_file_symlink(source: &Path, link: &Path) -> io::Result<()> {
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(source, link)
        }
        #[cfg(windows)]
        {
            std::os::windows::fs::symlink_file(source, link)
        }
    }

    fn test_entry(
        relative_path: &str,
        kind: WorkspaceFileKind,
        has_children_hint: bool,
    ) -> WorkspaceFileEntry {
        WorkspaceFileEntry {
            relative_path: relative_path.to_string(),
            name: relative_path
                .split('/')
                .next_back()
                .unwrap_or(relative_path)
                .to_string(),
            kind,
            size: 0,
            modified_millis: 0,
            content_token: format!("{relative_path}:token"),
            is_ignored: false,
            is_hidden: false,
            is_symlink: false,
            is_protected: false,
            has_children_hint,
            git_status: None,
        }
    }

    #[test]
    fn project_workspace_explorer_tree_adds_lazy_placeholders_and_bindings() {
        let projection = project_workspace_explorer_tree(
            "alera".to_string(),
            "/repo/alera".to_string(),
            Vec::new(),
            Some(WorkspaceExplorerDirectoryChildren {
                relative_path: String::new(),
                children: vec![
                    test_entry("src", WorkspaceFileKind::Directory, true),
                    test_entry("readme.md", WorkspaceFileKind::File, false),
                ],
            }),
        );

        let node_ids = projection
            .nodes
            .iter()
            .map(|node| node.id.as_str())
            .collect::<Vec<_>>();
        assert!(node_ids.contains(&"workspace-root"));
        assert!(node_ids.contains(&"path:src"));
        assert!(node_ids.contains(&"path:readme.md"));
        assert!(node_ids.contains(&"__alera_placeholder__:src"));
        assert!(projection
            .entry_bindings
            .iter()
            .any(|binding| binding.node_id == "path:src" && binding.relative_path == "src"));
    }

    #[test]
    fn project_workspace_explorer_tree_prunes_stale_expanded_subtrees() {
        let projection = project_workspace_explorer_tree(
            "alera".to_string(),
            "/repo/alera".to_string(),
            vec![
                WorkspaceExplorerDirectoryChildren {
                    relative_path: String::new(),
                    children: vec![test_entry("src", WorkspaceFileKind::Directory, true)],
                },
                WorkspaceExplorerDirectoryChildren {
                    relative_path: "src".to_string(),
                    children: vec![test_entry("src/main.dart", WorkspaceFileKind::File, false)],
                },
            ],
            Some(WorkspaceExplorerDirectoryChildren {
                relative_path: String::new(),
                children: Vec::new(),
            }),
        );

        assert_eq!(projection.directories.len(), 1);
        assert!(projection.directories[0].relative_path.is_empty());
        assert!(projection.directories[0].children.is_empty());
        assert!(!projection
            .nodes
            .iter()
            .any(|node| node.id == "path:src" || node.id == "path:src/main.dart"));
    }

    #[test]
    fn list_workspace_children_sorts_directories_and_filters_ignored_entries() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), "ignored.txt\n").expect("write gitignore");
        fs::create_dir(workspace.path().join("src")).expect("create src");
        fs::write(workspace.path().join("src/main.dart"), "void main() {}\n").expect("write src");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");
        fs::write(workspace.path().join("ignored.txt"), "ignored\n").expect("write ignored");

        let entries =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let names = entries
            .iter()
            .map(|entry| entry.name.as_str())
            .collect::<Vec<_>>();

        assert!(names.contains(&"src"));
        assert!(names.contains(&"readme.md"));
        assert!(!names.contains(&"ignored.txt"));
        assert!(
            names.iter().position(|name| *name == "src").unwrap()
                < names.iter().position(|name| *name == "readme.md").unwrap()
        );

        let src = entries.iter().find(|entry| entry.name == "src").unwrap();
        assert_eq!(src.kind, WorkspaceFileKind::Directory);
        assert!(src.has_children_hint);
    }

    #[test]
    fn list_workspace_children_always_hides_protected_git_directory() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::create_dir(workspace.path().join(".git")).expect("create git dir");
        fs::write(workspace.path().join(".git/config"), "protected").expect("write git config");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        for hide_ignored in [true, false] {
            let entries =
                list_workspace_children(workspace_path(&workspace), String::new(), hide_ignored)
                    .unwrap();
            let names = entries
                .iter()
                .map(|entry| entry.name.as_str())
                .collect::<Vec<_>>();

            assert!(names.contains(&"readme.md"));
            assert!(!names.contains(&".git"));
        }
    }

    #[test]
    fn list_workspace_children_omits_git_status_outside_git_repositories() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join("note.txt"), "note").expect("write note");

        let entries =
            list_workspace_children(workspace_path(&workspace), String::new(), false).unwrap();

        assert_eq!(
            entries
                .iter()
                .find(|entry| entry.name == "note.txt")
                .unwrap()
                .git_status,
            None
        );
    }

    #[test]
    fn list_workspace_children_reports_git_status_for_git_repositories() {
        let workspace = tempfile::tempdir().expect("tempdir");
        let repo = Repository::init(workspace.path()).expect("init repo");
        fs::write(workspace.path().join("tracked.txt"), "one").expect("write tracked");
        commit_all(&repo, "initial");
        fs::write(workspace.path().join("tracked.txt"), "two").expect("modify tracked");
        fs::write(workspace.path().join("added.txt"), "added").expect("write added");
        {
            let mut index = repo.index().expect("index");
            index
                .add_path(Path::new("added.txt"))
                .expect("add added file");
            index.write().expect("write index");
        }
        fs::write(workspace.path().join("untracked.txt"), "untracked").expect("write untracked");

        let entries =
            list_workspace_children(workspace_path(&workspace), String::new(), false).unwrap();
        let status_for = |name: &str| {
            entries
                .iter()
                .find(|entry| entry.name == name)
                .and_then(|entry| entry.git_status)
        };

        assert_eq!(
            status_for("tracked.txt"),
            Some(WorkspaceFileGitStatus::Modified)
        );
        assert_eq!(status_for("added.txt"), Some(WorkspaceFileGitStatus::Added));
        assert_eq!(
            status_for("untracked.txt"),
            Some(WorkspaceFileGitStatus::Untracked)
        );
    }

    #[test]
    fn rejects_parent_relative_paths_before_touching_the_filesystem() {
        let workspace = tempfile::tempdir().expect("tempdir");

        let kind = error_kind(list_workspace_children(
            workspace_path(&workspace),
            "../outside".to_string(),
            false,
        ));

        assert_eq!(kind, WorkspaceFileErrorKind::InvalidPath);
    }

    #[test]
    fn read_workspace_editor_text_file_returns_raw_and_display_content() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join("main.dart"), "\tvoid main() {}\n").expect("write file");

        let file =
            read_workspace_editor_text_file(workspace_path(&workspace), "main.dart".to_string(), 4)
                .expect("read editor file");

        assert_eq!(file.raw_content, "\tvoid main() {}\n");
        assert_eq!(file.display_content, "    void main() {}\n");
        assert_eq!(file.size, 16);
    }

    #[test]
    fn write_workspace_editor_text_file_preserves_raw_tabs_on_unchanged_lines() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(
            workspace.path().join("main.dart"),
            "\talpha\n\tbeta\n\tgamma\n",
        )
        .expect("write file");
        let initial =
            read_workspace_editor_text_file(workspace_path(&workspace), "main.dart".to_string(), 4)
                .expect("read editor file");

        let saved = write_workspace_editor_text_file(
            workspace_path(&workspace),
            "main.dart".to_string(),
            "    alpha\n    beta changed\n    gamma\n".to_string(),
            Some(initial.raw_content),
            Some(initial.display_content),
            Some(initial.content_token),
            false,
            4,
        )
        .expect("save editor file");

        assert_eq!(
            fs::read_to_string(workspace.path().join("main.dart")).unwrap(),
            "\talpha\n    beta changed\n\tgamma\n"
        );
        assert_eq!(
            saved.display_content,
            "    alpha\n    beta changed\n    gamma\n"
        );
    }

    #[test]
    fn read_and_write_large_workspace_editor_text_file_smoke() {
        let workspace = tempfile::tempdir().expect("tempdir");
        let mut raw = String::with_capacity(2 * 1024 * 1024);
        while raw.len() < 2 * 1024 * 1024 {
            raw.push_str("\talpha\n\tbeta\n\tgamma\n");
        }
        fs::write(workspace.path().join("large.txt"), &raw).expect("write large file");

        let loaded =
            read_workspace_editor_text_file(workspace_path(&workspace), "large.txt".to_string(), 4)
                .expect("read large editor file");

        assert!(loaded.raw_content.starts_with('\t'));
        assert!(loaded.display_content.starts_with("    "));

        let saved = write_workspace_editor_text_file(
            workspace_path(&workspace),
            "large.txt".to_string(),
            loaded.display_content.clone(),
            Some(loaded.raw_content),
            Some(loaded.display_content),
            Some(loaded.content_token),
            false,
            4,
        )
        .expect("save large editor file");

        assert_eq!(saved.raw_content, raw);
    }

    #[test]
    fn write_workspace_text_file_detects_content_token_conflicts() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join("main.dart"), "one").expect("write file");
        let initial = read_workspace_text_file(workspace_path(&workspace), "main.dart".to_string())
            .expect("read file");
        fs::write(workspace.path().join("main.dart"), "external").expect("external write");

        let kind = error_kind(write_workspace_text_file(
            workspace_path(&workspace),
            "main.dart".to_string(),
            "two".to_string(),
            Some(initial.content_token),
            false,
        ));

        assert_eq!(kind, WorkspaceFileErrorKind::Conflict);

        let overwritten = write_workspace_text_file(
            workspace_path(&workspace),
            "main.dart".to_string(),
            "two".to_string(),
            None,
            true,
        )
        .expect("overwrite file");
        assert_eq!(overwritten.content, "two");
    }

    #[test]
    fn write_workspace_text_file_rejects_symlink_escape() {
        let workspace = tempfile::tempdir().expect("tempdir");
        let outside = tempfile::tempdir().expect("outside tempdir");
        let outside_file = outside.path().join("important.txt");
        fs::write(&outside_file, "outside").expect("write outside file");
        let link = workspace.path().join("note.txt");
        if let Err(error) = create_file_symlink(&outside_file, &link) {
            eprintln!("skipping symlink test because symlink creation failed: {error}");
            return;
        }

        let kind = error_kind(write_workspace_text_file(
            workspace_path(&workspace),
            "note.txt".to_string(),
            "changed".to_string(),
            None,
            true,
        ));

        assert_eq!(kind, WorkspaceFileErrorKind::OutsideWorkspace);
        assert_eq!(fs::read_to_string(outside_file).unwrap(), "outside");
    }

    #[test]
    fn write_workspace_text_file_rejects_symlink_to_protected_path() {
        let workspace = tempfile::tempdir().expect("tempdir");
        let git_dir = workspace.path().join(".git");
        fs::create_dir(&git_dir).expect("create git dir");
        let protected_file = git_dir.join("config");
        fs::write(&protected_file, "protected").expect("write protected file");
        let link = workspace.path().join("config-link");
        if let Err(error) = create_file_symlink(&protected_file, &link) {
            eprintln!("skipping symlink test because symlink creation failed: {error}");
            return;
        }

        let kind = error_kind(write_workspace_text_file(
            workspace_path(&workspace),
            "config-link".to_string(),
            "changed".to_string(),
            None,
            true,
        ));

        assert_eq!(kind, WorkspaceFileErrorKind::ProtectedPath);
        assert_eq!(fs::read_to_string(protected_file).unwrap(), "protected");
    }

    #[test]
    fn write_workspace_text_file_allows_symlink_to_regular_workspace_file() {
        let workspace = tempfile::tempdir().expect("tempdir");
        let target_file = workspace.path().join("target.txt");
        fs::write(&target_file, "one").expect("write target file");
        let link = workspace.path().join("note.txt");
        if let Err(error) = create_file_symlink(&target_file, &link) {
            eprintln!("skipping symlink test because symlink creation failed: {error}");
            return;
        }

        let written = write_workspace_text_file(
            workspace_path(&workspace),
            "note.txt".to_string(),
            "two".to_string(),
            None,
            true,
        )
        .expect("write through workspace-local symlink");

        assert_eq!(written.content, "two");
        assert_eq!(fs::read_to_string(target_file).unwrap(), "two");
    }

    #[test]
    fn copy_workspace_entry_creates_a_unique_destination_name() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join("note.txt"), "one").expect("write source");
        fs::write(workspace.path().join("note copy.txt"), "existing").expect("write existing");

        let copied = copy_workspace_entry(
            workspace_path(&workspace),
            "note.txt".to_string(),
            String::new(),
        )
        .expect("copy file");

        assert_eq!(copied.relative_path, "note copy 2.txt");
        assert_eq!(
            fs::read_to_string(workspace.path().join("note copy 2.txt")).unwrap(),
            "one"
        );
    }

    fn commit_all(repo: &Repository, message: &str) {
        let mut index = repo.index().expect("index");
        index
            .add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
            .expect("add all");
        index.write().expect("write index");
        let tree_id = index.write_tree().expect("write tree");
        let tree = repo.find_tree(tree_id).expect("find tree");
        let signature = git2::Signature::now("Alera", "alera@example.com").expect("signature");
        repo.commit(Some("HEAD"), &signature, &signature, message, &tree, &[])
            .expect("commit");
    }
}
