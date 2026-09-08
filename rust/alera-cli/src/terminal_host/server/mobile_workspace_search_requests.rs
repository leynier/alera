use std::fs;
use std::path::Path;

use alera_core::runtime::RuntimeStore;
use alera_core::workspace_files::is_protected_workspace_path;
use ignore::overrides::OverrideBuilder;
use ignore::WalkBuilder;
use regex::{Regex, RegexBuilder};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::require_string_key;

const DEFAULT_MAX_RESULTS: u32 = 2000;
const MAX_RESULTS_CAP: u32 = 2000;
const MAX_MATCHES_PER_FILE: u32 = 100;
const MAX_TEXT_FILE_BYTES: u64 = 5 * 1024 * 1024;
const MAX_LINE_CONTENT_LENGTH: usize = 500;

pub(super) async fn search_mobile_workspace(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let query = require_string_key(payload, "query")?;
    if query.trim().is_empty() {
        return Ok(json!({
            "files": [],
            "totalMatches": 0,
            "truncated": false,
        }));
    }
    let options = SearchOptions {
        workspace_path: workspace.path,
        query,
        case_sensitive: payload
            .get("caseSensitive")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        whole_word: payload
            .get("wholeWord")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        use_regex: payload
            .get("useRegex")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        include_pattern: optional_pattern(payload, "includePattern"),
        exclude_pattern: optional_pattern(payload, "excludePattern"),
        include_ignored: payload
            .get("includeIgnored")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        max_results: payload
            .get("maxResults")
            .and_then(Value::as_u64)
            .and_then(|value| u32::try_from(value).ok())
            .unwrap_or(DEFAULT_MAX_RESULTS)
            .clamp(1, MAX_RESULTS_CAP),
    };
    spawn_blocking_workspace("Workspace search", move || run_search(options)).await
}

struct SearchOptions {
    workspace_path: String,
    query: String,
    case_sensitive: bool,
    whole_word: bool,
    use_regex: bool,
    include_pattern: Option<String>,
    exclude_pattern: Option<String>,
    include_ignored: bool,
    max_results: u32,
}

fn optional_pattern(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn run_search(options: SearchOptions) -> HostResult<Value> {
    let root = fs::canonicalize(&options.workspace_path).map_err(|error| {
        HostError::state(format!("Workspace search root is unavailable: {error}"))
    })?;
    if !root.is_dir() {
        return Err(HostError::state(
            "Workspace search root is not a directory.",
        ));
    }
    let matcher = compile_matcher(&options)?;
    let overrides = build_overrides(
        &root,
        options.include_pattern.as_deref(),
        options.exclude_pattern.as_deref(),
    )?;
    let mut walker = WalkBuilder::new(&root);
    walker
        .hidden(false)
        .parents(true)
        .follow_links(false)
        .require_git(false);
    if options.include_ignored {
        walker
            .ignore(false)
            .git_global(false)
            .git_ignore(false)
            .git_exclude(false);
    }
    if let Some(overrides) = overrides {
        walker.overrides(overrides);
    }

    let mut files = Vec::new();
    let mut total_matches = 0_u32;
    let mut truncated = false;
    for entry in walker.build() {
        if total_matches >= options.max_results {
            truncated = true;
            break;
        }
        let Ok(entry) = entry else {
            continue;
        };
        let path = entry.path();
        if path == root {
            continue;
        }
        let Some(file_type) = entry.file_type() else {
            continue;
        };
        if !file_type.is_file() || file_type.is_symlink() {
            continue;
        }
        let Ok(relative) = path.strip_prefix(&root) else {
            continue;
        };
        if is_protected_workspace_path(relative) {
            continue;
        }
        let relative_path = relative.to_string_lossy().replace('\\', "/");
        let Ok(metadata) = fs::metadata(path) else {
            continue;
        };
        if metadata.len() > MAX_TEXT_FILE_BYTES {
            continue;
        }
        let remaining = options.max_results.saturating_sub(total_matches);
        let matches = match_file(
            path,
            &relative_path,
            &matcher,
            remaining.min(MAX_MATCHES_PER_FILE),
        )?;
        if matches.is_empty() {
            continue;
        }
        total_matches += u32::try_from(matches.len()).unwrap_or(0);
        files.push(json!({
            "relativePath": relative_path,
            "matches": matches,
        }));
    }

    Ok(json!({
        "files": files,
        "totalMatches": total_matches,
        "truncated": truncated,
    }))
}

fn compile_matcher(options: &SearchOptions) -> HostResult<Regex> {
    let source = if options.use_regex {
        options.query.clone()
    } else {
        regex::escape(&options.query)
    };
    let source = if options.whole_word {
        format!(r"\b(?:{source})\b")
    } else {
        source
    };
    RegexBuilder::new(&source)
        .case_insensitive(!options.case_sensitive)
        .multi_line(false)
        .build()
        .map_err(|error| HostError::state(format!("Invalid search pattern: {error}")))
}

fn build_overrides(
    root: &Path,
    include: Option<&str>,
    exclude: Option<&str>,
) -> HostResult<Option<ignore::overrides::Override>> {
    if include.is_none() && exclude.is_none() {
        return Ok(None);
    }
    let mut builder = OverrideBuilder::new(root);
    let mut any = false;
    if let Some(include) = include {
        for pattern in split_patterns(include) {
            add_override(&mut builder, &pattern, false)?;
            any = true;
        }
    }
    if let Some(exclude) = exclude {
        for pattern in split_patterns(exclude) {
            add_override(&mut builder, &pattern, true)?;
            any = true;
        }
    }
    if !any {
        return Ok(None);
    }
    builder
        .build()
        .map(Some)
        .map_err(|error| HostError::state(format!("Invalid search glob: {error}")))
}

fn add_override(builder: &mut OverrideBuilder, pattern: &str, exclude: bool) -> HostResult<()> {
    let prefixed = if exclude && !pattern.starts_with('!') {
        format!("!{pattern}")
    } else {
        pattern.to_string()
    };
    builder
        .add(&prefixed)
        .map_err(|error| HostError::state(format!("Invalid search glob: {error}")))?;
    if !pattern.contains('/') {
        let nested = if exclude {
            format!("!**/{pattern}")
        } else {
            format!("**/{pattern}")
        };
        builder
            .add(&nested)
            .map_err(|error| HostError::state(format!("Invalid search glob: {error}")))?;
    }
    Ok(())
}

fn split_patterns(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|pattern| !pattern.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn match_file(
    path: &Path,
    relative_path: &str,
    matcher: &Regex,
    limit: u32,
) -> HostResult<Vec<Value>> {
    let bytes = fs::read(path)
        .map_err(|error| HostError::state(format!("Could not read {relative_path}: {error}")))?;
    if bytes.contains(&0) || std::str::from_utf8(&bytes).is_err() {
        return Ok(Vec::new());
    }
    let mut matches = Vec::new();
    for (index, line) in bytes.split(|byte| *byte == b'\n').enumerate() {
        if matches.len() as u32 >= limit {
            break;
        }
        let Ok(line) = std::str::from_utf8(line) else {
            continue;
        };
        let line = line.trim_end_matches('\r');
        let Some(found) = matcher.find(line) else {
            continue;
        };
        let column = u32::try_from(found.start()).unwrap_or(0) + 1;
        let match_length = u32::try_from(found.end().saturating_sub(found.start())).unwrap_or(0);
        let line_content = if line.chars().count() > MAX_LINE_CONTENT_LENGTH {
            line.chars()
                .take(MAX_LINE_CONTENT_LENGTH)
                .collect::<String>()
        } else {
            line.to_string()
        };
        matches.push(json!({
            "id": format!("{relative_path}:{}:{}", index + 1, column),
            "line": index + 1,
            "column": column,
            "matchLength": match_length,
            "lineContent": line_content,
        }));
    }
    Ok(matches)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_case_insensitive_matches_and_skips_binary() {
        let workspace = tempfile::tempdir().unwrap();
        fs::write(workspace.path().join("readme.md"), "Hello Search World\n").unwrap();
        fs::write(workspace.path().join("binary.bin"), [0_u8, 1, 2, 3]).unwrap();
        let result = run_search(SearchOptions {
            workspace_path: workspace.path().to_string_lossy().into_owned(),
            query: "search".into(),
            case_sensitive: false,
            whole_word: false,
            use_regex: false,
            include_pattern: None,
            exclude_pattern: None,
            include_ignored: false,
            max_results: 20,
        })
        .unwrap();
        assert_eq!(result["totalMatches"], 1);
        assert_eq!(result["files"][0]["relativePath"], "readme.md");
        assert_eq!(result["files"][0]["matches"][0]["line"], 1);
    }
}
