use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use ignore::WalkBuilder;
use uuid::Uuid;

use super::{
    is_protected_workspace_path, relative_string, workspace_root, WorkspaceFileError,
    WorkspaceFileErrorKind,
};

mod index;
mod ranking;

use self::index::{QuickOpenFile, QuickOpenIndex};

#[cfg(test)]
use self::index::character_counts;

#[derive(Debug, Clone)]
pub struct WorkspaceQuickOpenSession {
    pub id: String,
    pub indexed_file_count: u32,
}

#[derive(Debug, Clone)]
pub struct WorkspaceQuickOpenMatch {
    pub relative_path: String,
    pub score: i32,
}

#[derive(Debug)]
struct QuickOpenSessionEntry {
    index: Arc<QuickOpenIndex>,
    last_accessed: Instant,
}

const QUICK_OPEN_SESSION_IDLE_TTL: Duration = Duration::from_secs(15 * 60);
const MAX_QUICK_OPEN_SESSIONS: usize = 16;
const MAX_QUICK_OPEN_INDEXED_FILES: usize = 50_000;
const MAX_QUICK_OPEN_INDEXED_PATH_BYTES: usize = 2 * 1024 * 1024;

static SESSIONS: OnceLock<Mutex<HashMap<String, QuickOpenSessionEntry>>> = OnceLock::new();
static INDEX_BUILD_GATE: OnceLock<Mutex<()>> = OnceLock::new();

pub fn start_workspace_quick_open_session(
    workspace_path: String,
) -> Result<WorkspaceQuickOpenSession, WorkspaceFileError> {
    start_workspace_quick_open_session_with_symlinks(workspace_path, true)
}

pub fn start_workspace_quick_open_session_without_symlinks(
    workspace_path: String,
) -> Result<WorkspaceQuickOpenSession, WorkspaceFileError> {
    start_workspace_quick_open_session_with_symlinks(workspace_path, false)
}

fn start_workspace_quick_open_session_with_symlinks(
    workspace_path: String,
    include_internal_symlinks: bool,
) -> Result<WorkspaceQuickOpenSession, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let mut files = with_quick_open_build_gate(|| {
        collect_quick_open_files(
            &root,
            MAX_QUICK_OPEN_INDEXED_FILES,
            MAX_QUICK_OPEN_INDEXED_PATH_BYTES,
            include_internal_symlinks,
        )
    })?;
    sort_quick_open_files(&mut files);
    let indexed_file_count = u32::try_from(files.len()).unwrap_or(u32::MAX);
    let id = Uuid::new_v4().to_string();
    let mut sessions = sessions().lock().map_err(|_| {
        WorkspaceFileError::new(
            WorkspaceFileErrorKind::Io,
            "quick open registry lock poisoned",
        )
    })?;
    prune_sessions(&mut sessions, Instant::now());
    sessions.insert(
        id.clone(),
        QuickOpenSessionEntry {
            index: Arc::new(QuickOpenIndex::new(files)),
            last_accessed: Instant::now(),
        },
    );
    enforce_session_limit(&mut sessions);
    Ok(WorkspaceQuickOpenSession {
        id,
        indexed_file_count,
    })
}

fn sort_quick_open_files(files: &mut [QuickOpenFile]) {
    files.sort_by(|left, right| {
        left.normalized_path
            .cmp(&right.normalized_path)
            .then_with(|| left.relative_path.cmp(&right.relative_path))
    });
}

fn with_quick_open_build_gate<T>(
    build: impl FnOnce() -> Result<T, WorkspaceFileError>,
) -> Result<T, WorkspaceFileError> {
    let _guard = INDEX_BUILD_GATE
        .get_or_init(|| Mutex::new(()))
        .lock()
        .map_err(|_| {
            WorkspaceFileError::new(
                WorkspaceFileErrorKind::Io,
                "quick open indexing lock poisoned",
            )
        })?;
    build()
}

fn collect_quick_open_files(
    root: &Path,
    max_files: usize,
    max_path_bytes: usize,
    include_internal_symlinks: bool,
) -> Result<Vec<QuickOpenFile>, WorkspaceFileError> {
    let filter_root = root.to_path_buf();
    let walker = WalkBuilder::new(root)
        .hidden(false)
        .parents(true)
        .require_git(false)
        .git_ignore(true)
        .git_exclude(true)
        .follow_links(false)
        .sort_by_file_path(|left, right| left.cmp(right))
        .filter_entry(move |entry| entry.path() == filter_root || !protected_entry(entry.path()))
        .build();
    let mut files = Vec::new();
    let mut indexed_path_bytes = 0_usize;
    for entry in walker {
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) if error.depth().is_some_and(|depth| depth > 0) => continue,
            Err(error) => {
                return Err(WorkspaceFileError::new(
                    WorkspaceFileErrorKind::Io,
                    error.to_string(),
                ));
            }
        };
        if let Some(relative_path) =
            quick_open_relative_path(root, entry.path(), include_internal_symlinks)?
        {
            if files.len() >= max_files {
                break;
            }
            let next_path_bytes = indexed_path_bytes.saturating_add(relative_path.len());
            if next_path_bytes > max_path_bytes {
                break;
            }
            indexed_path_bytes = next_path_bytes;
            files.push(QuickOpenFile::new(relative_path));
        }
    }
    Ok(files)
}

pub fn search_workspace_quick_open_session(
    session: WorkspaceQuickOpenSession,
    query: String,
    limit: u32,
) -> Result<Vec<WorkspaceQuickOpenMatch>, WorkspaceFileError> {
    let index = {
        let mut sessions = sessions().lock().map_err(|_| {
            WorkspaceFileError::new(
                WorkspaceFileErrorKind::Io,
                "quick open registry lock poisoned",
            )
        })?;
        access_session(&mut sessions, &session.id, Instant::now())?
    };
    Ok(ranking::search(&index, &query, limit))
}

fn access_session(
    sessions: &mut HashMap<String, QuickOpenSessionEntry>,
    session_id: &str,
    now: Instant,
) -> Result<Arc<QuickOpenIndex>, WorkspaceFileError> {
    let index = {
        let entry = sessions.get_mut(session_id).ok_or_else(|| {
            WorkspaceFileError::new(
                WorkspaceFileErrorKind::NotFound,
                "quick open session not found",
            )
        })?;
        entry.last_accessed = now;
        Arc::clone(&entry.index)
    };
    prune_sessions(sessions, now);
    Ok(index)
}

pub fn stop_workspace_quick_open_session(session: WorkspaceQuickOpenSession) {
    if let Ok(mut sessions) = sessions().lock() {
        sessions.remove(&session.id);
    }
}

fn quick_open_relative_path(
    root: &std::path::Path,
    path: &std::path::Path,
    include_internal_symlinks: bool,
) -> Result<Option<String>, WorkspaceFileError> {
    let relative_path = relative_string(root, path)?;
    if relative_path.is_empty() || is_protected_workspace_path(std::path::Path::new(&relative_path))
    {
        return Ok(None);
    }
    let link_metadata = fs::symlink_metadata(path)
        .map_err(|error| WorkspaceFileError::from_io(error, path.display().to_string()))?;
    let is_symlink = link_metadata.file_type().is_symlink();
    if is_symlink {
        if !include_internal_symlinks {
            return Ok(None);
        }
        let canonical = match fs::canonicalize(path) {
            Ok(canonical) => canonical,
            Err(_) => return Ok(None),
        };
        if !canonical.starts_with(root) {
            return Ok(None);
        }
        let canonical_relative = relative_string(root, &canonical)?;
        if is_protected_workspace_path(std::path::Path::new(&canonical_relative)) {
            return Ok(None);
        }
    }
    let metadata = if is_symlink {
        match fs::metadata(path) {
            Ok(metadata) => metadata,
            Err(_) => return Ok(None),
        }
    } else {
        link_metadata
    };
    Ok(metadata.is_file().then_some(relative_path))
}

fn protected_entry(path: &std::path::Path) -> bool {
    path.file_name().is_some_and(|name| {
        matches!(
            name.to_string_lossy().to_ascii_lowercase().as_str(),
            ".git" | ".hg" | ".svn"
        )
    })
}

fn sessions() -> &'static Mutex<HashMap<String, QuickOpenSessionEntry>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn prune_sessions(sessions: &mut HashMap<String, QuickOpenSessionEntry>, now: Instant) {
    sessions.retain(|_, entry| {
        now.saturating_duration_since(entry.last_accessed) < QUICK_OPEN_SESSION_IDLE_TTL
    });
}

fn enforce_session_limit(sessions: &mut HashMap<String, QuickOpenSessionEntry>) {
    while sessions.len() > MAX_QUICK_OPEN_SESSIONS {
        let Some(oldest) = sessions
            .iter()
            .min_by_key(|(_, entry)| entry.last_accessed)
            .map(|(id, _)| id.clone())
        else {
            break;
        };
        sessions.remove(&oldest);
    }
}

#[cfg(test)]
mod tests;
