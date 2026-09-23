//! FRB facade over `alera_core::workspace_search`. The engine lives in
//! `alera-core` so the terminal-host sidecar serves the paired phone from the
//! same code; the types stay defined here so the generated Dart bindings do not
//! depend on another crate.

use alera_core::workspace_search as engine;

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

pub fn search_workspace(
    options: WorkspaceSearchOptions,
) -> Result<WorkspaceSearchResult, WorkspaceSearchError> {
    engine::search_workspace(options.into())
        .map(Into::into)
        .map_err(Into::into)
}

pub fn search_workspace_cancelable(
    options: WorkspaceSearchOptions,
    request_id: String,
) -> Result<WorkspaceSearchResult, WorkspaceSearchError> {
    engine::search_workspace_cancelable(options.into(), request_id)
        .map(Into::into)
        .map_err(Into::into)
}

pub fn preview_workspace_replace(
    options: WorkspaceReplaceOptions,
) -> Result<WorkspaceReplacePreview, WorkspaceSearchError> {
    engine::preview_workspace_replace(options.into())
        .map(Into::into)
        .map_err(Into::into)
}

pub fn preview_workspace_replace_cancelable(
    options: WorkspaceReplaceOptions,
    request_id: String,
) -> Result<WorkspaceReplacePreview, WorkspaceSearchError> {
    engine::preview_workspace_replace_cancelable(options.into(), request_id)
        .map(Into::into)
        .map_err(Into::into)
}

pub fn replace_workspace_matches(
    request: WorkspaceReplaceRequest,
) -> Result<WorkspaceReplaceResult, WorkspaceSearchError> {
    engine::replace_workspace_matches(request.into())
        .map(Into::into)
        .map_err(Into::into)
}

pub fn cancel_workspace_search(request_id: String) {
    engine::cancel_workspace_search(request_id);
}

impl From<WorkspaceSearchOptions> for engine::WorkspaceSearchOptions {
    fn from(options: WorkspaceSearchOptions) -> Self {
        Self {
            workspace_path: options.workspace_path,
            query: options.query,
            case_sensitive: options.case_sensitive,
            whole_word: options.whole_word,
            use_regex: options.use_regex,
            include_pattern: options.include_pattern,
            exclude_pattern: options.exclude_pattern,
            include_ignored: options.include_ignored,
            max_results: options.max_results,
        }
    }
}

impl From<WorkspaceReplaceOptions> for engine::WorkspaceReplaceOptions {
    fn from(options: WorkspaceReplaceOptions) -> Self {
        Self {
            search: options.search.into(),
            replacement: options.replacement,
            preserve_case: options.preserve_case,
        }
    }
}

impl From<WorkspaceReplaceRequest> for engine::WorkspaceReplaceRequest {
    fn from(request: WorkspaceReplaceRequest) -> Self {
        Self {
            options: request.options.into(),
            match_ids: request.match_ids,
            expected_files: request
                .expected_files
                .into_iter()
                .map(|file| engine::WorkspaceReplaceFileExpectation {
                    relative_path: file.relative_path,
                    content_token: file.content_token,
                })
                .collect(),
        }
    }
}

impl From<engine::WorkspaceSearchResult> for WorkspaceSearchResult {
    fn from(result: engine::WorkspaceSearchResult) -> Self {
        Self {
            files: result.files.into_iter().map(Into::into).collect(),
            total_matches: result.total_matches,
            truncated: result.truncated,
        }
    }
}

impl From<engine::WorkspaceSearchFileResult> for WorkspaceSearchFileResult {
    fn from(file: engine::WorkspaceSearchFileResult) -> Self {
        Self {
            relative_path: file.relative_path,
            content_token: file.content_token,
            matches: file.matches.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<engine::WorkspaceSearchMatch> for WorkspaceSearchMatch {
    fn from(m: engine::WorkspaceSearchMatch) -> Self {
        Self {
            id: m.id,
            line: m.line,
            column: m.column,
            match_length: m.match_length,
            line_content: m.line_content,
            display_column: m.display_column,
            display_match_length: m.display_match_length,
            replacement_preview: m.replacement_preview,
        }
    }
}

impl From<engine::WorkspaceReplacePreview> for WorkspaceReplacePreview {
    fn from(preview: engine::WorkspaceReplacePreview) -> Self {
        Self {
            result: preview.result.into(),
            replacement: preview.replacement,
            preserve_case: preview.preserve_case,
        }
    }
}

impl From<engine::WorkspaceReplaceResult> for WorkspaceReplaceResult {
    fn from(result: engine::WorkspaceReplaceResult) -> Self {
        Self {
            files_changed: result.files_changed,
            matches_replaced: result.matches_replaced,
            conflicts: result
                .conflicts
                .into_iter()
                .map(|conflict| WorkspaceReplaceConflict {
                    relative_path: conflict.relative_path,
                    reason: conflict.reason,
                })
                .collect(),
        }
    }
}

impl From<engine::WorkspaceSearchError> for WorkspaceSearchError {
    fn from(error: engine::WorkspaceSearchError) -> Self {
        Self {
            kind: match error.kind {
                engine::WorkspaceSearchErrorKind::InvalidPath => {
                    WorkspaceSearchErrorKind::InvalidPath
                }
                engine::WorkspaceSearchErrorKind::OutsideWorkspace => {
                    WorkspaceSearchErrorKind::OutsideWorkspace
                }
                engine::WorkspaceSearchErrorKind::InvalidPattern => {
                    WorkspaceSearchErrorKind::InvalidPattern
                }
                engine::WorkspaceSearchErrorKind::Io => WorkspaceSearchErrorKind::Io,
                engine::WorkspaceSearchErrorKind::Cancelled => WorkspaceSearchErrorKind::Cancelled,
            },
            context: error.context,
        }
    }
}
