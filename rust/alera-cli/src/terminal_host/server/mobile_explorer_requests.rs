use alera_core::runtime::RuntimeStore;
use serde_json::Value;

use crate::terminal_host::host_error::HostResult;

use super::mobile_workspace_file_requests::workspace_for_mobile_file_request;
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
    let entries = crate::remote_workspace_files::list_workspace_files(
        runtime_store,
        &workspace,
        &relative_path,
        hide_ignored,
    )
    .await
    .map_err(|error| crate::terminal_host::host_error::HostError::state(error.to_string()))?;
    Ok(crate::remote_workspace_files::entries_to_json(&entries))
}
