use alera_core::runtime::{RuntimeStore, LOCAL_HOST_ID};
use alera_core::workspace_search::{
    cancel_workspace_search, preview_workspace_replace, preview_workspace_replace_cancelable,
    replace_workspace_matches, search_workspace, search_workspace_cancelable,
    WorkspaceReplaceFileExpectation, WorkspaceReplaceOptions, WorkspaceReplaceRequest,
    WorkspaceReplaceResult, WorkspaceSearchError, WorkspaceSearchOptions, WorkspaceSearchResult,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::require_string_key;

pub(super) async fn handle_mobile_workspace_search_request(
    runtime_store: &RuntimeStore,
    client_id: u64,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    match request_type {
        "mobile.workspaceSearch.replace" => replace_mobile_workspace(runtime_store, payload).await,
        "mobile.workspaceSearch.cancel" => cancel_mobile_workspace_search(client_id, payload),
        _ => search_mobile_workspace(runtime_store, client_id, payload).await,
    }
}

async fn search_mobile_workspace(
    runtime_store: &RuntimeStore,
    client_id: u64,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "Search and replace are only available for workspaces on this runtime.",
        ));
    }
    let query = require_string_key(payload, "query")?;
    if query.is_empty() {
        return Ok(result_json(WorkspaceSearchResult {
            files: Vec::new(),
            total_matches: 0,
            truncated: false,
        }));
    }
    let search = search_options(workspace.path, query, payload);
    let replacement = payload
        .get("replacement")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let preserve_case = bool_key(payload, "preserveCase");
    let request_id = scoped_request_id(client_id, payload);
    spawn_blocking_workspace("Workspace search", move || {
        let result = match (replacement, request_id) {
            (Some(replacement), request_id) => {
                let options = WorkspaceReplaceOptions {
                    search,
                    replacement,
                    preserve_case,
                };
                match request_id {
                    Some(id) => preview_workspace_replace_cancelable(options, id),
                    None => preview_workspace_replace(options),
                }
                .map(|preview| preview.result)
            }
            (None, Some(id)) => search_workspace_cancelable(search, id),
            (None, None) => search_workspace(search),
        };
        result.map(result_json).map_err(search_error)
    })
    .await
}

async fn replace_mobile_workspace(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "Search and replace are only available for workspaces on this runtime.",
        ));
    }
    let query = require_string_key(payload, "query")?;
    if query.is_empty() {
        return Err(HostError::state("Run search before replacing."));
    }
    let replacement = payload
        .get("replacement")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let workspace_path = workspace.path.clone();
    let workspace_id = workspace.id.clone();
    let request = WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search: search_options(workspace.path, query, payload),
            replacement,
            preserve_case: bool_key(payload, "preserveCase"),
        },
        match_ids: string_list(payload, "matchIds"),
        expected_files: expected_files(payload),
    };
    spawn_blocking_workspace("Workspace replace", move || {
        let paths: Vec<_> = request
            .expected_files
            .iter()
            .map(|file| file.relative_path.clone())
            .collect();
        let result = replace_workspace_matches(request).map_err(search_error)?;
        let mut value = replace_result_json(result);
        value["workspaceId"] = json!(workspace_id);
        value["workspacePath"] = json!(workspace_path);
        value["relativePaths"] = json!(paths);
        Ok(value)
    })
    .await
}

fn cancel_mobile_workspace_search(client_id: u64, payload: &Value) -> HostResult<Value> {
    if let Some(request_id) = scoped_request_id(client_id, payload) {
        cancel_workspace_search(request_id);
    }
    Ok(json!({}))
}

/// Cancellation flags live in one process-wide table keyed by request id, so
/// the id is namespaced by client: a phone must not be able to cancel a search
/// another client started by guessing its id.
fn scoped_request_id(client_id: u64, payload: &Value) -> Option<String> {
    payload
        .get("requestId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(|value| format!("mobile:{client_id}:{value}"))
}

fn search_options(
    workspace_path: String,
    query: String,
    payload: &Value,
) -> WorkspaceSearchOptions {
    WorkspaceSearchOptions {
        workspace_path,
        query,
        case_sensitive: bool_key(payload, "caseSensitive"),
        whole_word: bool_key(payload, "wholeWord"),
        use_regex: bool_key(payload, "useRegex"),
        include_pattern: optional_pattern(payload, "includePattern"),
        exclude_pattern: optional_pattern(payload, "excludePattern"),
        include_ignored: bool_key(payload, "includeIgnored"),
        max_results: payload
            .get("maxResults")
            .and_then(Value::as_u64)
            .and_then(|value| u32::try_from(value).ok()),
    }
}

fn bool_key(payload: &Value, key: &str) -> bool {
    payload.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn optional_pattern(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn string_list(payload: &Value, key: &str) -> Vec<String> {
    payload
        .get(key)
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn expected_files(payload: &Value) -> Vec<WorkspaceReplaceFileExpectation> {
    payload
        .get("expectedFiles")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    Some(WorkspaceReplaceFileExpectation {
                        relative_path: item.get("relativePath")?.as_str()?.to_string(),
                        content_token: item.get("contentToken")?.as_str()?.to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn search_error(error: WorkspaceSearchError) -> HostError {
    HostError::state(error.context)
}

fn result_json(result: WorkspaceSearchResult) -> Value {
    // Leave room for the encrypted relay envelope and bound repeated previews.
    const RESPONSE_BYTES: usize = 256 * 1024;
    const PREVIEW_BYTES: usize = 16 * 1024;
    let mut remaining = RESPONSE_BYTES - 1024;
    let mut truncated = result.truncated;
    let mut files = Vec::new();
    for file in result.files {
        let mut value = json!({
            "relativePath": file.relative_path,
            "contentToken": file.content_token,
            "matches": [],
        });
        let overhead = value.to_string().len() + 1;
        if overhead > remaining {
            truncated = true;
            break;
        }
        remaining -= overhead;
        let mut matches = Vec::new();
        for m in file.matches {
            if m.replacement_preview
                .as_ref()
                .is_some_and(|text| text.len() > PREVIEW_BYTES)
            {
                truncated = true;
                continue;
            }
            let entry = json!({
                "id": m.id,
                "line": m.line,
                "column": m.column,
                "matchLength": m.match_length,
                "lineContent": m.line_content,
                "displayColumn": m.display_column,
                "displayMatchLength": m.display_match_length,
                "replacementPreview": m.replacement_preview,
            });
            let bytes = entry.to_string().len() + 1;
            if bytes > remaining {
                truncated = true;
                continue;
            }
            remaining -= bytes;
            matches.push(entry);
        }
        if !matches.is_empty() {
            value["matches"] = json!(matches);
            files.push(value);
        }
    }
    json!({
        "files": files,
        "totalMatches": result.total_matches,
        "truncated": truncated,
    })
}

fn replace_result_json(result: WorkspaceReplaceResult) -> Value {
    let conflicts = result
        .conflicts
        .into_iter()
        .map(|conflict| {
            json!({
                "relativePath": conflict.relative_path,
                "reason": conflict.reason,
            })
        })
        .collect::<Vec<_>>();
    json!({
        "filesChanged": result.files_changed,
        "matchesReplaced": result.matches_replaced,
        "conflicts": conflicts,
    })
}

#[cfg(test)]
#[path = "mobile_workspace_search_requests_tests.rs"]
mod tests;
