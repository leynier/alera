use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};

use crate::terminal_host::host_error::HostResult;

use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::optional_string_key;

pub(super) async fn list_mobile_workspace_explorer(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let relative_path = optional_string_key(payload, "relativePath").unwrap_or_default();
    let hide_ignored = payload
        .get("hideIgnored")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    let root = workspace.path.clone();
    spawn_blocking_workspace("Workspace explorer list", move || {
        let entries = alera_core::workspace_files::list_workspace_children(
            &root,
            &relative_path,
            hide_ignored,
        )
        .map_err(|error| crate::terminal_host::host_error::HostError::state(error.to_string()))?;
        Ok(json!({
            "entries": entries
                .into_iter()
                .map(|entry| json!({
                    "relativePath": entry.relative_path,
                    "name": entry.name,
                    "kind": entry.kind.as_str(),
                    "size": entry.size,
                    "isHidden": entry.is_hidden,
                    "hasChildrenHint": entry.has_children_hint,
                }))
                .collect::<Vec<_>>(),
        }))
    })
    .await
}
