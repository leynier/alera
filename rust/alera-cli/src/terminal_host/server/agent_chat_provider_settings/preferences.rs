use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::AgentChatPreferenceOperation;
use serde_json::{json, Value};

pub(super) fn operations(payload: &Value) -> HostResult<Vec<AgentChatPreferenceOperation>> {
    let operations = payload["operations"]
        .as_array()
        .ok_or_else(|| HostError::format("operations must be an array"))?;
    if operations.is_empty() || operations.len() > 100 {
        return Err(HostError::format("Invalid preference operation count."));
    }
    let mut edits = Vec::new();
    for operation in operations {
        let (section, key, value) = match operation["type"].as_str() {
            Some("setDefaultSelection") => (
                "defaultSelection",
                None,
                operation.get("selection").cloned(),
            ),
            Some("setProjectDefault") => (
                "projectDefaults",
                Some(text(operation, "projectId")?),
                operation.get("selection").cloned(),
            ),
            Some("setModels") => (
                "models",
                Some(text(operation, "providerInstanceId")?),
                Some(json!({"hidden":operation["hidden"],"order":operation["order"]})),
            ),
            Some("setFavorites") => ("favorites", None, Some(operation["favorites"].clone())),
            _ => return Err(HostError::format("Unknown preference operation.")),
        };
        if value.is_none() {
            return Err(HostError::format("Preference value is required."));
        }
        edits.push(AgentChatPreferenceOperation {
            section: section.into(),
            key,
            value,
        });
    }
    Ok(edits)
}

pub(super) fn text(payload: &Value, key: &str) -> HostResult<String> {
    payload[key]
        .as_str()
        .filter(|value| !value.trim().is_empty() && value.len() <= 4096 && !value.contains('\0'))
        .map(str::to_owned)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}

pub(super) fn revision(payload: &Value) -> HostResult<i64> {
    payload["expectedRevision"]
        .as_i64()
        .filter(|value| *value >= 0)
        .ok_or_else(|| HostError::format("expectedRevision is required"))
}
