use std::collections::{HashMap, HashSet};
use std::fs;

use super::compile::compile_search;
use super::engine::run_search;
use super::line_ranges::LineRanges;
use super::paths::{content_token, resolve_replace_file};
use super::preview::replacement_for_match;
use super::{
    WorkspaceReplaceConflict, WorkspaceReplaceRequest, WorkspaceReplaceResult,
    WorkspaceSearchError, WorkspaceSearchErrorKind,
};

pub(super) fn replace_workspace_matches_impl(
    request: WorkspaceReplaceRequest,
) -> Result<WorkspaceReplaceResult, WorkspaceSearchError> {
    replace_with_file_checkpoint(request, |_, _| {})
}

pub(super) fn replace_with_file_checkpoint(
    request: WorkspaceReplaceRequest,
    mut checkpoint: impl FnMut(&std::path::Path, bool),
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
    let matches = run_search(&compiled, true, None)?;
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
        checkpoint(&path, false);
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
        if content_token(&content) != file.content_token {
            conflicts.push(WorkspaceReplaceConflict {
                relative_path: file.relative_path,
                reason: "File changed on disk".to_string(),
            });
            continue;
        }
        let line_ranges = LineRanges::new(&content);
        let mut ranges = Vec::new();
        let selected_matches_count = selected_matches.len();
        for m in selected_matches {
            if let Some(range) =
                line_ranges.locate_match_range(&content, m.line, m.column, m.match_length)
            {
                if let Some((line, start, end)) =
                    line_ranges.match_context(&content, m.line, m.column, m.match_length)
                {
                    if let Some(replacement) = replacement_for_match(
                        line,
                        start,
                        end,
                        &compiled.replacement_regex,
                        &request.options,
                    ) {
                        ranges.push((range.0, range.1, replacement));
                    }
                }
            }
        }
        if ranges.len() != selected_matches_count {
            conflicts.push(WorkspaceReplaceConflict {
                relative_path: file.relative_path,
                reason: "Selected match is no longer available".to_string(),
            });
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
        checkpoint(&path, true);
        if resolve_replace_file(&compiled.root, &file.relative_path).is_err()
            || fs::read(&path).ok().as_deref() != Some(content.as_bytes())
        {
            conflicts.push(WorkspaceReplaceConflict {
                relative_path: file.relative_path,
                reason: "File changed on disk".to_string(),
            });
            continue;
        }
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
