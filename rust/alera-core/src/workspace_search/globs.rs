use globset::{Glob, GlobSet, GlobSetBuilder};

use super::{WorkspaceSearchError, WorkspaceSearchErrorKind};

pub(super) fn build_globs(
    patterns: Option<&str>,
    exclude: bool,
) -> Result<Option<GlobSet>, WorkspaceSearchError> {
    let Some(patterns) = patterns else {
        return Ok(None);
    };
    let split = split_search_glob_patterns(patterns);
    if split.is_empty() {
        return Ok(None);
    }
    let mut builder = GlobSetBuilder::new();
    for pattern in split {
        let normalized = pattern.replace('\\', "/");
        add_glob(&mut builder, &normalized)?;
        if !normalized.contains('/') {
            add_glob(&mut builder, &format!("**/{normalized}"))?;
        }
    }
    builder.build().map(Some).map_err(|error| {
        WorkspaceSearchError::new(
            WorkspaceSearchErrorKind::InvalidPattern,
            format!("{exclude}: {error}"),
        )
    })
}

fn add_glob(builder: &mut GlobSetBuilder, pattern: &str) -> Result<(), WorkspaceSearchError> {
    let glob = Glob::new(pattern).map_err(|error| {
        WorkspaceSearchError::new(WorkspaceSearchErrorKind::InvalidPattern, error.to_string())
    })?;
    builder.add(glob);
    Ok(())
}

pub(super) fn split_search_glob_patterns(patterns: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut chars = patterns.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\\' {
            if chars.peek().is_some_and(|next| *next == ',') {
                current.push(',');
                chars.next();
            } else {
                current.push(ch);
            }
            continue;
        }
        if ch == ',' {
            let trimmed = current.trim();
            if !trimmed.is_empty() {
                out.push(trimmed.to_string());
            }
            current.clear();
            continue;
        }
        current.push(ch);
    }
    let trimmed = current.trim();
    if !trimmed.is_empty() {
        out.push(trimmed.to_string());
    }
    out
}

pub(super) fn matches_globs(relative_path: &str, globs: &Option<GlobSet>, default: bool) -> bool {
    globs
        .as_ref()
        .map_or(default, |set| set.is_match(relative_path))
}
