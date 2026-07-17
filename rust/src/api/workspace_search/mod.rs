use std::collections::HashMap;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

mod compile;
mod engine;
mod globs;
mod line_ranges;
mod paths;
mod preview;
mod replace;

#[cfg(test)]
mod cancellation_tests;
#[cfg(test)]
mod ignore_tests;
#[cfg(test)]
mod preview_tests;
#[cfg(test)]
mod replace_tests;
#[cfg(test)]
mod tests;

pub(super) const DEFAULT_MAX_RESULTS: u32 = 2000;
pub(super) const MAX_RESULTS_CAP: u32 = 2000;
pub(super) const MAX_MATCHES_PER_FILE: u32 = 100;
pub(super) const MAX_TEXT_FILE_BYTES: u64 = 5 * 1024 * 1024;
pub(super) const MAX_LINE_CONTENT_LENGTH: usize = 500;
pub(super) const PROTECTED_NAMES: [&str; 3] = [".git", ".hg", ".svn"];
const CANCEL_TOMBSTONE_TTL: Duration = Duration::from_secs(30);

#[derive(Debug, Clone)]
pub struct WorkspaceSearchOptions {
    pub workspace_path: String,
    pub query: String,
    pub case_sensitive: bool,
    pub whole_word: bool,
    pub use_regex: bool,
    pub include_pattern: Option<String>,
    pub exclude_pattern: Option<String>,
    pub include_ignored: bool,
    pub max_results: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceReplaceOptions {
    pub search: WorkspaceSearchOptions,
    pub replacement: String,
    pub preserve_case: bool,
}

#[derive(Debug, Clone)]
pub struct WorkspaceReplaceRequest {
    pub options: WorkspaceReplaceOptions,
    pub match_ids: Vec<String>,
    pub expected_files: Vec<WorkspaceReplaceFileExpectation>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceReplaceFileExpectation {
    pub relative_path: String,
    pub content_token: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSearchResult {
    pub files: Vec<WorkspaceSearchFileResult>,
    pub total_matches: u32,
    pub truncated: bool,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSearchFileResult {
    pub relative_path: String,
    pub content_token: String,
    pub matches: Vec<WorkspaceSearchMatch>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSearchMatch {
    pub id: String,
    pub line: u32,
    pub column: u32,
    pub match_length: u32,
    pub line_content: String,
    pub display_column: Option<u32>,
    pub display_match_length: Option<u32>,
    pub replacement_preview: Option<String>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceReplacePreview {
    pub result: WorkspaceSearchResult,
    pub replacement: String,
    pub preserve_case: bool,
}

#[derive(Debug, Clone)]
pub struct WorkspaceReplaceResult {
    pub files_changed: u32,
    pub matches_replaced: u32,
    pub conflicts: Vec<WorkspaceReplaceConflict>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceReplaceConflict {
    pub relative_path: String,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceSearchErrorKind {
    InvalidPath,
    OutsideWorkspace,
    InvalidPattern,
    Io,
    Cancelled,
}

#[derive(Debug)]
pub struct WorkspaceSearchError {
    pub kind: WorkspaceSearchErrorKind,
    pub context: String,
}

impl WorkspaceSearchError {
    pub(super) fn new(kind: WorkspaceSearchErrorKind, context: impl Into<String>) -> Self {
        Self {
            kind,
            context: context.into(),
        }
    }

    pub(super) fn from_io(error: io::Error, context: impl Into<String>) -> Self {
        Self::new(
            WorkspaceSearchErrorKind::Io,
            format!("{}: {error}", context.into()),
        )
    }
}

pub fn search_workspace(
    options: WorkspaceSearchOptions,
) -> Result<WorkspaceSearchResult, WorkspaceSearchError> {
    let compiled = compile::compile_search(&options)?;
    engine::run_search(&compiled, false, None)
}

pub fn search_workspace_cancelable(
    options: WorkspaceSearchOptions,
    request_id: String,
) -> Result<WorkspaceSearchResult, WorkspaceSearchError> {
    let cancellation = SearchCancellation::begin(request_id);
    let compiled = compile::compile_search(&options)?;
    engine::run_search(&compiled, false, Some(&cancellation.flag))
}

pub fn preview_workspace_replace(
    options: WorkspaceReplaceOptions,
) -> Result<WorkspaceReplacePreview, WorkspaceSearchError> {
    preview::preview_workspace_replace_impl(options, None)
}

pub fn preview_workspace_replace_cancelable(
    options: WorkspaceReplaceOptions,
    request_id: String,
) -> Result<WorkspaceReplacePreview, WorkspaceSearchError> {
    let cancellation = SearchCancellation::begin(request_id);
    preview::preview_workspace_replace_impl(options, Some(&cancellation.flag))
}

pub fn replace_workspace_matches(
    request: WorkspaceReplaceRequest,
) -> Result<WorkspaceReplaceResult, WorkspaceSearchError> {
    replace::replace_workspace_matches_impl(request)
}

pub fn cancel_workspace_search(request_id: String) {
    let mut searches = active_searches()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    prune_cancel_tombstones(&mut searches);
    let entry = searches.entry(request_id).or_insert_with(|| SearchEntry {
        flag: Arc::new(AtomicBool::new(false)),
        touched_at: Instant::now(),
        active: false,
    });
    entry.touched_at = Instant::now();
    entry.flag.store(true, Ordering::Relaxed);
}

static ACTIVE_SEARCHES: OnceLock<Mutex<HashMap<String, SearchEntry>>> = OnceLock::new();

fn active_searches() -> &'static Mutex<HashMap<String, SearchEntry>> {
    ACTIVE_SEARCHES.get_or_init(|| Mutex::new(HashMap::new()))
}

struct SearchEntry {
    flag: Arc<AtomicBool>,
    touched_at: Instant,
    active: bool,
}

fn prune_cancel_tombstones(searches: &mut HashMap<String, SearchEntry>) {
    searches.retain(|_, entry| entry.active || entry.touched_at.elapsed() < CANCEL_TOMBSTONE_TTL);
}

struct SearchCancellation {
    request_id: String,
    flag: Arc<AtomicBool>,
}

impl SearchCancellation {
    fn begin(request_id: String) -> Self {
        let mut searches = active_searches()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        prune_cancel_tombstones(&mut searches);
        let entry = searches
            .entry(request_id.clone())
            .or_insert_with(|| SearchEntry {
                flag: Arc::new(AtomicBool::new(false)),
                touched_at: Instant::now(),
                active: false,
            });
        entry.active = true;
        entry.touched_at = Instant::now();
        let flag = entry.flag.clone();
        Self { request_id, flag }
    }
}

impl Drop for SearchCancellation {
    fn drop(&mut self) {
        let mut searches = active_searches()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if searches
            .get(&self.request_id)
            .is_some_and(|current| Arc::ptr_eq(&current.flag, &self.flag))
        {
            searches.remove(&self.request_id);
        }
    }
}
