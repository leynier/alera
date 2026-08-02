use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use super::{
    WorkspaceFileError, WorkspaceFileErrorKind, WorkspaceQuickOpenMatch, WorkspaceQuickOpenSession,
};

mod index;
mod ranking;

#[cfg(test)]
mod tests;

static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<String, Arc<index::QuickOpenIndex>>>> = OnceLock::new();

pub(super) fn start_workspace_quick_open_session(
    workspace_path: String,
) -> Result<WorkspaceQuickOpenSession, WorkspaceFileError> {
    let index = index::build_index(&workspace_path)?;
    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed).to_string();
    let indexed_file_count = u32::try_from(index.files.len()).unwrap_or(u32::MAX);
    sessions()
        .lock()
        .map_err(|_| {
            WorkspaceFileError::new(
                WorkspaceFileErrorKind::Io,
                "quick open session registry lock poisoned",
            )
        })?
        .insert(id.clone(), index);
    Ok(WorkspaceQuickOpenSession {
        id,
        indexed_file_count,
    })
}

pub(super) fn search_workspace_quick_open_session(
    session: WorkspaceQuickOpenSession,
    query: String,
    limit: u32,
) -> Result<Vec<WorkspaceQuickOpenMatch>, WorkspaceFileError> {
    let index = {
        let sessions = sessions().lock().map_err(|_| {
            WorkspaceFileError::new(
                WorkspaceFileErrorKind::Io,
                "quick open session registry lock poisoned",
            )
        })?;
        sessions.get(&session.id).cloned().ok_or_else(|| {
            WorkspaceFileError::new(
                WorkspaceFileErrorKind::NotFound,
                format!("quick open session {}", session.id),
            )
        })?
    };
    Ok(ranking::search(&index, &query, limit))
}

pub(super) fn stop_workspace_quick_open_session(session: WorkspaceQuickOpenSession) {
    if let Ok(mut sessions) = sessions().lock() {
        sessions.remove(&session.id);
    }
}

fn sessions() -> &'static Mutex<HashMap<String, Arc<index::QuickOpenIndex>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}
