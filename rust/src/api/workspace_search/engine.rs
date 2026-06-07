use std::fs;

use grep_matcher::Matcher;
use ignore::WalkBuilder;

use super::compile::CompiledSearch;
use super::globs::matches_globs;
use super::paths::{
    content_token, is_protected_relative_path, relative_string, safe_regular_file_metadata,
    should_walk_entry,
};
use super::{
    WorkspaceSearchError, WorkspaceSearchErrorKind, WorkspaceSearchFileResult,
    WorkspaceSearchMatch, WorkspaceSearchResult, MAX_LINE_CONTENT_LENGTH, MAX_MATCHES_PER_FILE,
    MAX_TEXT_FILE_BYTES,
};

pub(super) fn run_search(
    compiled: &CompiledSearch,
    full_lines: bool,
) -> Result<WorkspaceSearchResult, WorkspaceSearchError> {
    let mut files = Vec::<WorkspaceSearchFileResult>::new();
    let mut total_matches = 0_u32;
    let mut truncated = false;
    let mut walker = WalkBuilder::new(&compiled.root);
    let root = compiled.root.clone();
    walker
        .hidden(false)
        .git_ignore(true)
        .git_exclude(true)
        .parents(true)
        .filter_entry(move |entry| should_walk_entry(&root, entry.path()));
    if compiled.include_ignored {
        walker
            .ignore(false)
            .git_global(false)
            .git_ignore(false)
            .git_exclude(false);
    }

    for entry in walker.build() {
        if total_matches >= compiled.max_results {
            truncated = true;
            break;
        }
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let path = entry.path();
        if path == compiled.root {
            continue;
        }
        let file_type = match entry.file_type() {
            Some(file_type) => file_type,
            None => continue,
        };
        if !file_type.is_file() || file_type.is_symlink() {
            continue;
        }
        let relative_path = match relative_string(&compiled.root, path) {
            Some(path) => path,
            None => continue,
        };
        if is_protected_relative_path(&relative_path) {
            continue;
        }
        if !matches_globs(&relative_path, &compiled.include, true)
            || matches_globs(&relative_path, &compiled.exclude, false)
        {
            continue;
        }
        let metadata = match safe_regular_file_metadata(&compiled.root, path, &relative_path) {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };
        if metadata.len() > MAX_TEXT_FILE_BYTES {
            continue;
        }
        let bytes = match fs::read(path) {
            Ok(bytes) => bytes,
            Err(_) => continue,
        };
        if bytes.contains(&0) {
            continue;
        }
        let text = match String::from_utf8(bytes) {
            Ok(text) => text,
            Err(_) => continue,
        };
        let matches = matches_in_file(
            &relative_path,
            &text,
            compiled,
            full_lines,
            &mut total_matches,
            &mut truncated,
        )?;
        if !matches.is_empty() {
            files.push(WorkspaceSearchFileResult {
                relative_path,
                content_token: content_token(&metadata),
                matches,
            });
        }
    }

    Ok(WorkspaceSearchResult {
        files,
        total_matches,
        truncated,
    })
}

fn matches_in_file(
    relative_path: &str,
    text: &str,
    compiled: &CompiledSearch,
    full_lines: bool,
    total_matches: &mut u32,
    truncated: &mut bool,
) -> Result<Vec<WorkspaceSearchMatch>, WorkspaceSearchError> {
    let mut out = Vec::new();
    for (line_index, line) in text.lines().enumerate() {
        if *total_matches >= compiled.max_results {
            *truncated = true;
            break;
        }
        let line_bytes = line.as_bytes();
        let mut file_count = out.len() as u32;
        compiled
            .matcher
            .find_iter(line_bytes, |m| {
                if *total_matches >= compiled.max_results || file_count >= MAX_MATCHES_PER_FILE {
                    *truncated = true;
                    return false;
                }
                let start = m.start();
                let end = m.end();
                let column = line[..start].chars().count() as u32 + 1;
                let match_length = line[start..end].chars().count() as u32;
                let line_number = line_index as u32 + 1;
                let clamped = if full_lines {
                    LinePreview {
                        line_content: line.to_string(),
                        display_column: None,
                        display_match_length: None,
                    }
                } else {
                    clamp_line_context(line, start, end)
                };
                let id = format!("{relative_path}:{line_number}:{column}:{}", out.len());
                out.push(WorkspaceSearchMatch {
                    id,
                    line: line_number,
                    column,
                    match_length,
                    line_content: clamped.line_content,
                    display_column: clamped.display_column,
                    display_match_length: clamped.display_match_length,
                    replacement_preview: None,
                });
                *total_matches += 1;
                file_count += 1;
                true
            })
            .map_err(|error| {
                WorkspaceSearchError::new(
                    WorkspaceSearchErrorKind::InvalidPattern,
                    error.to_string(),
                )
            })?;
    }
    Ok(out)
}

struct LinePreview {
    line_content: String,
    display_column: Option<u32>,
    display_match_length: Option<u32>,
}

fn clamp_line_context(line: &str, start_byte: usize, end_byte: usize) -> LinePreview {
    let chars = line.chars().collect::<Vec<_>>();
    let start = line[..start_byte].chars().count();
    let end = line[..end_byte].chars().count();
    let match_len = end.saturating_sub(start);
    if chars.len() <= MAX_LINE_CONTENT_LENGTH {
        return LinePreview {
            line_content: line.to_string(),
            display_column: None,
            display_match_length: None,
        };
    }
    let clamped_match_len = match_len.min(MAX_LINE_CONTENT_LENGTH);
    let remaining = MAX_LINE_CONTENT_LENGTH.saturating_sub(clamped_match_len);
    let left_budget = remaining / 2;
    let mut window_start = start.saturating_sub(left_budget);
    let window_end = (window_start + MAX_LINE_CONTENT_LENGTH).min(chars.len());
    window_start = window_end.saturating_sub(MAX_LINE_CONTENT_LENGTH);
    let mut snippet = chars[window_start..window_end].iter().collect::<String>();
    let mut display_column = start.saturating_sub(window_start) as u32 + 1;
    if window_start > 0 {
        snippet.insert(0, '…');
        display_column += 1;
    }
    if window_end < chars.len() {
        snippet.push('…');
    }
    LinePreview {
        line_content: snippet,
        display_column: Some(display_column),
        display_match_length: Some(clamped_match_len as u32),
    }
}
