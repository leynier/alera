use std::collections::{HashMap, HashSet};
use std::fs;

use super::compile::compile_search;
use super::engine::run_search;
use super::paths::resolve_replace_file;
use super::preview::replacement_for_slice;
use super::{
    WorkspaceReplaceConflict, WorkspaceReplaceRequest, WorkspaceReplaceResult,
    WorkspaceSearchError, WorkspaceSearchErrorKind,
};

pub(super) fn replace_workspace_matches_impl(
    request: WorkspaceReplaceRequest,
) -> Result<WorkspaceReplaceResult, WorkspaceSearchError> {
    let compiled = compile_search(&request.options.search)?;
    let expected = request
        .expected_files
        .into_iter()
        .map(|file| (file.relative_path, file.content_token))
        .collect::<HashMap<_, _>>();
    let selected = if request.match_ids.is_empty() {
        None
    } else {
        Some(request.match_ids.into_iter().collect::<HashSet<_>>())
    };
    let matches = run_search(&compiled, true)?;
    if selected.is_none() && matches.truncated {
        return Err(WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::InvalidPattern,
            "Replace all is unavailable while results are truncated.",
        ));
    }
    let mut files_changed = 0_u32;
    let mut matches_replaced = 0_u32;
    let mut conflicts = Vec::new();

    if let Some(selected_ids) = &selected {
        let found_ids = matches
            .files
            .iter()
            .flat_map(|file| file.matches.iter())
            .filter_map(|m| selected_ids.contains(&m.id).then_some(m.id.as_str()))
            .collect::<HashSet<_>>();
        for id in selected_ids {
            if !found_ids.contains(id.as_str()) {
                conflicts.push(WorkspaceReplaceConflict {
                    relative_path: relative_path_from_match_id(id),
                    reason: "Selected match is no longer available".to_string(),
                });
            }
        }
    }

    for file in matches.files {
        let selected_matches = file
            .matches
            .iter()
            .filter(|m| selected.as_ref().is_none_or(|ids| ids.contains(&m.id)))
            .collect::<Vec<_>>();
        if selected_matches.is_empty() {
            continue;
        }
        match expected.get(&file.relative_path) {
            Some(token) if token == &file.content_token => {}
            Some(_) => {
                conflicts.push(WorkspaceReplaceConflict {
                    relative_path: file.relative_path,
                    reason: "File changed on disk".to_string(),
                });
                continue;
            }
            None => {
                conflicts.push(WorkspaceReplaceConflict {
                    relative_path: file.relative_path,
                    reason: "File was not part of the preview".to_string(),
                });
                continue;
            }
        }
        let (path, _) = match resolve_replace_file(&compiled.root, &file.relative_path) {
            Ok(resolved) => resolved,
            Err(error) => {
                conflicts.push(WorkspaceReplaceConflict {
                    relative_path: file.relative_path,
                    reason: error.context,
                });
                continue;
            }
        };
        let content = match fs::read_to_string(&path) {
            Ok(content) => content,
            Err(error) => {
                conflicts.push(WorkspaceReplaceConflict {
                    relative_path: file.relative_path,
                    reason: format!("Could not read file: {error}"),
                });
                continue;
            }
        };
        let line_ranges = LineRanges::new(&content);
        let mut ranges = Vec::new();
        for m in selected_matches {
            if let Some(range) =
                line_ranges.locate_match_range(&content, m.line, m.column, m.match_length)
            {
                let replacement = replacement_for_slice(
                    &content[range.0..range.1],
                    &compiled.replacement_regex,
                    &request.options,
                );
                ranges.push((range.0, range.1, replacement));
            }
        }
        if ranges.is_empty() {
            continue;
        }
        ranges.sort_by_key(|range| range.0);
        let mut next = String::with_capacity(content.len());
        let mut cursor = 0;
        let mut file_matches_replaced = 0_u32;
        for (start, end, replacement) in ranges {
            if start < cursor {
                continue;
            }
            next.push_str(&content[cursor..start]);
            next.push_str(&replacement);
            cursor = end;
            file_matches_replaced += 1;
        }
        next.push_str(&content[cursor..]);
        if let Err(error) = fs::write(&path, next) {
            conflicts.push(WorkspaceReplaceConflict {
                relative_path: file.relative_path,
                reason: format!("Could not write file: {error}"),
            });
            continue;
        }
        matches_replaced += file_matches_replaced;
        files_changed += 1;
    }

    Ok(WorkspaceReplaceResult {
        files_changed,
        matches_replaced,
        conflicts,
    })
}

struct LineRanges {
    ranges: Vec<LineRange>,
}

impl LineRanges {
    fn new(content: &str) -> Self {
        let mut ranges = Vec::new();
        let mut start = 0;
        for line in content.split_inclusive('\n') {
            let mut end = start + line.len();
            if line.ends_with('\n') {
                end -= 1;
            }
            if end > start && content.as_bytes()[end - 1] == b'\r' {
                end -= 1;
            }
            ranges.push(LineRange { start, end });
            start += line.len();
        }
        Self { ranges }
    }

    fn locate_match_range(
        &self,
        content: &str,
        line_number: u32,
        column: u32,
        match_length: u32,
    ) -> Option<(usize, usize)> {
        let line = self.ranges.get(line_number.checked_sub(1)? as usize)?;
        let clean_line = &content[line.start..line.end];
        let start_col = column.saturating_sub(1) as usize;
        let start_byte = byte_offset_for_char(clean_line, start_col);
        let end_byte = byte_offset_for_char(clean_line, start_col + match_length as usize);
        Some((line.start + start_byte, line.start + end_byte))
    }
}

struct LineRange {
    start: usize,
    end: usize,
}

fn byte_offset_for_char(text: &str, char_offset: usize) -> usize {
    text.char_indices()
        .nth(char_offset)
        .map(|(byte, _)| byte)
        .unwrap_or(text.len())
}

fn relative_path_from_match_id(id: &str) -> String {
    let mut parts = id.rsplitn(4, ':');
    let index = parts.next();
    let column = parts.next();
    let line = parts.next();
    let path = parts.next();
    if index.and_then(|value| value.parse::<u32>().ok()).is_some()
        && column.and_then(|value| value.parse::<u32>().ok()).is_some()
        && line.and_then(|value| value.parse::<u32>().ok()).is_some()
    {
        if let Some(path) = path {
            if !path.is_empty() {
                return path.to_string();
            }
        }
    }
    "unknown".to_string()
}
