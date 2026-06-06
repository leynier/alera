use std::path::PathBuf;

use globset::GlobSet;
use grep_regex::{RegexMatcher, RegexMatcherBuilder};
use regex::Regex;

use super::globs::build_globs;
use super::paths::workspace_root;
use super::{
    WorkspaceSearchError, WorkspaceSearchErrorKind, WorkspaceSearchOptions, DEFAULT_MAX_RESULTS,
    MAX_RESULTS_CAP,
};

pub(super) struct CompiledSearch {
    pub(super) root: PathBuf,
    pub(super) matcher: RegexMatcher,
    pub(super) replacement_regex: Regex,
    pub(super) include: Option<GlobSet>,
    pub(super) exclude: Option<GlobSet>,
    pub(super) max_results: u32,
}

pub(super) fn compile_search(
    options: &WorkspaceSearchOptions,
) -> Result<CompiledSearch, WorkspaceSearchError> {
    let root = workspace_root(&options.workspace_path)?;
    if options.query.is_empty() {
        return Err(WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::InvalidPattern,
            "query is empty",
        ));
    }
    let mut builder = RegexMatcherBuilder::new();
    builder
        .case_insensitive(!options.case_sensitive)
        .word(options.whole_word)
        .fixed_strings(!options.use_regex)
        .multi_line(true)
        .line_terminator(Some(b'\n'));
    let matcher = builder.build(&options.query).map_err(|error| {
        WorkspaceSearchError::new(WorkspaceSearchErrorKind::InvalidPattern, error.to_string())
    })?;

    let regex_pattern = if options.use_regex {
        options.query.clone()
    } else {
        regex::escape(&options.query)
    };
    let regex_pattern = if options.whole_word {
        format!(r"\b(?:{regex_pattern})\b")
    } else {
        regex_pattern
    };
    let regex_pattern = if options.case_sensitive {
        regex_pattern
    } else {
        format!("(?i:{regex_pattern})")
    };
    let replacement_regex = Regex::new(&regex_pattern).map_err(|error| {
        WorkspaceSearchError::new(WorkspaceSearchErrorKind::InvalidPattern, error.to_string())
    })?;

    Ok(CompiledSearch {
        root,
        matcher,
        replacement_regex,
        include: build_globs(options.include_pattern.as_deref(), false)?,
        exclude: build_globs(options.exclude_pattern.as_deref(), true)?,
        max_results: options
            .max_results
            .unwrap_or(DEFAULT_MAX_RESULTS)
            .clamp(1, MAX_RESULTS_CAP),
    })
}
