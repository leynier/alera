use std::fs;
use std::sync::atomic::AtomicBool;

use regex::Regex;

use super::compile::{compile_search, CompiledSearch};
use super::engine::{ensure_not_cancelled, run_search};
use super::line_ranges::LineRanges;
use super::paths::{content_token, resolve_replace_file};
use super::{
    WorkspaceReplaceOptions, WorkspaceReplacePreview, WorkspaceSearchError,
    WorkspaceSearchErrorKind, WorkspaceSearchMatch,
};

pub(super) fn preview_workspace_replace_impl(
    options: WorkspaceReplaceOptions,
    cancellation: Option<&AtomicBool>,
) -> Result<WorkspaceReplacePreview, WorkspaceSearchError> {
    let compiled = compile_search(&options.search)?;
    let mut result = run_search(&compiled, false, cancellation)?;
    for file in &mut result.files {
        ensure_not_cancelled(cancellation)?;
        let (path, _) = resolve_replace_file(&compiled.root, &file.relative_path)?;
        let content = fs::read_to_string(&path)
            .map_err(|error| WorkspaceSearchError::from_io(error, file.relative_path.clone()))?;
        if content_token(&content) != file.content_token {
            return Err(WorkspaceSearchError::new(
                WorkspaceSearchErrorKind::Io,
                "File changed while preparing replacement previews.",
            ));
        }
        let line_ranges = LineRanges::new(&content);
        for m in &mut file.matches {
            ensure_not_cancelled(cancellation)?;
            m.replacement_preview = Some(preview_replacement(
                m,
                &content,
                &line_ranges,
                &compiled,
                &options,
            ));
        }
    }
    Ok(WorkspaceReplacePreview {
        result,
        replacement: options.replacement,
        preserve_case: options.preserve_case,
    })
}

pub(super) fn preview_replacement(
    m: &WorkspaceSearchMatch,
    content: &str,
    line_ranges: &LineRanges,
    compiled: &CompiledSearch,
    options: &WorkspaceReplaceOptions,
) -> String {
    line_ranges
        .match_context(content, m.line, m.column, m.match_length)
        .and_then(|(line, start, end)| {
            replacement_for_match(line, start, end, &compiled.replacement_regex, options)
        })
        .unwrap_or_else(|| options.replacement.clone())
}

pub(super) fn replacement_for_match(
    line: &str,
    start: usize,
    end: usize,
    regex: &Regex,
    options: &WorkspaceReplaceOptions,
) -> Option<String> {
    let matched = line.get(start..end)?;
    let replacement = if options.search.use_regex {
        let captures = regex.captures_at(line, start)?;
        let whole = captures.get(0)?;
        if whole.start() != start || whole.end() != end {
            return None;
        }
        let mut expanded = String::new();
        captures.expand(&options.replacement, &mut expanded);
        expanded
    } else {
        options.replacement.clone()
    };
    Some(if options.preserve_case {
        preserve_case(matched, &replacement)
    } else {
        replacement
    })
}

pub(super) fn preserve_case(source: &str, replacement: &str) -> String {
    let has_alphabetic = source.chars().any(char::is_alphabetic);
    if has_alphabetic
        && source
            .chars()
            .all(|c| !c.is_alphabetic() || c.is_uppercase())
    {
        return replacement.to_uppercase();
    }
    if source.chars().next().is_some_and(|c| c.is_uppercase())
        && source
            .chars()
            .skip(1)
            .all(|c| !c.is_alphabetic() || c.is_lowercase())
    {
        let mut chars = replacement.chars();
        if let Some(first) = chars.next() {
            return first.to_uppercase().collect::<String>() + &chars.as_str().to_lowercase();
        }
    }
    replacement.to_string()
}
