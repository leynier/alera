use regex::Regex;

use super::compile::{compile_search, CompiledSearch};
use super::engine::run_search;
use super::{
    WorkspaceReplaceOptions, WorkspaceReplacePreview, WorkspaceSearchError, WorkspaceSearchMatch,
};

pub(super) fn preview_workspace_replace_impl(
    options: WorkspaceReplaceOptions,
) -> Result<WorkspaceReplacePreview, WorkspaceSearchError> {
    let compiled = compile_search(&options.search)?;
    let mut result = run_search(&compiled, Some(&options), false)?;
    for file in &mut result.files {
        for m in &mut file.matches {
            m.replacement_preview = Some(preview_replacement(m, &compiled, &options));
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
    compiled: &CompiledSearch,
    options: &WorkspaceReplaceOptions,
) -> String {
    let col = m.display_column.unwrap_or(m.column).saturating_sub(1) as usize;
    let len = m.display_match_length.unwrap_or(m.match_length) as usize;
    let chars = m.line_content.chars().collect::<Vec<_>>();
    if col + len > chars.len() {
        return options.replacement.clone();
    }
    let matched = chars[col..col + len].iter().collect::<String>();
    replacement_for_slice(&matched, &compiled.replacement_regex, options)
}

pub(super) fn replacement_for_slice(
    matched: &str,
    regex: &Regex,
    options: &WorkspaceReplaceOptions,
) -> String {
    let replacement = if options.search.use_regex {
        regex
            .replace(matched, options.replacement.as_str())
            .to_string()
    } else {
        options.replacement.clone()
    };
    if options.preserve_case {
        preserve_case(matched, &replacement)
    } else {
        replacement
    }
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
            return first.to_uppercase().collect::<String>() + chars.as_str();
        }
    }
    replacement.to_string()
}
