//! Schema pieces and argument helpers shared by the injected `chat_*` tools.

use serde_json::{json, Value};

use crate::mcp_tools::{ToolArguments, ToolInputError};

pub(super) const RUNTIME_MODES: &[&str] = &[
    "approval-required",
    "auto-accept-edits",
    "auto",
    "full-access",
];
pub(super) const INTERACTION_MODES: &[&str] = &["default", "plan"];

/// A delegation target: exactly one existing chat, existing workspace, or new
/// workspace.
pub(super) fn target_schema() -> Value {
    json!({
        "type": "object",
        "description": "Exactly one target object: chat, workspace, or newWorkspace.",
        "minProperties": 1,
        "maxProperties": 1,
        "additionalProperties": false,
        "properties": {
            "chat": {"type": "object"},
            "workspace": {"type": "object"},
            "newWorkspace": {"type": "object"},
        },
    })
}

/// A required object argument, serialized as the JSON a CLI option carries.
pub(super) fn object_json(arguments: &ToolArguments, name: &str) -> Result<String, ToolInputError> {
    arguments
        .object(name)
        .map(|value| Value::Object(value.clone()).to_string())
        .ok_or_else(|| ToolInputError(format!("Missing object argument {name}.")))
}

/// An optional object argument, serialized as the JSON a CLI option carries.
pub(super) fn object_json_optional(
    arguments: &ToolArguments,
    name: &str,
) -> Result<Option<String>, ToolInputError> {
    Ok(arguments
        .object(name)
        .map(|value| Value::Object(value.clone()).to_string()))
}
