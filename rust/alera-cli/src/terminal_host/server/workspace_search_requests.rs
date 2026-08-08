use alera_native::api::workspace_search::{
    preview_workspace_replace, replace_workspace_matches, search_workspace,
    WorkspaceReplaceFileExpectation, WorkspaceReplaceOptions, WorkspaceReplaceRequest,
    WorkspaceReplaceResult, WorkspaceSearchOptions, WorkspaceSearchResult,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceSearchRequest {
    workspace_path: String,
    query: String,
    case_sensitive: bool,
    whole_word: bool,
    use_regex: bool,
    include_pattern: Option<String>,
    exclude_pattern: Option<String>,
    include_ignored: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceReplaceAllRequest {
    #[serde(flatten)]
    search: WorkspaceSearchRequest,
    replacement: String,
    preserve_case: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceReplaceMatchesRequest {
    #[serde(flatten)]
    search: WorkspaceSearchRequest,
    replacement: String,
    preserve_case: bool,
    match_ids: Vec<String>,
    expected_files: Vec<WorkspaceReplaceFileExpectationRequest>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceReplaceFileExpectationRequest {
    relative_path: String,
    content_token: String,
}

pub(super) async fn search(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceSearchRequest = parse(payload)?;
    let result = tokio::task::spawn_blocking(move || search_workspace(request.into_options()))
        .await
        .map_err(|error| HostError::state(format!("Workspace Search Task Failed: {error}")))?
        .map_err(|error| HostError::state(error.context))?;
    Ok(search_result_value(result))
}

pub(super) async fn preview_replace(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceReplaceAllRequest = parse(payload)?;
    let preview = tokio::task::spawn_blocking(move || {
        preview_workspace_replace(WorkspaceReplaceOptions {
            search: request.search.into_options(),
            replacement: request.replacement,
            preserve_case: request.preserve_case,
        })
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace Replace Preview Task Failed: {error}")))?
    .map_err(|error| HostError::state(error.context))?;
    Ok(search_result_value(preview.result))
}

pub(super) async fn replace_all(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceReplaceAllRequest = parse(payload)?;
    let result = tokio::task::spawn_blocking(move || {
        let options = WorkspaceReplaceOptions {
            search: request.search.into_options(),
            replacement: request.replacement,
            preserve_case: request.preserve_case,
        };
        let preview = preview_workspace_replace(options.clone())?;
        let match_ids = preview
            .result
            .files
            .iter()
            .flat_map(|file| file.matches.iter().map(|item| item.id.clone()))
            .collect();
        let expected_files = preview
            .result
            .files
            .iter()
            .map(|file| WorkspaceReplaceFileExpectation {
                relative_path: file.relative_path.clone(),
                content_token: file.content_token.clone(),
            })
            .collect();
        replace_workspace_matches(WorkspaceReplaceRequest {
            options,
            match_ids,
            expected_files,
        })
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace Replace Task Failed: {error}")))?
    .map_err(|error| HostError::state(error.context))?;
    Ok(replace_result_value(result))
}

pub(super) async fn replace_matches(payload: &Value) -> HostResult<Value> {
    let request: WorkspaceReplaceMatchesRequest = parse(payload)?;
    let result = tokio::task::spawn_blocking(move || {
        replace_workspace_matches(WorkspaceReplaceRequest {
            options: WorkspaceReplaceOptions {
                search: request.search.into_options(),
                replacement: request.replacement,
                preserve_case: request.preserve_case,
            },
            match_ids: request.match_ids,
            expected_files: request
                .expected_files
                .into_iter()
                .map(|file| WorkspaceReplaceFileExpectation {
                    relative_path: file.relative_path,
                    content_token: file.content_token,
                })
                .collect(),
        })
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace Replace Task Failed: {error}")))?
    .map_err(|error| HostError::state(error.context))?;
    Ok(replace_result_value(result))
}

impl WorkspaceSearchRequest {
    fn into_options(self) -> WorkspaceSearchOptions {
        WorkspaceSearchOptions {
            workspace_path: self.workspace_path,
            query: self.query,
            case_sensitive: self.case_sensitive,
            whole_word: self.whole_word,
            use_regex: self.use_regex,
            include_pattern: self.include_pattern,
            exclude_pattern: self.exclude_pattern,
            include_ignored: self.include_ignored,
            max_results: None,
        }
    }
}

fn parse<T: for<'de> Deserialize<'de>>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|error| HostError::format(format!("Invalid Workspace Search Request: {error}")))
}

fn search_result_value(result: WorkspaceSearchResult) -> Value {
    json!({
        "files": result.files.into_iter().map(|file| json!({
            "relativePath": file.relative_path,
            "contentToken": file.content_token,
            "matches": file.matches.into_iter().map(|item| json!({
                "id": item.id,
                "line": item.line,
                "column": item.column,
                "matchLength": item.match_length,
                "lineContent": item.line_content,
                "displayColumn": item.display_column,
                "displayMatchLength": item.display_match_length,
                "replacementPreview": item.replacement_preview,
            })).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
        "totalMatches": result.total_matches,
        "truncated": result.truncated,
    })
}

fn replace_result_value(result: WorkspaceReplaceResult) -> Value {
    json!({
        "filesChanged": result.files_changed,
        "matchesReplaced": result.matches_replaced,
        "conflicts": result.conflicts.into_iter().map(|conflict| json!({
            "relativePath": conflict.relative_path,
            "reason": conflict.reason,
        })).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn searches_and_replaces_workspace_text() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(directory.path().join("note.txt"), "hello world").unwrap();
        let payload = json!({
            "workspacePath": directory.path(),
            "query": "world",
            "caseSensitive": false,
            "wholeWord": false,
            "useRegex": false,
            "includePattern": null,
            "excludePattern": null,
            "includeIgnored": false,
        });
        let result = search(&payload).await.unwrap();
        assert_eq!(result["totalMatches"], 1);
        let preview = preview_replace(&json!({
            "workspacePath": directory.path(),
            "query": "world",
            "caseSensitive": false,
            "wholeWord": false,
            "useRegex": false,
            "includePattern": null,
            "excludePattern": null,
            "includeIgnored": false,
            "replacement": "there",
            "preserveCase": false,
        }))
        .await
        .unwrap();
        assert_eq!(
            preview["files"][0]["matches"][0]["replacementPreview"],
            "there"
        );
        let replaced = replace_all(&json!({
            "workspacePath": directory.path(),
            "query": "world",
            "caseSensitive": false,
            "wholeWord": false,
            "useRegex": false,
            "includePattern": null,
            "excludePattern": null,
            "includeIgnored": false,
            "replacement": "there",
            "preserveCase": false,
        }))
        .await
        .unwrap();
        assert_eq!(replaced["matchesReplaced"], 1);
        assert_eq!(
            std::fs::read_to_string(directory.path().join("note.txt")).unwrap(),
            "hello there"
        );
    }
}
